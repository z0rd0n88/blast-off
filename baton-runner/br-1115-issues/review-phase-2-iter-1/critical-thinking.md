### Summary

I read the five-file diff of 5062c7d in full, plus `lib/receipt.sh`, `lib/ci.sh`, `scripts/gate.sh`, `tests/lib.sh`, `docs/spec.md` section 6, excerpts of `lib/units.sh` and `lib/child.sh`, the work baton, the task plan, the phase 1 digest and review-2 baton, and issue 31. Static work only: no scenario, `tests/run`, `scripts/gate.sh` or `bin/blast-off` was run. Checks made: `bash -n` and `shellcheck -S warning` on the three changed scripts (both clean), a PyYAML parse of `ci.yml`, greps for every verdict reader, read-only `gh`, and inline bash probes of the splitting and matching expressions that execute no repo file.

The receipt path does what criterion 2 asks: every in-repo reader of a verdict line anchors on `"GATE: "` (`lib/receipt.sh:8,31,38,60`) and none accepts `GATE-ONLY:`. The input reaches the shell only through `env:` (`ci.yml:51`); the `run:` text (`ci.yml:52-56`) holds no expression, so I found no shell or YAML injection.

The change rests on one assumption nobody wrote down: that the verdict line is the only thing anyone reads. Two readers key on something else. `blast-off ci-wait` reads run conclusions, and `scripts/gate.sh` and the baton contract read the exit status. A filtered pass is `success` and exit 0 to both. The work baton's "dispatch runs are not PR checks, so nothing gates on it" is contradicted by `lib/ci.sh:19`. Items 1 and 2 are the ones I would want answered before merge. Item 3 is a spec sentence the code falsifies. The rest are test gaps, doc gaps and edge cases.

### Findings

**1. `ci-wait` counts a filtered dispatch run as CI for the PR head**

- **Item:** `lib/ci.sh:19` and `:29` list runs with `gh run list --commit "$sha" --limit 100 --json databaseId`: no `--event`, no `--workflow`. `:35-41` record only `{id, name, conclusion}` and call the head `success` when every conclusion is success, skipped or neutral. A filtered run that passes concludes `success` and is named `ci` like the full run (`ci.yml` has no `run-name`; parsed: `run-name: None`).
- **Why it matters:** Dispatching `ci` on a PR head is real practice here: `gh run list --workflow ci` shows a `workflow_dispatch` and a `pull_request` run on the same sha `ed18476` (branch `fix/ci-dead-status`, 2026-11-11). Before this diff every dispatch ran the whole suite, so counting it was sound. After it:
  - A green one-scenario dispatch is a `success` run in `ci-pr-<n>.json`, with nothing to tell it from the gate. Where the head has no `pull_request` run (GitHub starts none for a PR with merge conflicts; that is documented behaviour, not observed here), `ci-wait` itself flips from exit 10 with a record of `absent` ("absent checks are not a pass", `lib/ci.sh:11`) to exit 0 with a record of `success`, on one scenario. The runner's `ci_check` already lets an `absent` record through at `done`, logged as not a pass (`lib/ci.sh:59`), so what changes is `ci-wait`'s exit code, the record and the log line, not whether `done` is reached. The receipt design exists to stop a child shortcutting the gate; this is the same shortcut on the CI reader.
  - A red filtered dispatch (a typo'd name, or the flake being reproduced) makes `ci-wait` exit 10 for that head with the advice "fix and push if red", though no code is wrong.
  - The work baton says "Dispatch runs are not PR checks, so nothing gates on it." `lib/ci.sh:19` gates on it.
- **What to verify or decide:** Should `ci-wait` count a run that was filtered, and if not, what in a run's metadata lets it tell? UNREPRODUCED (runs forbidden in this review; needs GitHub). After the branch is pushed and has a PR: `gh workflow run ci --repo z0rd0n88/blast-off --ref <PR head branch> -f only=70-docs`, then `gh run list --repo z0rd0n88/blast-off --commit <head sha> --json event,name,conclusion`. Expected: two rows named `ci`, events `pull_request` and `workflow_dispatch`, both `success`; `blast-off ci-wait <job-dir> <pr>` then lists both under `runs` and writes `verdict: success`.

**2. A filtered pass exits 0, and some readers key on the exit status, not the line**

- **Item:** `tests/run:88-89` exits 0 on `GATE-ONLY: PASS`. `scripts/gate.sh:10` runs `tests/run` with the caller's environment and passes its status through; its header (`:2-4`) still says "every scenario" and "the last line is its GATE: PASS|FAIL verdict". The phase 1 baton states the rule as "CLEAN by the contract's rule: gate exit 0" (`baton-phase-1-review-2.md`, "Where things stand"). The GitHub step goes green on exit 0.
- **Why it matters:** `BLAST_OFF_TEST_ONLY` is ambient. The repo already defends against the owner's environment leaking in (`ci.yml:53-54` unsets five `JOB_*` names; `tests/lib.sh:10` unsets the Jev keys). Nothing clears the new variable in `scripts/gate.sh`. A session that exported it for a diagnosis and then runs the gate gets exit 0 from one scenario. `blast-off start` does not pass it to a unit (`lib/units.sh:19-23` lists the names), but `blast-off run` from a shell does reach the child: `lib/child.sh:13,21` scrubs only `CLAUDE*`.
- **What to verify or decide:** Why does a run that "is not the gate" exit with the gate's success status, and which callers (the baton contract, `scripts/gate.sh`, any `tests/run && ...`) have been checked to read the line and not the status? Not run.

**3. A filtered run can still end in a `GATE:` line: the keep-dir refusal runs before the filter is read**

- **Item:** `tests/run:30` (`no_keep`) prints the hard-coded `GATE: FAIL passed=0 failed=1 shellcheck=skipped` and exits at `:32-33`, before `only` is parsed at `:39`. `docs/spec.md:216` says a filtered run ends `GATE-ONLY: PASS` or `GATE-ONLY: FAIL`, "never a `GATE:` line"; the header (`tests/run:12-14`) says the same.
- **Why it matters:** The spec sentence has a counter-example in the code. `receipt_verdict` accepts that line (`lib/receipt.sh:8`; my probe: `[[ "GATE: FAIL ..." == "GATE: "* ]]` is true), so `blast-off receipt` writes a FAIL receipt for a filtered run instead of refusing it. Harm is small (exit 1, the runner refuses FAIL), but "refuses the log" is the stated contract. No test sets both variables.
- **What to verify or decide:** Is "never a `GATE:` line" meant to hold for every exit path of a filtered run, or only the ones after `:39`? UNREPRODUCED (runs forbidden in this review). Fixture-dir command, no `install_units`: `d=$(mktemp -d); mkdir "$d/fix"; printf 'exit 0\n' > "$d/fix/01-ok.sh"; : > "$d/file"; BLAST_OFF_TEST_ONLY=01-ok BLAST_OFF_TEST_KEEP="$d/file/kept" BLAST_OFF_NO_SHELLCHECK=1 tests/run "$d/fix"; echo rc=$?`. Expected: a `mkdir:` error line, `FAIL BLAST_OFF_TEST_KEEP=<d>/file/kept: cannot be made`, `GATE: FAIL passed=0 failed=1 shellcheck=skipped`, `rc=1`.

**4. The only combination CI uses for a filtered run, keep dir plus filter, has no test**

- **Item:** `ci.yml:48,51` set `BLAST_OFF_TEST_KEEP` and `BLAST_OFF_TEST_ONLY` together on every dispatch. `tests/00-harness.sh:28` (`only()`) sets no keep dir. `tests/40-receipt-required.sh:63` runs under an outer `tests/run` that already unset it (`tests/run:26`). The work baton's hand probe was `BLAST_OFF_TEST_ONLY=70-docs tests/run`, also without it.
- **Why it matters:** By reading, `tests/run:56-59` moves only the scenarios that ran, which is right. But item 3 lives in this gap, and so does item 5.
- **What to verify or decide:** What evidence is there, other than reading, that a filtered run with a keep dir keeps exactly the named scenarios?

**5. P1R2-1 gets an easy new route: a filtered run that matched nothing uploads an archive with nothing in it**

- **Item:** `tests/run:33` makes the keep dir before the loop. With only unknown names no scenario runs, nothing is moved in, and the run exits 1 (`:61-63`). `ci.yml:62-71` then run: the dir exists, so `tar` exits 0 (unlike P1R2-1's missing dir, where it exits 2) and the upload goes green with one empty directory.
- **Why it matters:** P1R2-1 needed a failed step before the gate. This needs one typo in the dispatch form. The `ci.yml` header (`:4-5`, "every scenario's work dir") and the step comment (`:47`) are also untrue for any filtered run: only the named scenarios are kept.
- **What to verify or decide:** Is an empty `blast-off-tests` artifact on a typo acceptable, given the run log already names the bad input? UNREPRODUCED (needs GitHub): `gh workflow run ci --ref <branch> -f only=nope`. Expected: red run; log `FAIL only nope: no such scenario in <workspace>/tests`, then `PASS shellcheck (33 files)`, then `GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=nope`; tar and upload steps green; the artifact's `.tgz` holds only `blast-off-tests/`.

**6. Mutants the new tests would not kill (by reading; none was run)**

- **Item:**
  - Deleting the `inputs:` block (`ci.yml:12-16`): `tests/00-harness.sh:109` pins only the env line, and no test mentions `workflow_dispatch` (grep of `tests/` finds `inputs` on lines 109-110 only). The suite stays green while the dispatch form loses its field.
  - Moving the env line to another step or to job level: the regex `^ +BLAST_OFF_TEST_ONLY: \$\{\{ inputs\.only \}\}$` matches anywhere in the file. This extends P1R2-2 (text, not steps) to the new line.
  - `${{ inputs['only'] }}`, `${{ github.event.inputs['only'] }}` or `${{ toJSON(inputs) }}` written into a `run:` script: none holds the substring `inputs.`, so the count at `:109` stays 1. The failure message's "and nowhere else" claims more than the count proves.
  - Skipping shellcheck on a filtered real-suite run: every filtered test uses a fixture dir with `BLAST_OFF_NO_SHELLCHECK=1` (`00-harness.sh:10,28`; `40-receipt-required.sh:63`). The task plan's decision "Shellcheck still runs on a filtered real-suite run" rests on one hand probe.
  - Dropping `-d ''` from `tests/run:39`: no test passes a newline or a tab. With that mutant `$'01-a\n09-x'` drops `09-x` silently and ends `GATE-ONLY: PASS`, the opposite of "fails loudly". The comment at `:39` claims the behaviour; nothing pins it.
  - `[[ $ran == *"$o"* ]]` at `tests/run:62` (delimiting spaces dropped): no test names a proper substring of a scenario that ran (for example `01-a 1-a`), so a wrong name would pass as matched.
  - Killed, by the same reading: dropping the `unset` at `tests/run:40` (fixture `01-a` exits 1, `00-harness.sh:26`); glob matching (the `*` case, `:42-45`); a `GATE:` prefix on a filtered FAIL (`:38`); `' , '` treated as a name (`:47-49`, and the work baton's RED 1b); ignoring the filter (test 40's block, the work baton's RED 1); weakening the match at `tests/run:46` to a substring (the `01-a.sh` case).
- **Why it matters:** Criterion 3 says the tests prove the filter. Criterion 1's first clause (the input exists) and "fails loudly" for a second-line name are held by no assertion.
- **What to verify or decide:** Which of these six is an accepted gap, and which was simply not tried?

**7. Odd characters: what my probes of the split expression showed**

- **Item:** Inline probe of `read -rd '' -a only <<< "${only//,/ }"` and of the tail `$(IFS=,; echo "${only[*]}")` on bash 5.2.21:
  - A lone `-n`, `-e` or `-ne` is eaten by `echo`: the tail is ` only=` with no name (probe output `in=-n n=1 [<-n>] tail=' only='`). The `FAIL only -n: ...` line still names it.
  - A carriage return is not a separator: `$'01-a\r'` stays one name `01-a\r`, matches nothing, and is printed raw into the `FAIL only` line and the verdict line. A terminal overprints the line start.
  - A no-break space is not a separator: `01-a<U+00A0>02-b` is one name.
  - Tabs and newlines do split. The header (`tests/run:11-12`), the spec row and the input description (`ci.yml:14`) all say "spaces or commas".
  - `*`, `a\x`, `01-a;02-b` stay literal single names (`0?-a` is covered by `00-harness.sh:42-45`, green in the gate log, not by my probe); the two `[[ ]]` matches quote the name, so nothing globs (probes: "no match star", "ran star nomatch").
  - A name given twice runs once and is printed twice in `only=`.
- **Why it matters:** Every case fails loudly or is harmless, and only someone with write access can dispatch, so I see no privilege gained. The cost is a verdict line that can show an empty `only=` on a filtered run, and a CRLF-pasted value that fails with a line that looks right on screen.
- **What to verify or decide:** Is the `only=` tail meant to be a faithful record of what was asked? If so, why is it printed with `echo`?

**8. `GATE-ONLY: PASS` still holds the words GATE and PASS**

- **Item:** The prefix was chosen so `lib/receipt.sh` refuses it without a code change (task plan, Decisions). In-repo readers are all anchored: `lib/receipt.sh:8,31,38,60`; `lib/ci.sh` reads no line; `tests/51-templates.sh:100` calls `receipt_verdict`.
- **Why it matters:** The other readers are not anchored parsers: LLM children told that the gate's last line is `GATE: PASS` or `GATE: FAIL` (`templates/brief.md:61`, `skills/blast-off/SKILL.md:33`), people skimming a log, and the baton-runner and big-next-job skills under `~/.claude`, which I was not allowed to read. A child that sees the refusal gets "the last line ... is not a GATE: verdict; run the gate again and save its whole output there" (`lib/receipt.sh:24`); with the variable still set, following that advice gives the same refusal again.
- **What to verify or decide:** Has anyone checked how the out-of-repo readers match the verdict (anchored `GATE: PASS`, or a loose `GATE.*PASS`)?

**9. Docs that still say every run ends `GATE: PASS` or `GATE: FAIL`**

- **Item:** Not updated: `README.md:107,148`; `.claude/big-next-job.md:5-6`; `scripts/gate.sh:3-4`; `docs/spec.md:24` (row K6); `skills/blast-off/SKILL.md:33,85`. `docs/spec.md:227` (the `40-receipt-required` row) still reads "done phase without a matching receipt; exit 9" though the scenario gained a behaviour; the work baton admits this. Stated nowhere a user reads: shellcheck still runs on a filtered real-suite run, so a filtered run can fail on lint alone; named scenarios run in suite order; matched scenarios still run when another name is unknown. The issue's second caution (a timing-dependent failure may not reproduce alone) is in neither the input description (`ci.yml:14`) nor the header.
- **Why it matters:** Criterion 4 names only `docs/spec.md` and the header, so this is inside the letter of the criteria. But `README.md:148` is the first place a reader learns what `tests/run` prints, and it is now incomplete.
- **What to verify or decide:** Is the criterion's file list the whole doc scope, or the minimum?

**10. Nothing in this diff has run on GitHub**

- **Item:** `git branch -r` shows only `origin/main` and `origin/feat/br-1115-issues/phase-1`; 5062c7d is not pushed, and `gh run list --workflow ci` shows no run of this `ci.yml`. The work baton says the same.
- **Why it matters:** This is P1R2-3's class, grown. Every pull request run now depends on `${{ inputs.only }}` evaluating to an empty string, not an error, when the event is `pull_request`. I believe it does (the pattern is common); nobody has observed it here. Also unobserved: whether the form or the API trims the value, and whether a dispatch from a non-default ref offers the input.
- **What to verify or decide:** What is the plan to see one `pull_request` run, one empty dispatch and one filtered dispatch before merge? UNREPRODUCED (needs GitHub). Expected last log lines: the PR run and `gh workflow run ci --ref <branch>` both end `GATE: PASS passed=18 failed=0 shellcheck=ok`; `gh workflow run ci --ref <branch> -f only=70-docs` ends `GATE-ONLY: PASS passed=1 failed=0 shellcheck=ok only=70-docs`.

**11. Decisions the task plan records without a reason that settles them**

- **Item:**
  - An unknown name fails at the end, after every matched scenario has run (`tests/run:61-63`), not before the first. The stated reason is "one code path".
  - A `.sh` suffix is rejected ("YAGNI"). The issue's own evidence names the file: `ln -sf .../tests/30-paused-limit.sh`.
  - A value of only separators (`,` or a space) is the whole gate with a real `GATE:` line (`00-harness.sh:46-50`).
- **Why it matters:** The first costs the full run time of the good names before the typo is reported. The second makes the most likely first mistake a red run. The third means a dispatcher who typed something into the field can still get a receipt-worthy gate line.
- **What to verify or decide:** For each, which mistake by the person dispatching was it designed around?

**12. Scenario 40 now runs `tests/run` itself**

- **Item:** `tests/40-receipt-required.sh:63` is the second scenario to call `tests/run`. The comments at `tests/run:25` and `:38` name only `00-harness` as the reason for the two `unset`s.
- **Why it matters:** `only=40-receipt-required` works only because of the `unset` at `tests/run:40`. The fixture `onlyfix/01-a.sh` (`00-harness.sh:26`) does pin that unset, so this is covered; the comments are just out of date.
- **What to verify or decide:** Nothing to decide beyond the comment.

### Confidence

Medium-high on the static claims: each cites a line I read or a probe I ran. Items 1, 3, 5 and 10 carry expected outputs I could not observe; running the commands given, on a quiet box or on GitHub, would settle them. Not examined: the skills under `~/.claude` that read the gate verdict; `bin/blast-off`, `tests/70-docs.sh` and `tests/51-templates.sh` beyond a grep; `lib/units.sh` and `lib/child.sh` beyond the excerpts cited; and anything about GitHub's handling of the `inputs` context beyond general knowledge.
