# Progress
- 2026-11-15 slice 1+2: test first in tests/00-harness.sh, red (fixture saw the var), implemented in tests/run, green; three mutations each turned one assertion red.
- slice 3+4: ci.yml env + upload-artifact `if: failure()` (YAML parses); header comment; spec row 215.
- slice 5: `tests/run` GATE: PASS passed=18 failed=0 shellcheck=ok, with the var unset and set. Closed, uncommitted (manager owns git). Details: ../baton-phase-1-work.md
