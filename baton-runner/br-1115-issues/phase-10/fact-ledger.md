# Phase 10 fact ledger (work unit B)

Every factual claim in the scope files, with the code or test that makes it true. Locations are at commit
0a5d3b1 (after this unit's fixes); "fixed" rows give the old text in work-B.md. Code paths are relative to
the repo root. `docs/2026-11-04-large-job-launcher-prompt.md` is a verbatim historical copy: not checked.

Counts: 240 claims; 200 ok (7 of them new text this unit added, each checked), 38 fixed, 2 deleted. Rows in the last section marked "counted above" repeat a row of an earlier section and are not counted again.

## README.md

| claim | location | evidence | result |
|---|---|---|---|
| runner checks liveness, soft cap, git tree, usage, receipts, CI before accepting a phase/job | README.md:6-8 | lib/child.sh:69-95, lib/chain.sh:104-120, :53-85, lib/usage.sh:17-50, lib/receipt.sh:45-71, lib/ci.sh:57-119 | ok |
| a child works one step and the runner relaunches until `done` or `blocked` | README.md:4-6 | lib/chain.sh:196-205 | ok |
| link docs/spec.md, docs/systemd-guide-deviations.md, bin/blast-off header, launcher prompt copy exist | README.md:10-13 | files present (`ls docs/`); test 70-docs.sh:70-72 pins the prompt link | ok (lines 9-13 not edited, per brief) |
| requirements: bash, tmux 3.2+, jq, python3, systemd, claude, gh; shellcheck for tests | README.md:17-18 | lib/chain.sh:88 (DEPS), lib/preflight.sh:17 (gh), tests/run:76-77 (shellcheck) | ok |
| optional jev with an `sk-or-` OpenRouter key | README.md:18 | lib/jev.sh:34-38 | ok |
| pick below `JOB_JEV_MIN_CONF` (default 0.7) keeps `CLAUDE_FLAGS` | README.md:19 | lib/jev.sh:31, :47-49; test 61-jev-pick.sh | ok |
| `install` writes blast-off@.service and blast-off.slice, daemon-reload | README.md:25, :30-31 | lib/units.sh:8-14; test 11-unit-smoke.sh:13-16 | ok |
| `install` never runs `enable` | README.md:31 | lib/units.sh:8-14 (no enable); systemd/blast-off@.service:9 (no [Install]) | ok |
| slice limits MemoryHigh=14G, MemoryMax=18G, CPUQuota=1600%, TasksMax=4096, oomd 65% | README.md:32-33 | systemd/blast-off.slice:10-15 | ok |
| sized for a 20-core, 23 GB box | README.md:33 | systemd/blast-off.slice:2 | ok |
| job dir `<worktree>/.big-next-job/` with brief.md and checkpoint.md; workdir its parent | README.md:37-38 | bin/blast-off:62 (`dirname "$JOB"`) | ok |
| exclude line via `git rev-parse --git-common-dir`/info/exclude | README.md:40 | git(1): info/exclude is per common dir; no code involved | ok |
| §4 Target set confirmed as its own question; §9 stays verbatim | README.md:42-44 | templates/brief.md:52-53, :112 | ok |
| checkpoint: one Phase plan row per phase from the left margin, key first, Status last; keep HTML comment | README.md:45-46 | lib/checkpoint.sh:10-27; templates/checkpoint.md:20-45; test 51-templates.sh | ok |
| workdir name letters, digits, `-`, `_` names unit `blast-off-<name>.service` and tmux server `blast-off-<name>` | README.md:47-48 | bin/blast-off:64-66; lib/child.sh:23 (`-L "$UNIT"`) | ok |
| start the skill session inside the target repo | README.md:51-53 | test 70-docs.sh:66-69 (text pinned); behaviour is a Claude Code fact the owner ruled on (#21) | ok |
| preflight prints flags, level, cap, child count, timeout, account, usage, estimate, PRs, behind | README.md:61 | lib/preflight.sh:19-49 | ok |
| `start` runs transient unit blast-off-<name>.service in blast-off.slice | README.md:62 | lib/units.sh:41-52 (`-p Slice=` from the template); test 11-unit-smoke.sh:33-35 | ok |
| preflight exits 1 when CLAUDE_FLAGS empty, a dependency missing, brief.md missing, child-count garbled, a bad JOB_* number, estimate over the 7-day window | README.md:65-67 | lib/preflight.sh:13-17, :15, :39, :98, :51 | fixed (list was incomplete) |
| `start` passes PATH, GH_TOKEN, CLAUDE_FLAGS and every set JOB_*/BLAST_OFF_* name the runner reads (not JOB_BASE, BLAST_OFF_ESTIMATE_FROM) by name | README.md:67-69 | lib/units.sh:21-29; test 11-unit-smoke.sh:21-24 | fixed (said "every set `JOB_*` name": JOB_BASE is not passed, BLAST_OFF_* were not named) |
| `start` refuses GH_TOKEN/CLAUDE_FLAGS unset or empty, or a bad JOB_* number | README.md:70 | lib/units.sh:32-38; test 12-start-env.sh | ok |
| with an `sk-or-` key and JOB_JEV not 0, start passes OPENROUTER_API_KEY | README.md:70-71 | lib/units.sh:23; test 12-start-env.sh | ok |
| otherwise children get CLAUDE_FLAGS as given | README.md:72-73 | lib/jev.sh:31-38 | ok |
| run.log pick line `model level for phase 2: light (jev, confidence 0.87, threshold 0.7): ...` | README.md:73-74 | lib/jev.sh:73 | ok |
| the key never in run.log | README.md:74 | lib/jev.sh:28, :41 (masks `sk-or-`); test 61-jev-pick.sh, 11-unit-smoke.sh:97 | ok |
| resume timer passes the same names with values from when it was armed | README.md:74-75 | lib/usage.sh:69-71 (`unit_env`, `--setenv=NAME` at arm time) | ok |
| systemd keeps resolved values in the transient unit file under $XDG_RUNTIME_DIR until collected | README.md:76-77 | systemd-run(1) `--setenv` semantics; docs/spec.md:72-75 records the check | ok |
| children never get OPENROUTER_API_KEY | README.md:77-78 | lib/child.sh:22 (`-u OPENROUTER_API_KEY`) | ok |
| hand-started template instance has no CLAUDE_FLAGS and exits 1 | README.md:80-82 | lib/chain.sh:147; systemd/blast-off@.service:4-6 | ok |
| allow rule `Bash(blast-off start:*)`; does not match past an assignment prefix; classifier denial is final | README.md:84-95 | Claude Code permission behaviour recorded in docs/spec.md F2 row (owner-verified, phase 7); no blast-off code | ok |
| blast-off never writes settings | README.md:94 | no code writes `.claude/settings*` (grep lib/ bin/) | ok |
| `wait` blocks until status, phase, child or unit changes; prints one line | README.md:98 | lib/units.sh:110-161 | ok |
| `status`: checkpoint header, unit state, child count, resume timer | README.md:99 | lib/units.sh:76-86 | ok |
| `logs`: run.log tail and the unit's journal | README.md:100 | lib/units.sh:97-100 | ok |
| run.log holds children, picks, pauses, refusals | README.md:101 | lib/chain.sh:233, lib/jev.sh:69-73, lib/usage.sh:49, lib/receipt.sh:12 | ok |
| `tmux -L blast-off-<name> attach -t job-<name>` | README.md:102 | bin/blast-off:66-68; lib/child.sh:23 | ok |
| `stop` stops the runner, its children and any resume timer | README.md:103 | lib/units.sh:89-95 | ok |
| `resume`: paused-cap, or paused-limit after its reset | README.md:104 | lib/units.sh:60-74 | ok |
| `run` is the same chain in the foreground (what the unit runs) | README.md:105 | bin/blast-off:73; systemd/blast-off@.service:15 | ok |
| re-running resumes from `Next action`; nothing redone | README.md:108 | lib/chain.sh:160 (constant prompt); templates/brief.md:115 | ok |
| wait reads status, phase, last child number, unit and timer state every 5 s (`BLAST_OFF_WAIT_POLL`) | README.md:110-113 | lib/units.sh:111, :146-161 | ok |
| at done/blocked, reads `runner-end`, written only when the runner accepts | README.md:113-114 | lib/units.sh:117-119; lib/chain.sh:10, :202-203 | ok |
| never reads run.log | README.md:114 | lib/units.sh:146-161 (reads checkpoint.md, child-count, systemctl only) | ok |
| a change is state, never the clock | README.md:114-115 | lib/units.sh:134; test 13-wait.sh:242-259 | ok |
| line shape `wait: <final|changed|stuck> · status: ... · phase: ... · child <n> · unit <state> · timer <state>` | README.md:115 | lib/units.sh:118, :127-128, :134, :160 | ok |
| status word at most 80 characters | README.md:116 | lib/units.sh:160 (`${WAIT_STATUS:0:80}`) | ok |
| `until <time>`: the time at most 40 characters | README.md:116 | lib/units.sh:157 (`{1,40}`) | fixed (P6R3-12: said "at most 40 more"; the part is up to 47 with " until ") |
| phase line: no control characters, each `·` turned into `-`, at most 80 | README.md:116-117 | lib/units.sh:159-160; test 13-wait.sh:91-95 | fixed (P6R3-12: said `·` is dropped) |
| final: exit 0, status done/blocked and runner-end holds the same word | README.md:121 | lib/units.sh:117-119; test 13-wait.sh:104-111 | ok |
| changed: exit 11 | README.md:122 | lib/units.sh:134 | ok |
| stuck at paused-cap: exit 12, line says `paused-cap: run blast-off resume <job-dir>` | README.md:123 | lib/units.sh:126-129 | ok |
| stuck: 10 s (at least two polls) with unit and timer down, no matching runner-end | README.md:124 | lib/units.sh:121-130 | ok |
| stuck `no read for 60 s`: 60 s or more, at least one retry, a long poll stretches it | README.md:125 | lib/units.sh:135-140 | fixed (P6R3-14) |
| exit 1 at start: no argument, no job dir, bad workdir name, missing/empty checkpoint.md, bad poll value, systemctl failing | README.md:126 | bin/blast-off:60-64; lib/units.sh:113-115, :148-152 | fixed (P6R1-18: no argument and workdir name were missing) |
| wait watches the unit; foreground `run` reads as stuck | README.md:128 | lib/units.sh:150-151 (unit state only) | ok |
| usage record `~/.claude/state/usage-limits-<session>.json`, written by `usage-limit-tee.sh` | README.md:130-132 | lib/usage.sh:3-6, :19 | ok |
| window at or above 95% (`JOB_USAGE_PAUSE`), StopFailure rate_limit or child exit 75 -> `paused-limit until <time>`, exit 8 | README.md:132-134 | lib/chain.sh:225-246; lib/usage.sh:9, :41-50; test 30-paused-limit.sh | ok |
| timer `blast-off-<name>.resume.timer` runs `blast-off resume` 60 s after the reset | README.md:134-135 | lib/usage.sh:45, :56-77 | ok |
| timer on tmpfs; after a reboot `status` prints the resume line | README.md:135 | lib/units.sh:81-85 | ok |
| close order: commit, gate log `gate-logs/phase-<n>.log` ending `GATE: PASS/FAIL`, receipt, ci-wait, Status cell | README.md:139-147 | lib/receipt.sh:4-39; templates/brief.md:131-151 | ok |
| receipt writes `gate-logs/phase-<n>.json`: verdict, tally, HEAD sha, UTC time | README.md:143 | lib/receipt.sh:30-36 | ok |
| ci-wait: one blocking `gh run watch` per CI run of the PR head | README.md:144 | lib/ci.sh:24-33 | ok |
| done row without a PASS receipt for its sha: exit 9 | README.md:148 | lib/receipt.sh:45-65 | ok |
| done refused (exit 10) on a row with neither `PR #` nor `no PR`, no readable row, a malformed Phase plan, a second heading, red/unread/absent CI | README.md:149-153 | lib/ci.sh:60-119; lib/checkpoint.sh:27-99; test 41-ci-wait.sh | ok |
| PRs read only from those cells; run.log says which | README.md:153-154 | lib/ci.sh:101-103 | ok |
| done gate threat model (owner ruling 3) | README.md:156-160 | owner ruling; test 70-docs.sh:54-60 pins the text | ok |
| exit 0..10 table rows | README.md:166-175 | lib/chain.sh:6, :84, :190, :202-203, :209-210, :250; lib/receipt.sh; lib/ci.sh; lib/usage.sh:49 | ok |
| exit 4: hard cap counts every run in `child-count`; resume after a fresh start may pause at paused-cap; deleting child-count resets | README.md:169 | lib/chain.sh:122-144, :185, :208-210 | ok |
| exit 6: resume gives a fresh allotment, numbering goes on | README.md:171 | lib/chain.sh:185 | ok |
| exit 8: nothing while the timer is active, else resume after `<time>` | README.md:173 | lib/units.sh:60-74 | ok |
| non-zero codes except 1 are states; no `Restart=` | README.md:177-178 | systemd/blast-off@.service:8 | ok |
| big-next-job launches `run-job` with `nohup` | README.md:182 | ~/.agents/skills/big-next-job/SKILL.md:119 | ok |
| a big-next-job checkpoint ends in exit 9 at its first done row | README.md:184-185 | its template row `done · commit <sha>` (big-next-job templates/checkpoint.md:16) is read as done with no receipt: lib/receipt.sh:56 | ok |
| `tests/run`: every NN-*.sh with fakes, shellcheck, GATE: PASS/FAIL | README.md:193 | tests/run:2-16, :43-92 | ok |
| scenarios start real `blast-off-test-<pid>-*` units | README.md:196 | tests/lib.sh:7; test 11-unit-smoke.sh | ok |
| `BLAST_OFF_TEST_ONLY`: named scenarios, spaces or commas, `GATE-ONLY:` line refused by receipt, unknown name fails | README.md:198-200 | tests/run:11-15, :39, :61-62, :86-87; test 00-harness.sh:22-44, 40-receipt-required.sh:60-67 | ok (added by this unit) |
| `BLAST_OFF_TEST_KEEP=<dir>` keeps `<dir>/<name>`, not under bin/lib/tests | README.md:200-201 | tests/run:7-10, :27-35, :54-59 | ok (added by this unit) |
| `scripts/gate.sh <log-dir>` tees `<log-dir>/tests-run.log`, exits with tests/run's status | README.md:201-202 | scripts/gate.sh:6-10 (pipefail) | ok (added by this unit) |
| CI runs tests/run on every PR; job 30 min, gate step 25 min | README.md:203-204 | .github/workflows/ci.yml:10, :22, :45, :56 | ok (added by this unit) |
| a red run uploads artifact `blast-off-tests` (`blast-off-tests.tgz`) | README.md:204-205 | .github/workflows/ci.yml:62-71 | ok (added by this unit) |
| a dispatch takes `only`, passed to BLAST_OFF_TEST_ONLY | README.md:205 | .github/workflows/ci.yml:11-16, :51 | ok (added by this unit) |

## docs/spec.md

| claim | location | evidence | result |
|---|---|---|---|
| source commits afc647e0, db41485ce in VistaMarkets/vbe | docs/spec.md:9-10 | `git -C ~/vista-root/vbe cat-file -t` both commit | ok |
| directive table source `~/.claude/docs/guides/system-d-guide.md` §5 at ad995d4 | docs/spec.md:10-11 | file exists, §5 at line 117; `git -C ~/.claude cat-file -t ad995d4` = commit | ok |
| blast-off never reads or writes the installed big-next-job skill | docs/spec.md:11 | no reference to `big-next-job` paths in lib/ or bin/ (grep) | ok |
| K1-K3, K5, F1, F4, F6, F11 template rows (decision table, §3.0-3.4, PR per phase, doubt pass and probes, target set, review shape, reviewer dispatch text, lanes off) | docs/spec.md:20-24, :30, :33, :35, :40 | templates/brief.md:14-21, :27-40, :46-56, :73-110; skills/blast-off/SKILL.md:32-36; test 51-templates.sh | ok |
| K4 chain mechanics files; ported from run-job | docs/spec.md:23 | lib/chain.sh, lib/child.sh, templates/settings.child.json; ~/.agents/skills/big-next-job/scripts/run-job (94 lines) | ok |
| K6 tests/run verdict with passed=, failed=, shellcheck=; receipt reads it | docs/spec.md:25 | tests/run:88-92; lib/receipt.sh:33 | ok |
| K7 finding IDs, phases/, decisions.tsv | docs/spec.md:26 | templates/brief.md:91, :127-128; lib/jev.sh:77-79 | ok |
| K8 Jev: question per first open row on stdin, OpenRouter only, levels light/standard/deep and flags, fallbacks, logging, start/timer pass key, preflight forecast | docs/spec.md:27 | lib/jev.sh:8-80; lib/units.sh:23; lib/preflight.sh:20-29; test 61-jev-pick.sh, 60-preflight.sh, 12-start-env.sh | ok |
| K9 runner exits 3 only on `status: blocked` | docs/spec.md:28 | lib/chain.sh:203 | ok |
| K10 children obey usage-checkpoint.py; runner reads usage-limits-<session>.json | docs/spec.md:29 | templates/brief.md:156; ~/.claude/hooks/usage-checkpoint.py exists; lib/usage.sh:19 | ok |
| F2 child pane polled every second, remain-on-exit, last screen logged | docs/spec.md:31 | lib/child.sh:26, :69-95, :98-102 | ok |
| F3 run.log warning past 150 lines | docs/spec.md:32 | lib/checkpoint.sh:112-115; test 50-checkpoint-size.sh | ok |
| F5 dirty-tree check before child 1 and at each child end, exit 7 | docs/spec.md:34 | lib/chain.sh:61-85, :194, :242 | ok |
| F5 "the child env also sets CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 (brief §3.3)" | docs/spec.md:34 | nothing in lib/, templates/ or bin/ sets it (grep: only the launcher prompt names it); templates/brief.md §3.3 is a placeholder | fixed (now: blast-off does not set it) |
| F7 ci-wait and ci_check exit 10 | docs/spec.md:36 | lib/ci.sh:13-47, :78-119 | ok |
| F8 receipt from templates/receipt.json; exit 9 on sha mismatch | docs/spec.md:37 | lib/receipt.sh:30-35, :59 | ok |
| F9 preflight PRs on Target set and behind count after fetch | docs/spec.md:38 | lib/preflight.sh:112-148 | ok |
| F10 paused-limit, exit 8, rate_limit, exit 75, resume timer, usage on rows, preflight estimate refuses seven_day only | docs/spec.md:39 | lib/usage.sh; lib/chain.sh:225-246; lib/checkpoint.sh:135-142; lib/preflight.sh:89-100 | ok |
| job dir: brief.md, checkpoint.md; runner adds run.log, child-count, runner-end | docs/spec.md:45-47 | bin/blast-off:69; lib/chain.sh:10, :144 | ok |
| runner-end `done <utc>`/`blocked <utc>`, by rename, before the end line | docs/spec.md:47-48 | lib/chain.sh:10, :202-203 | ok |
| a signal between runner-end and the end line leaves the file and `runner exit <n> without a state` | docs/spec.md:48-49 | lib/chain.sh:166, :18-27 | fixed (P6R3-9: added) |
| runner-end deleted by every run once it holds the lock; earlier exits leave it; refused = any exit but 0 and 3 | docs/spec.md:49-51 | lib/chain.sh:154-155 (exits before lock), :164-169 | fixed (P6R3-11: said "at the start of every run", "exit 7, 9 or 10") |
| dirty-tree check skips the job dir's own files | docs/spec.md:51 | lib/chain.sh:70 | ok |
| `run`: exits 1 without CLAUDE_FLAGS; takes the lock ($XDG_RUNTIME_DIR/<unit>.lock); logs cap; paused-cap -> running; dirty check | docs/spec.md:55 | lib/chain.sh:147, :36, :41, :172-173, :185-186, :194 | ok |
| `start`: systemd-run --user --collect --unit --working-directory, setenv list, OPENROUTER when Jev can use it, template [Service] directives but ExecStart as -p (Slice among them) | docs/spec.md:56 | lib/units.sh:21-29, :41-52; test 11-unit-smoke.sh:21-24 | fixed (said `--slice=blast-off.slice`, which start does not pass, and named only JOB_* and BLAST_OFF_TRUST_SECONDS) |
| `start` refuses unset GH_TOKEN/CLAUDE_FLAGS or a bad JOB_* number, prints the resolved launch first | docs/spec.md:56 | lib/units.sh:32-38, :49 | ok |
| `status` output lines and the `no resume timer` line | docs/spec.md:57 | lib/units.sh:76-86 | ok |
| `stop`: stops the service, child scopes and resume timer; exit 1 if still active | docs/spec.md:58 | lib/units.sh:89-95 | fixed (named the service only) |
| `logs`: run.log tail and journalctl | docs/spec.md:59 | lib/units.sh:97-100 | ok |
| `resume`: start for paused-cap/paused-limit after until; exit 8 before; exit 1 on missing names or bad numbers; never writes status; waits up to 90 s; stops pending timer; no timer for a foreign workdir | docs/spec.md:60 | lib/units.sh:60-74; lib/usage.sh:60-63 | ok |
| `wait`: snapshot fields, poll, child `?` when garbled | docs/spec.md:61 | lib/units.sh:146-161 | ok |
| wait: accepted end via runner-end; never reads run.log | docs/spec.md:61 | lib/units.sh:117-119 | ok |
| wait: an unaccepted done/blocked is no change; runner may refuse with 7, 9 or 10 (done), 7 or 9 (blocked), 1 on an error, 128+n on a signal | docs/spec.md:61 | lib/units.sh:134; lib/chain.sh:194-203, :25-26 | fixed (P6R3-11: exit 1 and signals missing) |
| wait: 10 s down spell, states inactive/failed/deactivating, timer not active | docs/spec.md:61 | lib/units.sh:121-130 | ok |
| wait line: status word cut to 80, the until time up to 40, phase `·` -> `-`, cut to 80 | docs/spec.md:61 | lib/units.sh:157-160 | fixed (P6R3-12) |
| wait exit 1 causes: no argument, no job dir, bad workdir name, missing/empty checkpoint, bad poll, systemctl failing | docs/spec.md:61 | bin/blast-off:60-64; lib/units.sh:113-115, :148-152 | fixed (P6R1-18: no argument and workdir name added) |
| wait: failed reads retried; 60 s in a row (at least one retry) -> 12 `no read for 60 s` | docs/spec.md:61 | lib/units.sh:135-140; test 13-wait.sh:235-239 | fixed (P6R3-14) |
| wait: "No timeout of its own: the caller's background command has one" | docs/spec.md:61 | no timeout in lib/units.sh:110-142; the second half has no evidence (P6R1-19: a background command has none) | deleted (second half) |
| `install` writes blast-off@.service and blast-off.slice only; the resume timer is transient | docs/spec.md:62 | lib/units.sh:8-14; lib/usage.sh:70 | fixed (said "and the resume timer if used") |
| `preflight` lines: flags, model, effort, level, cap, child-count + left, timeout, account, GH_TOKEN, usage, estimate, slice, scope stop timeout, PRs, behind | docs/spec.md:63 | lib/preflight.sh:19-49 | ok |
| preflight refusals: missing brief.md, CLAUDE_FLAGS, deps or gh, garbled child-count, estimate | docs/spec.md:63 | lib/preflight.sh:13, :16-17, :39, :98 | fixed (missing brief.md added) |
| bad JOB_* count refused before any line; "(exit 1 above)" | docs/spec.md:63 | lib/preflight.sh:15; exit table is §3, below | fixed (P5R2-6: now "exit 1, §3") |
| `receipt`: fields, refusals, exit 0 PASS / 1, refusal logged | docs/spec.md:64 | lib/receipt.sh:6-39; templates/receipt.json | ok |
| `ci-wait`: dispatch runs left out, verdicts, 5 s re-read up to BLAST_OFF_CI_APPEAR, 3 rounds, BLAST_OFF_CI_WATCH, exit 0 / 10 | docs/spec.md:65 | lib/ci.sh:13-55 | ok |
| env defaults: JOB_CAP_FACTOR 3, JOB_CHILD_TIMEOUT 7200, JOB_MAX_CHILDREN hard default 12, TRUST 60, USAGE_PAUSE 95, RESUME_MARGIN 60, API_BACKOFF 600, STATE_DIR, CI_APPEAR 60, CI_WATCH 3600, CI_HEAD 60, JOB_JEV 1, MIN_CONF 0.7, JOB_BASE main | docs/spec.md:67-69 | lib/chain.sh:116-118, :151, :229; lib/child.sh:89; lib/usage.sh:19-21, :45; lib/ci.sh:21, :26, :132; lib/jev.sh:31, :33; lib/preflight.sh:140 | ok |
| child-count: `<launched> <base>`, by rename before each launch, hard/soft cap rules, fresh job, run.log start line | docs/spec.md:68 | lib/chain.sh:122-144, :174, :185, :208-218 | ok |
| garbled child-count: name and, when readable, size and wanted shape, never content | docs/spec.md:68 | lib/chain.sh:134-139 | fixed (P5R2-6: the unreadable branch gives no size) |
| JOB_KEEP_WINDOWS leaves children, server, scopes and dirs | docs/spec.md:69 | lib/chain.sh:21; lib/child.sh:137, :144 | ok |
| OPENROUTER_API_KEY passed when sk-or- and JOB_JEV not 0; children never get it | docs/spec.md:69 | lib/units.sh:23; lib/child.sh:22 | ok |
| secrets stored in the transient unit file under $XDG_RUNTIME_DIR/systemd/transient/ (0644 in a 0700 dir) and Environment property | docs/spec.md:72-76 | systemd-run(1); owner-verified on the build box (D21); no blast-off code writes it | ok |
| user manager PATH finds neither claude nor jev; PassEnvironment= has no effect in user scope | docs/spec.md:82-85 | systemd/blast-off@.service:4-5; docs/systemd-guide-deviations.md (verified rows) | ok |
| install writes ExecStart with this checkout's bin/blast-off; nothing outside ~/.config/systemd/user | docs/spec.md:88-89 | lib/units.sh:5, :10-11; test 11-unit-smoke.sh:14 | ok |
| exit 1 causes list | docs/spec.md:96 | lib/chain.sh:96-101, :147-155, :41, :178, :65, :25-26; lib/units.sh:32-38; lib/preflight.sh:51 | ok |
| exit 4 rules and paused-cap -> running | docs/spec.md:98 | lib/chain.sh:118, :185-186, :208-209 | ok |
| exit 5, 6, 7, 8 rows | docs/spec.md:99-102 | lib/chain.sh:248-250, :210, :61-85, :187-190; lib/usage.sh:41-50 | ok |
| exit 9: done row = Status cell `done` alone or followed by a blank or `(`, any case | docs/spec.md:103 | lib/checkpoint.sh:16-18, :50 | fixed (said "Status starts `done`") |
| exit 9 sha, receipt, gate log, code-after rules; at done any open row | docs/spec.md:103 | lib/receipt.sh:45-71 | ok |
| exit 10 rules (PR tokens, whitelist, unread lines, no done row, CI unread/red/absent, head read, workflow file, BLAST_OFF_CI_HEAD) | docs/spec.md:104 | lib/ci.sh:57-135; lib/checkpoint.sh:27-99; test 41-ci-wait.sh | ok |
| mid-run, a line done would refuse is logged each pass | docs/spec.md:111-112 | lib/chain.sh:200 | ok |
| wait codes 0/11/12/1 summary, 60 s at least one retry | docs/spec.md:114-117 | lib/units.sh:102-142 | fixed (P6R3-14) |
| "They are outside this table's range" | docs/spec.md:118-119 | 11 and 12 are; 0 and 1 are not (§3 table rows 0, 1) | fixed (P6R1-18) |
| code 2 unused; non-zero but 1 is a state | docs/spec.md:121-122 | no `exit 2`/`chain_end 2` in lib/ or bin/ (grep) | ok |
| private tmux server `-L <unit>` from inside the runner, CLAUDE* and OPENROUTER_API_KEY scrubbed | docs/spec.md:128-133 | lib/child.sh:12-27 | ok |
| socket under /tmp/tmux-1000/; watch line prints the attach command | docs/spec.md:137-139 | tmux(1) default socket dir; lib/child.sh:51; lib/units.sh:51 | ok |
| runner stops an earlier run's scopes and server at start; EXIT trap does the same unless JOB_KEEP_WINDOWS | docs/spec.md:139 | lib/child.sh:15, :30-34; lib/chain.sh:21 | ok |
| test cleanup never kill-server on others' servers; only its own | docs/spec.md:139 | tests/lib.sh:2-4 (`$TEST_ID` prefix) | ok |
| child command `systemd-run --user --scope --quiet --collect --slice=blast-off.slice --unit=<unit>-child-<n>.scope claude ...; rc=$?; echo $rc > <child dir>/exit; exit $rc` | docs/spec.md:148 | lib/child.sh:48-50 | fixed (missing `--quiet --collect`, `.scope`, and the exit-file commands) |
| exit file gives the status when tmux does not reap; CHILD_NOSTATUS run.log text | docs/spec.md:149-152 | lib/child.sh:61-62, :81-85; lib/chain.sh:233; test 20-dead-child.sh:79 | ok (added by this unit, PR 32 coverage) |
| commands after claude make the shell fork systemd-run | docs/spec.md:153-155 | lib/child.sh:39-41 | fixed (said "the trailing `; exit`") |
| slice directives | docs/spec.md:160-161 | systemd/blast-off.slice:8-15 | ok |
| template: Type=exec, ExecStart run %f, Slice, KillMode=control-group, ManagedOOMPreference=avoid, TimeoutStopSec, no Restart, no [Install] | docs/spec.md:163-169 | systemd/blast-off@.service:13-19, :8-9 | ok |
| usage record shape; `child <n> usage: ...` line; unknown/unreadable | docs/spec.md:174-181 | lib/usage.sh:3-36; lib/chain.sh:238 | ok |
| pause rules, until = latest reset over threshold / five_hour / now+5 h, plus margin, at least 5 s ahead | docs/spec.md:181-188 | lib/usage.sh:41-46; lib/chain.sh:244-246 | ok |
| exit 75 read from the exit file, else pane_dead_status | docs/spec.md:183 | lib/child.sh:81; lib/chain.sh:235 | ok |
| StopFailure hook writes failed.json; overloaded/server_error/unknown wait JOB_API_BACKOFF; others logged, next child at once | docs/spec.md:190-199 | templates/settings.child.json; lib/chain.sh:225-232, :213 | ok |
| resume timer `systemd-run --user --collect --unit=<unit>.resume --on-calendar=... --timer-property=AccuracySec=1s` plus start's setenv names | docs/spec.md:201-203 | lib/usage.sh:68-71 (also `--quiet`) | ok |
| `.resume` naming never collides; OnCalendar fires after sleep | docs/spec.md:203-208 | lib/usage.sh:52-55, :67 | ok |
| no timer with GH_TOKEN unset; `(the timer does it)` only when armed; foreign workdir names `blast-off run` | docs/spec.md:213-215 | lib/usage.sh:58-76 | ok |
| `stop` stops the timer; status prints `no resume timer` line | docs/spec.md:215-219 | lib/units.sh:85, :91 | ok |
| runner appends ` · usage <figure>` to a newly done row; stall fingerprint taken before | docs/spec.md:221-223 | lib/checkpoint.sh:135-142; lib/chain.sh:240-241 | ok |
| deviations doc lists every §5 directive; test 70 pins one filled row each | docs/spec.md:227-230 | test 70-docs.sh:73-89 | ok |
| tests/run is the gate; zero scenarios fails; shellcheck; ONLY run is not the gate | docs/spec.md:234-235 | tests/run:64, :66-92 | ok |
| fakes first on PATH; names prefixed blast-off-test-<pid>; marker file | docs/spec.md:236-240 | tests/lib.sh:7; test 10-chain-done.sh:4 (GH_TOKEN marker) | ok |
| row 00-harness (ONLY, KEEP, tar line, spec tables) | docs/spec.md:244 | test 00-harness.sh:22-44, :52-101, :136-144; 40-receipt-required.sh:60-67 | ok |
| row 10-chain-done (timeout 2, two stalls, cap 1, counts, SIGHUP/SIGKILL, garbled counts, forged line, trust window, exit 129, abort exit 4, child dirs, runner-end) | docs/spec.md:245 | test 10-chain-done.sh:60, :68, :84, :90, :99, :115, :134, :141, :155, :170, :196, :218, :22 | ok |
| row 11-unit-smoke (unit name, slice, template instance, cgroup, pane pid, status count, stop) | docs/spec.md:246 | test 11-unit-smoke.sh:13-75 | ok |
| row 11-unit-smoke: real unit gets an sk-or- key, run.log line `jev failed`, no key value | docs/spec.md:246 | test 11-unit-smoke.sh:90-99 | fixed (P7R2-16: row 12 pointed at this claim, row 11 lacked it; claim added) |
| row 12-start-env | docs/spec.md:247 | test 12-start-env.sh:2-5, :46-63, :89 | ok |
| row 13-wait (each listed case) | docs/spec.md:248 | test 13-wait.sh:75-259 | ok |
| row 13-wait: phase text `·` turned into `-` | docs/spec.md:248 | test 13-wait.sh:91-95 | fixed (P6R3-12: said "without ` · `") |
| row 13-wait: already stuck job "(after 10 s on wait's clock, not at once)" | docs/spec.md:248 | test 13-wait.sh:132 checks the exit code only (P6R3-12) | deleted |
| row 20-dead-child incl. CHILD_NOSTATUS | docs/spec.md:249 | test 20-dead-child.sh:79 | ok |
| row 21-soft-cap cases | docs/spec.md:250 | test 21-soft-cap.sh:19-86 | ok |
| row 21-soft-cap: "a `JOB_CAP_FACTOR` of 10" | docs/spec.md:250 | test 21-soft-cap.sh:85 (`JOB_CAP_FACTOR=1000000000`, 10 digits) | fixed ("of 10 digits") |
| row 22-dirty-tree | docs/spec.md:251 | test 22-dirty-tree.sh:3-4, :98, :136 | ok |
| row 23-runner-lock | docs/spec.md:252 | test 23-runner-lock.sh:2-4 | ok |
| row 30-paused-limit | docs/spec.md:253 | test 30-paused-limit.sh:23, :40, :66-70, :85-87, :125-137, :174 | ok |
| row 31-resume-after-reset: resume starts the unit, whose runner sets running | docs/spec.md:254 | lib/units.sh:54-59 (resume never writes status); lib/chain.sh:185-191; test 31-resume-after-reset.sh | fixed (said resume "sets running") |
| row 32, 40, 41, 50 | docs/spec.md:255-258 | tests 32, 40 (exit 9), 41 (header :2-9), 50:18, :37 | ok |
| row 51-templates incl. step 9 text (#16) | docs/spec.md:259 | test 51-templates.sh:52-98 | ok |
| row 60-preflight cases | docs/spec.md:260 | test 60-preflight.sh:59-162 | ok |
| row 61-jev-pick cases | docs/spec.md:261 | test 61-jev-pick.sh:4-105 | ok |
| row 70-docs | docs/spec.md:262 | test 70-docs.sh:6, :20-89 | ok |

## bin/blast-off (usage/help header)

| claim | location | evidence | result |
|---|---|---|---|
| run/start/status/stop/logs/install/preflight/receipt/ci-wait usage and arguments | bin/blast-off:7-20 | bin/blast-off:72-81 | ok |
| resume: paused-cap, or paused-limit after its reset: start (the runner sets running) | bin/blast-off:10 | lib/units.sh:54-74 | fixed (said "running, then start": resume never writes the status) |
| wait: exit 0 / 11 / 12 (stuck causes incl. a reboot and paused-limit with no timer) / no read for 60 s (at least one retry) / 1 | bin/blast-off:11-16 | lib/units.sh:102-142 | fixed (P6R1-20 list, P6R3-14, exit 1 added) |
| env defaults and meanings (CLAUDE_FLAGS ... BLAST_OFF_ESTIMATE_FROM) | bin/blast-off:21-41 | see docs/spec.md env row evidence; lib/units.sh:23 (OPENROUTER) | ok |
| exit codes 0, 1, 3-10 | bin/blast-off:42-47 | as README exit table | ok |

## skills/blast-off/SKILL.md

| claim | location | evidence | result |
|---|---|---|---|
| `bin/blast-off` two directories above the skill file | SKILL.md:12-13 | repo layout skills/blast-off/SKILL.md -> bin/blast-off | ok |
| unit `blast-off-<name>`, tmux session `job-<name>` | SKILL.md:51 | bin/blast-off:66-68 | ok |
| job dir directly inside the worktree; exclude line | SKILL.md:52-53 | bin/blast-off:62 | ok |
| preflight line; `preflight: refused` line | SKILL.md:57-59 | lib/preflight.sh:51 | ok |
| `start` passes OPENROUTER_API_KEY by name when an sk-or- key and JOB_JEV is not 0 | SKILL.md:68-69 | lib/units.sh:23 | fixed (P7R2-4: JOB_JEV condition missing) |
| a pick below JOB_JEV_MIN_CONF (0.7) keeps them; JOB_JEV=0 keeps CLAUDE_FLAGS | SKILL.md:70-71 | lib/jev.sh:31-33, :47-49 | ok |
| step 6 level line is a forecast | SKILL.md:72-73 | lib/preflight.sh:20-29 | ok |
| `tmux -L blast-off-<name> attach -t job-<name>` | SKILL.md:78 | lib/child.sh:23 | ok |
| wait exits 11/0/12/1 and their causes | SKILL.md:82-90 | lib/units.sh:102-142; bin/blast-off:60-64 | ok |
| a template instance gets no CLAUDE_FLAGS and exits 1 | SKILL.md:100-101 | lib/chain.sh:147 | ok |
| `start` takes no workdir | SKILL.md:110 | bin/blast-off:74 | ok |
| a gate whose last line is not `GATE:` is refused by receipt; done rows exit 9 | SKILL.md:111 | lib/receipt.sh:24, :56-61 | ok |
| the unit runs bin/blast-off from the checkout path | SKILL.md:112 | lib/units.sh:48 | ok |
| `ci-wait` records absent and exits 10; runner lets done through only with no workflow file at the PR head | SKILL.md:40-42 | lib/ci.sh:40, :46, :108-114 | ok |

## templates/brief.md

| claim | location | evidence | result |
|---|---|---|---|
| `"$BLAST_OFF"` is set in every child's environment | brief.md:6-7 | lib/child.sh:22 | ok |
| phases/, gate-logs/, decisions.tsv are in the job dir | brief.md:4-5 | lib/receipt.sh:22; lib/jev.sh:77 | ok |
| D1: Jev may pick --model/--effort when the runner holds the key; JOB_JEV=0 keeps them | brief.md:18 | lib/jev.sh:29-58 | ok (wording ambiguity P7R2-5 is not a factual error; see work-B.md) |
| gate's last non-empty line is `GATE: PASS`/`GATE: FAIL` | brief.md:61 | lib/receipt.sh:6-9 | ok |
| step 4: receipt, ci-wait, `done (<sha>) · PR #<n>`, exit 10 for neither, first 7-40 hex word, exit 9 after a code commit | brief.md:131-151 (§9, not edited) | lib/receipt.sh:45-65; lib/ci.sh:78-119; lib/checkpoint.sh:55 | ok |
| step 4: absent with a workflow file is refused; with none the runner logs absent, not a pass | brief.md:135-139 (§9) | lib/ci.sh:108-114 | ok |
| step 6: pause percent `${JOB_USAGE_PAUSE:-95}`; exit 75 reserved | brief.md:156-162 (§9) | lib/usage.sh:9, :21 | ok |
| step 7: a child writing paused-cap/paused-limit gets another child launched | brief.md:163-164 (§9) | lib/chain.sh:198-205 (only done/blocked end the loop) | ok |
| step 8: an unnamed path stops the chain (exit 7) | brief.md:168-170 (§9) | lib/chain.sh:84 | ok |
| step 9: refused tool calls come from the harness | brief.md:171-176 (§9) | owner ruling #16; test 51-templates.sh pins the text | ok |

## templates/checkpoint.md

| claim | location | evidence | result |
|---|---|---|---|
| the first status line is the one the runner reads | checkpoint.md:21 | lib/checkpoint.sh:5 | ok |
| one Phase plan heading; table rules; exit 10 naming the line | checkpoint.md:24-29 | lib/checkpoint.sh:10-99; lib/ci.sh:60-64 | ok |
| first 7 to 40 hex word; replace, never append | checkpoint.md:30-33 | lib/checkpoint.sh:55; lib/receipt.sh:51-52 | ok |
| ` · usage ...` written by the runner | checkpoint.md:34 | lib/checkpoint.sh:139 | ok |
| PR rule, exit 10, ci-wait record per PR | checkpoint.md:35-40 | lib/ci.sh:78-119 | ok |
| uncommitted path named whole, bare name in backticks, exit 7 | checkpoint.md:41-44 | lib/checkpoint.sh:120-130; lib/chain.sh:84 | ok |
| over 150 lines the runner warns before each child | checkpoint.md:45 | lib/checkpoint.sh:112-115 | ok |

## lib/*.sh header and doc comments

| claim | location | evidence | result |
|---|---|---|---|
| chain_accept: deleted once the run holds the lock; earlier exits leave it; a signal leaves it with no end line | lib/chain.sh:9-11 | lib/chain.sh:154-155, :164-169 | fixed (P6R3-9, -11: said "Each run deletes it first") |
| chain_count: COUNT_ERR names the file and, when readable, size and shape | lib/chain.sh:129 | lib/chain.sh:134-139 | fixed (P5R2-6) |
| chain_nums, chain_cap, chain_dirty, chain_lock, pid_start, chain_exit comments | lib/chain.sh:12-120 | the functions they head | ok |
| child.sh comments (server env, scrub, PATH/BLAST_OFF, launch, wait codes 0-3, CHILD_RC/NOSTATUS, trust window) | lib/child.sh:2-95 | the functions they head | ok |
| checkpoint.sh cp_scan modes and rules; cp_names; cp_mark_usage | lib/checkpoint.sh:4-142 | the functions they head | ok |
| ci.sh ci_wait exit 0 green, 10 red or no runs; dispatch left out; ci_check rules | lib/ci.sh:4-134 | the functions they head | ok |
| jev.sh levels, question, fallbacks, key handling | lib/jev.sh:2-80 | the functions they head | ok |
| preflight.sh header refusals: brief.md, CLAUDE_FLAGS, deps or gh, child-count, estimate; JOB_* before any line | lib/preflight.sh:2-6 | lib/preflight.sh:13-17, :39, :98 | fixed (brief.md and gh missing) |
| preflight.sh: start passes the key when Jev can use it (sk-or-, JOB_JEV not 0) | lib/preflight.sh:21 | lib/units.sh:23 | fixed (P7R2-2: said "when it is set") |
| receipt.sh: exit 0 PASS, 1 otherwise; refusal logged, nothing written | lib/receipt.sh:14-18 | lib/receipt.sh:11-38 | ok |
| units.sh: naming rule, UNIT_ENV, resume, status, stop, wait comments | lib/units.sh:2-161 | the functions they head | ok |
| usage.sh: record shape, LIMIT_EXIT 75, pause and arm rules | lib/usage.sh:2-83 | the functions they head | ok |

## tests/*.sh header comments

| claim | location | evidence | result |
|---|---|---|---|
| 00, 10, 11, 12, 13, 20, 21, 22, 23, 30, 32, 40, 41, 50, 51, 61, 70 headers | tests/NN-*.sh:2-9 | each file's own assertions (tok.sh greps listed above for the rows) | ok |
| 31: after the reset resume starts the runner unit, which sets running | tests/31-resume-after-reset.sh:3 | lib/units.sh:54-59; lib/chain.sh:185-191 | fixed (said resume "sets running") |
| 60: start passes the key when Jev can use it | tests/60-preflight.sh:4 | lib/units.sh:23 | fixed (P7R2-2) |
| 60: exit 1 with every line printed, but a bad JOB_* number prints only its refused line | tests/60-preflight.sh:8-10 | lib/preflight.sh:15 | fixed (P5R2-7) |
| lib.sh: names start with $TEST_ID | tests/lib.sh:2-4 | tests/lib.sh:7 | ok |

## Open doc findings from #36, #40, #42, #46, #47

| claim | location | evidence | result |
|---|---|---|---|
| #36 rulings (row commit in its PR, *.yml only, branch-scoped runs, no /pull/N) | docs/spec.md:104; README.md:149-155 | not built (lib/ci.sh:67-68 still reads `/pull/N`, :111 any file); docs describe the code as built, which is correct | ok (docs match code; rulings are future work) |
| P5R2-6 "exit 1 above"; byte-size promise | docs/spec.md:63, :68; lib/chain.sh:129 | see rows above | fixed (counted above) |
| P5R2-7 test 60 header | tests/60-preflight.sh:8-10 | lib/preflight.sh:15 | fixed (counted above) |
| P6R1-18 wait codes outside the runner's range; README exit-1 row | docs/spec.md:118-119; README.md:126 | §3 table | fixed (counted above) |
| P6R1-19 background command timeout | docs/spec.md:61 | no evidence | deleted (counted above) |
| P6R3-9 runner-end with no end line | docs/spec.md:48-49 | lib/chain.sh:166 | fixed (counted above) |
| P6R3-11 when runner-end is absent | docs/spec.md:49-51; README.md:113 | lib/chain.sh:154-169; README's "writes only when it accepts" is true | fixed (counted above); README ok |
| P6R3-12 field lengths, `·` handling, row 13, "not at once" | README.md:116-117; docs/spec.md:61, :248 | lib/units.sh:157-160; test 13-wait.sh:91-95, :132 | fixed / deleted (counted above) |
| P6R3-14 limits stretch with a long poll | README.md:125; docs/spec.md:61, :116; bin/blast-off:14-16 | lib/units.sh:135-140 | fixed (counted above) |
| #46 P7R2-2 comments "when it is set" | lib/preflight.sh:21; tests/60-preflight.sh:4 | lib/units.sh:23 | fixed (counted above) |
| #46 P7R2-4 SKILL.md step 7 key condition | SKILL.md:68-69 | lib/units.sh:23 | fixed (counted above) |
| #46 P7R2-16 row 12 points at a row-11 claim | docs/spec.md:246-247 | test 11-unit-smoke.sh:90-99 | fixed (counted above) |
| #47 "README.md:97 and SKILL.md:73 say watch a child's window only; never answer a prompt in it" | README.md, SKILL.md | text not present at 9c86128 (grep "never answer": no hit) | ok (nothing to check; owner question stays in #47) |
| #47 P8R2-3 step 9 text checked anywhere in §9 | docs/spec.md:259 | test 51-templates.sh:98; the row says "section 9 text (step 9 in the template)", true of the template | ok |
