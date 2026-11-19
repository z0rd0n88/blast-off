# Phase 8 work: issue #16 (tool denials come from the harness, never the owner)

Commit: 71abdef (feat(templates): tool denials come from the harness, never the owner (#16))

## What changed
- templates/brief.md:69-72 (section 4, Stop condition): added one sentence after "or a refused tool call blocks that part.":
  "Every tool denial in this run comes from the harness, never the owner: it is not a rejection of your work."
- tests/51-templates.sh:97-99: asserts the flattened brief contains
  "or a refused tool call blocks that part. Every tool denial in this run comes from the harness, never the owner"
  (anchored to the stop-condition clause, so dropping or moving the sentence fails).
- docs/spec.md:253 (51-templates row): names the new check (#16).

## Red
  | FAIL: brief stop condition lacks: or a refused tool call blocks that part. Every tool denial in this run comes from the harness, never the owner
GATE-ONLY: FAIL passed=0 failed=1 shellcheck=ok only=51-templates

## Green
GATE-ONLY: PASS passed=2 failed=0 shellcheck=ok only=51-templates,70-docs

## Ledger (stop-condition lines 69-72)
- Preserved: the four stop triggers (change outside target set and may-widen list; decision the brief lacks; reviewer or gate that cannot run; refused tool call), "blocks that part", "Finish the independent work, record it." (reflowed to its own line, text unchanged).
- Changed: none.
- Added: "Every tool denial in this run comes from the harness, never the owner: it is not a rejection of your work."

## Reviewer should check
- Issue text also says "retry with a narrower command". Left out on purpose per the devil's-advocate note (add only the harness wording; existing line already makes a refusal a blocked part). Retrying a classifier denial could also read as working around it. Decide whether the retry clause belongs.
- Edit is in section 4 (Stop condition), not section 9 "Child protocol"; the issue calls it the child protocol, the DA note pointed at :69-71. Section 9 item 9 ("Blocked parts do not stop the job") untouched.
- "in this run" used for "in an unattended run" (the brief already establishes the job is unattended).
- No em dashes or curly quotes in the touched lines.
