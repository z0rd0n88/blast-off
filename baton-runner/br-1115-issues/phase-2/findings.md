# Findings (context pack)
- `lib/receipt.sh:6-9` `receipt_verdict`: last non-empty line must start `GATE: `, else receipt_write refuses ("the last line of ... is not a GATE: verdict"), writes nothing, logs `receipt refused:` to run.log. A line starting `GATE: ` but not `GATE: PASS` gets a FAIL receipt written, so the filtered prefix must not start `GATE: ` at all.
- Other readers of the verdict line: `scripts/gate.sh` (comment only), `tests/51-templates.sh` (calls receipt_verdict on a fake gate), README/SKILL/brief prose. None parse a filtered line.
- `tests/run:19-21` reads then unsets BLAST_OFF_TEST_KEEP; same shape for the new var.
- `docs/spec.md:215` is the 00-harness row; `:206` the one-line gate description.
- ci.yml triggers: pull_request and workflow_dispatch only (no push).
