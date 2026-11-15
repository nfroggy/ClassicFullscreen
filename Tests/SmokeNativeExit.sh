#!/bin/sh
# Visible hardware test with an already running, EMPTY fullscreen Finder.
# Creates disposable native windows, quits them, and checks native focus and
# explicit guest return. No existing OS X application is closed or hidden.
# Keep the physical controls idle during the test. Failure leaves Classic open.
# CLASSIC_TEST_COCOA=1 exercises NSApplication termination instead of Carbon.
set -eu
app=${1:?absolute ClassicFullscreen executable path}
probe=${2:?compiled NativeExitSmoke executable path}
state=/var/run/classic-fullscreen-switch/session.state
scratch=$(mktemp -d /tmp/classic-native-exit.XXXXXX)
a= b=
cleanup() {
    test -z "$a" || kill -TERM "$a" 2>/dev/null || true
    test -z "$b" || kill -TERM "$b" 2>/dev/null || true
    rm -f "$scratch/a" "$scratch/b"
    rmdir "$scratch"
}
trap cleanup EXIT
wait_state() {
    attempt=0
    while test "$(cat "$state" 2>/dev/null || true)" != "$1"; do
        test "$attempt" -lt 30
        sleep 1
        attempt=$((attempt + 1))
    done
}
check_front() {
    test "$("$probe" --front | awk '{print $2}')" = "$1"
    test "$(cat "$state")" = A
}
test "$(cat "$state")" = C
"$probe" 'Exit test B' >"$scratch/b" &
b=$!
wait_state A
sleep 1
"$probe" 'Exit test A' >"$scratch/a" &
a=$!
sleep 2
check_front "$a"
kill -TERM "$a"
wait "$a"
a=
sleep 2
check_front "$b"
echo 'PASS: quitting front native A activates next native B, staying in OS X'

"$probe" 'Exit test A' >"$scratch/a" &
a=$!
sleep 2
check_front "$a"
kill -TERM "$b"
wait "$b"
b=
sleep 1
check_front "$a"
echo 'PASS: quitting a background native app does not change foreground focus'

"$app" --action return
wait_state C
sleep 1
guest_front=$("$probe" --front)
kill -TERM "$a"
wait "$a"
a=
sleep 2
test "$(cat "$state")" = C
test "$("$probe" --front)" = "$guest_front"
echo 'PASS: native app quitting in the background preserves the active Classic app'
"$probe" 'Exit test A' >"$scratch/a" &
a=$!
wait_state A
sleep 1
check_front "$a"

"$app" --action return
wait_state C
sleep 1
kill -USR1 "$a"
wait_state A
sleep 1
check_front "$a"
echo 'PASS: explicit Classic return and subsequent native activation still switch'

kill -TERM "$a"
wait "$a"
a=
sleep 2
test "$(cat "$state")" = A
test "$("$probe" --front | awk '{print $2}')" -gt 0
echo 'PASS: quitting final disposable window remains in OS X with another native app'
"$app" --action return
wait_state C
echo 'PASS: Classic remains available after all exit tests'
