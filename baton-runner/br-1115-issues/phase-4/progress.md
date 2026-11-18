# Phase 4 progress

- planning files written
- RED 10-chain-done (new cap re-run assertions) on old lib/chain.sh: FAIL "re-run at a reached cap launched a child"
- lib/chain.sh: chain_count / chain_count_set, cap compares LAUNCHED+1-BASE, paused-cap resume sets BASE, count saved before child_launch
- GREEN 10-chain-done PASS; mutation checks: save-after-wait -> hup block FAIL; garbled-as-0 -> badcount block FAIL
- 21-soft-cap: added numbering-goes-on + relaunch-at-cap assertions; RED on old chain.sh, mutation without BASE reset FAIL, GREEN PASS
- Blast radius: reruns in 11,12,22,23,30,31,40,41 read; only 11 (start_hang greps child=1 and child-1.scope) needed a change: rm child-count in start_hang; 40 two comments
- Ran alone, in order: 11 PASS, 23 PASS, 40 PASS, 70-docs PASS; ExecStart checked after 10, 11, 23/40: unchanged
- docs/spec.md (env JOB_MAX_CHILDREN, exit 1, 4, 6, test rows 10 and 21), README exit 4 and 6 rows
- shellcheck -S warning clean on the 5 changed scripts
