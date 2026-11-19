#!/usr/bin/env bash
# 12-start-env: every entry point refuses a child with no CLAUDE_FLAGS (K8, D8): `run` exits 1
# before the first child and launches nothing.
source "$REPO/tests/lib.sh"
use_fakes
export GH_TOKEN=dummy-not-a-token
bo="$REPO/bin/blast-off"

new_job run 'done'
rc=0; env -u CLAUDE_FLAGS "$bo" run "$JOB" > run.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "run without CLAUDE_FLAGS exit $rc: $(cat run.out)"
grep -q CLAUDE_FLAGS run.out || fail "refusal does not name CLAUDE_FLAGS: $(cat run.out)"
[ ! -e "$JOB/fake-marker" ] || fail "a child launched without CLAUDE_FLAGS"
rc=0; CLAUDE_FLAGS='' "$bo" run "$JOB" > run2.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "run with empty CLAUDE_FLAGS exit $rc"
[ ! -e "$JOB/fake-marker" ] || fail "a child launched with empty CLAUDE_FLAGS"


# start refuses before creating any unit: --setenv=NAME would turn an unset name into an empty value
new_job start 'done'
rc=0; env -u CLAUDE_FLAGS "$bo" start "$JOB" > s1.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q CLAUDE_FLAGS s1.out || fail "start without CLAUDE_FLAGS: exit $rc: $(cat s1.out)"
rc=0; CLAUDE_FLAGS="--model fake --effort low" GH_TOKEN='' "$bo" start "$JOB" > s2.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q GH_TOKEN s2.out || fail "start with empty GH_TOKEN: exit $rc: $(cat s2.out)"
rc=0; CLAUDE_FLAGS="--model fake --effort low" env -u GH_TOKEN "$bo" start "$JOB" > s3.out 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q GH_TOKEN s3.out || fail "start without GH_TOKEN: exit $rc: $(cat s3.out)"
[ "$(systemctl --user show "$TEST_ID-start.service" -p LoadState --value)" = not-found ] || fail "a refused start left a unit"
[ ! -e "$JOB/fake-marker" ] || fail "a refused start launched a child"

# --- issue 27: start, resume and the resume timer pass OPENROUTER_API_KEY by name when it is set, never its value ---
# A stub systemd-run records its argv and whether the key reached it; any other call (a child scope) goes to the real one.
key=sk-or-test-xxx-not-a-key-27
mkdir -p stub
{ echo '#!/usr/bin/env bash'
  printf '[[ " $* " != *" --scope "* ]] || exec %q "$@"\n' "$(command -v systemd-run)"
  printf 'printf "%%s\\n" "$@" "key=${OPENROUTER_API_KEY:+set}" > %q/argv-$$\n' "$PWD/stub"; } > stub/systemd-run
chmod +x stub/systemd-run
export CLAUDE_FLAGS="--model fake --effort low"
argv() { cat stub/argv-* 2>/dev/null; rm -f stub/argv-*; }
nokey() { ! grep -qr -- "$key" "$@" || fail "the key's value is in $(grep -rl -- "$key" "$@")"; }

new_job keyed 'done'
rc=0; OPENROUTER_API_KEY="$key" PATH="$PWD/stub:$PATH" "$bo" start "$JOB" > k1.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "start with the key: exit $rc: $(cat k1.out)"
a="$(argv)"
grep -qx -- '--setenv=OPENROUTER_API_KEY' <<<"$a" || fail "start does not pass --setenv=OPENROUTER_API_KEY: $a"
grep -qx 'key=set' <<<"$a" || fail "systemd-run did not get the key in its environment: $a"
grep -q -- '--setenv=OPENROUTER_API_KEY ' k1.out || fail "start's printed launch line has no --setenv=OPENROUTER_API_KEY: $(cat k1.out)"
grep -q -- "$key" <<<"$a" && fail "the key's value is on systemd-run's argv"
nokey k1.out "$JOB"

for e in unset empty; do
  rc=0
  if [ $e = unset ]; then PATH="$PWD/stub:$PATH" "$bo" start "$JOB" > k2.out 2>&1 || rc=$?
  else OPENROUTER_API_KEY='' PATH="$PWD/stub:$PATH" "$bo" start "$JOB" > k2.out 2>&1 || rc=$?; fi
  [ "$rc" -eq 0 ] || fail "start with the key $e: exit $rc: $(cat k2.out)"
  a="$(argv)"; grep -q -- '--setenv=GH_TOKEN' <<<"$a" || fail "start with the key $e: no launch recorded: $a"
  ! grep -q OPENROUTER <<<"$a" || fail "start with the key $e passes it: $a"
done

# resume of a paused-cap job starts the unit with the name too
new_job keyres 'done'
sed -i 's/^status: .*/status: paused-cap/' "$JOB/checkpoint.md"
rc=0; OPENROUTER_API_KEY="$key" PATH="$PWD/stub:$PATH" "$bo" resume "$JOB" > k3.out 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "resume with the key: exit $rc: $(cat k3.out)"
a="$(argv)"; grep -qx -- '--setenv=OPENROUTER_API_KEY' <<<"$a" || fail "resume does not pass --setenv=OPENROUTER_API_KEY: $a"
nokey k3.out "$JOB"

# the resume timer armed at a usage pause carries the name, so its later resume (and start) gets the key
new_job keytimer die75
rc=0; OPENROUTER_API_KEY="$key" FAKE_JEV="$PWD/jev" JOB_CHILD_TIMEOUT=30 BLAST_OFF_STATE_DIR="$PWD/state" PATH="$PWD/stub:$PATH" \
  "$bo" run "$JOB" > k4.out 2>&1 || rc=$?
[ "$rc" -eq 8 ] || fail "die75 run with the key: exit $rc, want 8: $(cat k4.out)"
a="$(argv)"
grep -q -- '--on-calendar' <<<"$a" || fail "no resume timer armed: $a; $(cat "$JOB/run.log")"
grep -qx -- '--setenv=OPENROUTER_API_KEY' <<<"$a" || fail "the resume timer does not pass --setenv=OPENROUTER_API_KEY: $a"
grep -q -- "$key" <<<"$a" && fail "the key's value is on the timer's systemd-run argv"
nokey k4.out "$JOB"
echo ok
