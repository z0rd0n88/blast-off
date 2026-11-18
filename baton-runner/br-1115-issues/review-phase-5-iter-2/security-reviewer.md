# security-reviewer: phase 5 fix round 1 (35c07d3..d059301), review round 2

Scope: `git diff 35c07d3..d059301 -- . ':!baton-runner'` (lib/chain.sh, lib/preflight.sh, tests 10/21/50/60, docs/spec.md), read against the phase diff `c4e2a41...d059301`, `review-phase-5-iter-1.md` and `baton-phase-5-fix-1.md`. Static review only. No tests, no gate, no state-changing git. The only shell runs were print-only probes in the scratchpad: bash 5.2.21 xtrace, NUL bytes in command substitution, `stat -L` on a `/proc` link, and `SHELLOPTS` import.

## Summary

**0 CRITICAL, 0 HIGH, 0 MEDIUM, 12 LOW.** The fix does what it says:

- **P5R1-5 is closed for `child-count`.** No path in `lib/` or `bin/` puts the file's content into run.log, `status`, `preflight` or the journal any more. The one remaining way is owner-enabled xtrace (SR2-6).
- **P5R1-4 is closed.** Every JOB_* value that reaches arithmetic is checked first, and nothing in the repo passes a leading-zero value.
- **Both `chain_nums` callers are safe under `set -e`.**

The LOWs are test-pinning gaps, small diagnostic and doc inaccuracies, and pre-existing items in the same class that this fix did not make worse.

| ID | Sev | Title |
|---|---|---|
| SR2-1 | LOW | Q5 "never the content" is pinned by one token (`job done`) only; a first-line or single-line echo mutant survives (the symlink-to-secret half) |
| SR2-2 | LOW | `NUMS_ERR` prints the raw JOB_* value, so a value with a newline can put a `preflight: ok` line in preflight stdout, or a forged journal entry |
| SR2-3 | LOW | `stat -L` byte size follows a symlink and shows the linked file's length. This is within Q5 and of negligible value |
| SR2-4 | LOW | The byte size is a second filesystem read: 0 for `/proc` and special files, possibly another file's size (race), `( bytes;` when stat fails |
| SR2-5 | LOW | Spec and comment say every refusal names the "byte size and the shape it wants"; the cannot-read branch gives neither, and its cause list is incomplete |
| SR2-6 | LOW | Owner-enabled xtrace (`bash -x`, or `SHELLOPTS=xtrace` exported) still prints child-count's content raw, newlines included, to stderr |
| SR2-7 | LOW | Pre-existing: run.log stays forgeable by other child-written content (last message, non-JSON payload), so Q5's "forge" rationale covers child-count only |
| SR2-8 | LOW | Pre-existing, at the edge of Q3: `JOB_JEV` is unvalidated, and `00`, ` 0` or `false` turn Jev on (row text goes to OpenRouter) when the owner meant off |
| SR2-9 | LOW | Pre-existing, outside Q3: numeric `BLAST_OFF_*` values are unvalidated; garbage makes `[` fail as false (the trust dialog is never answered) |
| SR2-10 | LOW | Pre-existing, owner input: `JOB_BASE` goes to `git fetch` as a positional with no guard against a leading `-` (option injection; not verified) |
| SR2-11 | LOW | The leading-zero refusal is untested for `JOB_RESUME_MARGIN` (the variable whose arithmetic actually read octal) and `JOB_API_BACKOFF` |
| SR2-12 | LOW | Informational: a `child-count` of `1 0\0` is accepted (bash drops the NUL with a content-free warning). No leak; the parse is lenient |

## Focus answers

### 1. Is P5R1-5 closed?

Yes, for every path in the product code.

- **Readers.** `chain_count` (lib/chain.sh:123) is the only reader of `child-count`; `chain_count_set` only writes it. Its callers are `chain_run` (:148), `unit_status` (lib/units.sh:74) and `preflight_run` (lib/preflight.sh:31). `grep child-count bin lib` finds no other reader.
- **cat's stderr.** It goes to `2>/dev/null` (:127). When cat fails, a fixed text replaces partial output, so a partial read is never kept.
- **The content variable `c`.** It is used only in `[[ =~ ]]`, which prints nothing. `BASH_REMATCH` goes into `LAUNCHED`, `BASE` and `COUNT_SAY` only after the match, so it is digits only. Bash's ERE has no REG_NEWLINE, so `^...$` anchors to the whole string, and a multi-line value never matches.
- **stat's output.** stdout is `%s`, which is digits. stderr, only on failure, carries the path and errno, never content (SR2-4).
- **Error messages.** `COUNT_ERR` holds `$f` (`$JOB/child-count`, the link's own path, not its target), the size and fixed text. `log` writes it to run.log and, through `>&2`, to stderr, which is the journal under the unit. `unit_status` and `preflight_run` echo `COUNT_ERR` only.
- **Bash warnings.** The `ignored null byte` warning text carries no content (probe, SR2-12).
- **set -x.** Nothing in lib/ or bin/ sets xtrace. The unit passes only named variables (`unit_env`), and `SHELLOPTS` is not one of them. Only an owner who turns xtrace on in a foreground shell sees the content (SR2-6).
- **The journal.** It sees only what the runner writes to stderr and stdout. `COUNT_ERR` has no content, and `die "$NUMS_ERR"` carries the owner's env value, not the file.
- **run.log.** It is no longer forgeable through `child-count`, but it still is through child_report (SR2-7, pre-existing).

**Is the byte size within Q5?** Yes. Q5 says "names the file and byte size only", and that is exactly what is shown. `stat -Lc %s` follows a symlink, so a link to a secrets file shows that file's length. That is negligible: children run as the same user and can read the target directly, so this crosses no boundary. A secret's length is also usually public (fixed token formats). See SR2-3, and SR2-4 for accuracy.

### 2. P5R1-4: octal and arithmetic injection

Every use of a JOB_* value in lib/ and bin/:

- **`JOB_CAP_FACTOR`:** `$((phases * …))` at chain.sh:109, through `chain_cap`.
- **`JOB_MAX_CHILDREN`:** reaches `MAXC`, which is used in `[ -gt ]` at chain.sh:200 and in `$((MAXC - …))` at preflight.sh:33.
- **`JOB_RESUME_MARGIN`:** `$((reset + …))` at usage.sh:45, through `usage_pause`, which only `chain_run` calls.
- **`JOB_USAGE_PAUSE`:** `jq --argjson` at usage.sh:21, through `usage_read` in `chain_run` and `pf_usage`.
- **`JOB_CHILD_TIMEOUT`:** reaches `TIMEOUT`, which is used in `[ -le ]` at child.sh:87.
- **`JOB_API_BACKOFF`:** passed to `sleep`.

**Order.** Every one of them runs after `chain_nums`:

- In `chain_run`, `chain_nums` is at :146. Before it there is only the string assignment `TIMEOUT=` (:144) and checks that do no arithmetic.
- In `preflight_run`, it is at :15, before `chain_cap` (:27) and `pf_usage` (:41).
- `status`, `resume`, `start`, `receipt`, `ci-wait` and `logs` do no arithmetic on JOB_*. `usage_until` reads only the checkpoint.

The new regex `^(0|[1-9][0-9]{0,8})$` admits only decimal digits with no leading zero. So the octal reading (`010` as 8) and the `08` "value too great for base" abort are gone. Arithmetic injection (`a[$(cmd)]`) was already blocked by the old digits-only regex, and it stays blocked.

**NUMS_ERR echoes the raw env value.** The value is the owner's own environment. A child cannot set the runner's env or the env passed by the resume timer through `--setenv`. The run path's message is the same as before the fix: the old `die` text already embedded `${!v}`. The preflight path is new: before the fix it died to stderr, and now it prints a `preflight: refused:` line to stdout. A newline in the value can therefore put a line that reads exactly `preflight: ok` into stdout, though the exit code stays 1 (SR2-2). Under `set -u`, `${!v}` is expanded only when the regex failed, and the regex fails only on a set, non-matching value, so there is no unbound-variable abort.

### 3. Regressions

- **Leading-zero values in the repo.** A grep of bin, lib, tests, templates, .github, README and the skill for `JOB_*=0[0-9]` finds only the deliberate bad values in tests 21 and 60. bin/blast-off's header defaults are `7200`, `3`, `95`, `60`, `600`, `1`, none with a leading zero. No unit file carries an `Environment=` JOB_* default.
- **Callers under `set -e`.**
  - `chain_run` uses `chain_nums || die`, and `preflight_run` uses `chain_nums || { echo …; exit 1; }`. Both run `chain_nums` on the left of `||`, so `return 1` never trips errexit. `chain_nums` has no other caller.
  - `chain_count` is called through `||` (chain_run) and `if` (status, preflight). So a failing `$(stat …)` inside the `COUNT_ERR=` assignment cannot abort the runner either.
- **Q3's stricter rule on non-arithmetic variables.** `JOB_CHILD_TIMEOUT`, `JOB_API_BACKOFF` and `JOB_USAGE_PAUSE` never read as octal: `[ ]` and `sleep` read decimal, and jq rejects `095` as JSON. Refusing them is a behaviour change the owner ordered, not a regression.

### 4. Are the docs true?

Mostly. The spec's exit-1 row, preflight row and test rows 10, 21, 50 and 60 match the code. There are three gaps:

- **The `JOB_MAX_CHILDREN` paragraph** says a refusal shows "the file's name, byte size and the shape it wants". That holds for the shape branch only. The cannot-read branch (a dangling link, a directory, and others) shows neither the size nor the shape (SR2-5).
- **The chain.sh:121 comment** has the same overstatement.
- **The preflight row** says "(exit 1, every line still printed)" and later "a JOB_* count … is refused at once, before any other line". The second sentence qualifies the first; it reads a little contradictory, but it is accurate.

## Findings

### SR2-1 LOW: Q5's "never the content" is pinned by one token, and a first-line or single-line echo mutant survives

- **Where:** tests/10-chain-done.sh:140-145 and tests/60-preflight.sh:196-209.
- **Failure path:** Both forged cases write `1 0\n2099-01-01T00:00:00Z job done\n` and assert only that `job done` does not appear. p9 (`x`) asserts the refusal prefix and `(2 bytes; `, but not that `x` is absent. A regression that adds back part of the content, such as `holds '${c%%$'\n'*}'` (the first line only), passes every test:
  - In test 10, `'1 0'` is shown and `job done` is not.
  - In p10, the same.
  - In p9, the prefix still matches.

  That brings back the security half of P5R1-5 that Q5 settled: a single-line secret reached through a `child-count` symlink shows up in run.log. No test has a symlink to a regular file holding garbage. The existing link case is dangling, so it goes down the cannot-read branch.
- **Fix:** In test 10, add a `child-count` symlink to a one-line file that holds a unique sentinel (for example `SENTINEL-8f3a`). Do the same in p9, or make p9's content that sentinel. Assert the sentinel appears in none of run.log, run's stdout and stderr, `status`, or `preflight`.

### SR2-2 LOW: `NUMS_ERR` prints the raw JOB_* value, so a newline can forge a `preflight: ok` line or a journal entry

- **Where:** lib/chain.sh:93 and lib/preflight.sh:15. The run path is lib/chain.sh:146 (`die`, stderr, which is the journal under the unit).
- **Failure path:** Take `JOB_MAX_CHILDREN=$'1\npreflight: ok\n'`. The regex fails, because `$` anchors to the end of the string. preflight then prints `preflight: refused: JOB_MAX_CHILDREN='1`, then the line `preflight: ok`, then `' is not a whole number …`, and exits 1.
  - A reader or script that greps `^preflight: ok$` sees a pass. The blast-off skill's step 6 has an agent read these lines.
  - Under the unit, journald splits the `die` text into separate entries, one of them forged.
  - Terminal escape sequences pass through raw as well.

  The input is the owner's own environment, and no child or file can set it, so this is a robustness gap, not a boundary crossing. The run path's text is unchanged from before the fix; the stdout path in preflight is new in this fix.
- **Fix:** Quote the value with `printf -v q %q "${!v}"` and use `$q`. Or follow Q5's model and print the name and length only (`JOB_MAX_CHILDREN (3 chars) is not …`).

### SR2-3 LOW: the `stat -L` byte size follows a symlink and shows the linked file's length

- **Where:** lib/chain.sh:131.
- **Failure path:** A child runs `ln -s ~/.secrets child-count`. `cat` succeeds, the shape check fails, and run.log, status and preflight show `(N bytes; …)`, where N is the size of `~/.secrets`.
  - This is within Q5 ("byte size only") and has negligible value: the child runs as the same user and can read the target itself.
  - If a job dir with its run.log were ever committed or pushed, it would disclose a secret file's length. That is usually public anyway, given fixed token formats.

  The message names the link path, not the target, which is good.
- **Fix:** None needed under Q5. If wanted, report the size of what was read (see SR2-4), or report `a symlink` instead of a size when `[ -L "$f" ]`.

### SR2-4 LOW: the byte size comes from a second filesystem read and can be wrong or empty

- **Where:** lib/chain.sh:131 (`$(stat -Lc %s "$f")`).
- **Failure path:** There are three cases.
  - **Special files.** For `/proc` and other special files, `stat` reports 0. The probe on a link to `/proc/self/environ` printed `0`, so the message says `0 bytes` for a file that had content.
  - **A replaced file.** A child that replaces or retargets the file between `cat` (:127) and `stat` gets another file's size reported.
  - **A removed file.** A child that removes it in that window makes `stat` fail. The message then reads `( bytes; …`, and stat's own error (path and errno, no content) goes to stderr. None of this aborts, because `chain_count` always runs under `||` or `if`.

  These are diagnostic-accuracy problems only; nothing leaks.
- **Fix:** Use the length of what was read, with no second filesystem access: `local LC_ALL=C; … (${#c} bytes read; …`. Note that `$( )` strips trailing newlines and drops NULs, so word it as "bytes read". Or keep `stat` and add `2>/dev/null || echo '?'`.

### SR2-5 LOW: the docs promise "byte size and the shape it wants" for every refusal, and the cannot-read branch gives neither

- **Where:** docs/spec.md:61 (the `JOB_MAX_CHILDREN` paragraph: "… or a dangling symlink, exits 1 … (the file's name, byte size and the shape it wants, never its content …)"); lib/chain.sh:121 comment; lib/chain.sh:128.
- **Failure path:** A dangling link, a directory or an unreadable file goes down the cannot-read branch. That branch prints `cannot read <f> (a dangling link, a directory, or no read permission)`, with no size and no wanted shape, so the spec's sentence is false for the dangling-symlink case it names in the same breath.
  - Its cause list is also a guess. A symlink loop (ELOOP), a socket (ENXIO) or EIO land there too and are misdescribed.
  - Since `cat`'s errno is discarded, the owner cannot tell which cause applies. Dropping it was a deliberate trade, noted in the fix baton.
- **Fix:**
  - **Spec:** "names the file, and for content of the wrong shape its byte size and the shape it wants; never its content".
  - **Message:** for example, "cannot read <f> (not a readable regular file or link to one)". Or keep `cat`'s errno through a separate `2>` capture of the error text only, `cat`'s own `strerror`, which holds no content, for example `err=$(cat "$f" 2>&1 >/dev/null)`. Note that this reads the file twice.

### SR2-6 LOW: owner-enabled xtrace still prints child-count's content raw

- **Where:** lib/chain.sh:127.
- **Failure path:**
  - If the owner runs `bash -x bin/blast-off run|status|preflight …`, bash 5.2 traces `+ c='1 0` followed by the line `2099 job done'` to stderr (probe). That second line starts the same as the forged `2099-01-01T00:00:00Z job done` line, with a trailing quote.
  - Bash also imports `SHELLOPTS` from the environment (probe: `env SHELLOPTS=xtrace bash -c 'x=1'` traces). So an owner shell that exports `SHELLOPTS` with xtrace does the same, without `-x`.

  The unit does not pass `SHELLOPTS` (`unit_env` lists names), so `start` and the resume timer are not affected. This only matters when the owner is debugging, and the owner already has the file. It is informational.
- **Fix:** None recommended. If wanted, wrap the read in `{ local -; set +x; } 2>/dev/null`.

### SR2-7 LOW (pre-existing, not made worse): run.log stays forgeable through other child-written content

- **Where:** lib/child.sh:114 (the first 200 bytes of a non-JSON Stop payload) and :120 (`last_assistant_message`, verbatim and multi-line), both into run.log. lib/child.sh:~95-100 writes a dead child's last screen there as well.
- **Failure path:** A child whose last message contains the line `2099-01-01T00:00:00Z job done` writes that line into run.log. So Q5's rationale ("a second line could forge a `run.log` line") is closed for `child-count` only, and run.log is still not a record a child cannot write into. `child_field` is sanitised (`tr -cd 'A-Za-z0-9_-'`), so the API-error line is safe.
- **Fix:** Owner decision. Either say in the spec that lines between `--- child's last message ---` and `---` are the child's own text, or indent and prefix each child-supplied line (for example `| `) so it can never start a line with a timestamp.

### SR2-8 LOW (pre-existing; at the edge of Q3): `JOB_JEV` is unvalidated, and off-looking values turn Jev on

- **Where:** lib/jev.sh:29 (`[ "${JOB_JEV:-1}" = 0 ]`); `chain_nums` (lib/chain.sh:91) does not list `JOB_JEV`.
- **Failure path:** An owner who means "no Jev" sets `JOB_JEV=00`, `' 0'`, `false` or `no`. Only the exact string `0` disables Jev, so with an OpenRouter key present each first open Phase plan row's text is sent to OpenRouter. This fails open, toward data leaving the machine. Q3 says "every JOB_* number". `JOB_JEV` is a 0/1 flag, so it is arguably outside that ruling, but `00` is precisely the leading-zero case.
- **Fix:** Refuse anything but `0` or `1` (for example `[[ ${JOB_JEV:-1} =~ ^[01]$ ]]`) in `chain_nums`, or in a sibling check that `chain_run` and `preflight_run` both call.

### SR2-9 LOW (pre-existing; outside Q3's JOB_* scope): numeric `BLAST_OFF_*` values are unvalidated

- **Where:**
  - lib/child.sh:88 (`[ "$el" -lt "${BLAST_OFF_TRUST_SECONDS:-60}" ]`).
  - lib/ci.sh:21 (`BLAST_OFF_CI_APPEAR`).
  - lib/ci.sh:26 and :132 (`timeout "${BLAST_OFF_CI_WATCH…}"`, `"${BLAST_OFF_CI_HEAD…}"`).
- **Failure path:** These use `[ ]` and `timeout`, both of which read decimal, so there is no octal reading and no arithmetic injection; this fix is not required to cover them. A garbled value, though, makes `[` print an error and return 2:
  - A garbled `BLAST_OFF_TRUST_SECONDS` means the trust dialog is never answered, so each child hangs until `JOB_CHILD_TIMEOUT`. The only trace is a `[: integer expression expected` on stderr.
  - A garbled `BLAST_OFF_CI_APPEAR` ends the wait for runs at once.
  - A garbled `BLAST_OFF_CI_WATCH` makes `timeout` fail with 125, which is recorded as a failure rather than a timeout.
- **Fix:** Add the four names to `chain_nums`'s list, or to a second list checked by `run`, `ci-wait` and `preflight`.

### SR2-10 LOW (pre-existing; owner input; not verified): `JOB_BASE` can be read by `git fetch` as an option

- **Where:** lib/preflight.sh:139 (`git -C "$WORKDIR" fetch -q origin "$base"`) and :140 (`"HEAD..origin/$base"`).
- **Failure path:** git's option parser for `fetch` permutes arguments (it does not stop at the first non-option). A `JOB_BASE` starting with `-`, for example `--upload-pack=<cmd>`, would be taken as an option. With a local-path or `ext::` remote, that runs a command locally. This was not run (no state-changing git). The input is the owner's environment, so this crosses no boundary; it is a hardening note.
- **Fix:** Refuse a `JOB_BASE` that starts with `-` or fails `git check-ref-format --branch "$base"` before use.

### SR2-11 LOW: the leading-zero refusal is untested for `JOB_RESUME_MARGIN` and `JOB_API_BACKOFF`

- **Where:** tests/21-soft-cap.sh:86 (bad values only for `JOB_MAX_CHILDREN`, `JOB_CAP_FACTOR` and `JOB_CHILD_TIMEOUT`); tests/30-paused-limit.sh:174 (`JOB_USAGE_PAUSE=9x`); tests/60-preflight.sh:211-216 (`JOB_MAX_CHILDREN` only).
- **Failure path:** `JOB_RESUME_MARGIN` is one of the variables whose arithmetic really read octal: `$((reset + 010))` at usage.sh:45. Yet a mutant that drops `JOB_RESUME_MARGIN`, or `JOB_API_BACKOFF`, from `chain_nums`'s `for` list survives every test. Partly pre-existing (P4R2-9 tested from one side only), but the octal rationale is new to this fix.
- **Fix:** Add `JOB_RESUME_MARGIN=010` and `JOB_API_BACKOFF=x` (or `08`) to test 21's bad-value loop.

### SR2-12 LOW (informational): a NUL byte is dropped before the shape check

- **Where:** lib/chain.sh:127-130.
- **Failure path:** The probe shows `printf '1 0\0' > child-count` is accepted as `1 0`. Bash drops the NUL from `$( )` and prints `warning: command substitution: ignored null byte in input`, which holds no content, to stderr; that is the journal under the unit, or `status` and `preflight` output. `1 0\0junk` becomes `1 0junk` and is refused. No leak; the parse is slightly lenient, and the warning is noise.
- **Fix:** None needed. If wanted, read with `read -r -d ''`, or check `tr -d '\0'` length against `stat` size, which is not worth it.

## Not re-filed (round-1, still open, not made worse)

- **P5R1-6.** `chain_nums` refusals under `run` still go only to stderr and the journal; the same `die` as before.
- **P5R1-12.** `cat` on a FIFO or `/dev/zero` link still blocks or grows memory. `stat -L` does not open the file, so it adds no new hang.
- **P5R1-26.** A link to a valid-shaped file is still read through and then replaced.
- **P5R1-29.** run.log and `child-count.tmp` are still written through planted symlinks.

None of these is worse after this fix.
