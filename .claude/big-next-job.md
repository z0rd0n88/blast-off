# blast-off: notes for jobs in this repo

Per-repo source for gates, reviewers, fixer and phase names (prompt §6).

- **Gate:** `tests/run` from the repo root. Prints one line, `GATE: PASS ...` (exit 0) or
  `GATE: FAIL ...` (exit 1). It runs every `tests/NN-*.sh` in its own temp dir, then
  `shellcheck -S warning` over `bin/blast-off`, `lib/*.sh`, `tests/*.sh`, `tests/run`.
  A run with zero scenarios, or without shellcheck installed, is a FAIL.
- **Gate evidence:** full output to `.big-next-job/gate-logs/phase-<n>.log`; receipt to
  `gate-logs/phase-<n>.json` (by hand until `blast-off receipt` exists).
- **Review:** `dw-review` on `<base>...HEAD`, at most 3 read-only reviewers per round, lenses
  change every round; `finding-fixer` applies fixes above LOW; LOW is recorded, never fixed.
- **Test names:** any tmux session or systemd unit a scenario starts is named
  `blast-off-test-<pid>-*` (`$TEST_ID` in `tests/lib.sh`); never stop what a test did not start.
- **Per-commit LLM plugins:** `security-guidance@claude-plugins-official` is off in
  `.claude/settings.json` (owner opt-out). No other per-commit LLM hook is enabled here.
- **Branches:** one per phase, stacked: `feat/00-spec` → `feat/01-tracer` → `feat/02-liveness`
  → `feat/03-usage` → `feat/04-receipts` → `feat/05-templates` → `feat/06-jev-preflight`
  → `feat/07-docs-skill` → `feat/08-gate-delivery`. Merge bottom-up.
- **Runtime deps:** bash, tmux, jq, python3, systemd (user scope), claude, gh. Dev: shellcheck.
