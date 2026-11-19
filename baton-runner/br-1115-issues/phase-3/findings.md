# Findings (context pack)
- `lib/ci.sh`: `ci_wait` lists by commit twice (`:19,29`), records `{id,name,conclusion}`; `ci_check` (`:53`) greps the whole checkpoint for `PR #N`/`/pull/N`; `absent` branch logs and passes after `ci_head`.
- `lib/chain.sh:132-140`: `TOP` = git toplevel of the workdir, empty when not a repo (receipt and dirty checks off). `:159` calls `receipt_all_done; ci_check` at done.
- `lib/receipt.sh:44-63`: in a git workdir every done row needs a sha in history and a matching PASS receipt.
- `tests/fakes/gh`: `run list` ignores `--json`; no event field.
- Spec text on absent CI: `docs/spec.md:35` (F7), `:58` (ci-wait), `:97` (exit 10), `:228` (41 row). No `D18` literal in spec; only in the decision log tsv (history, not edited).
