#!/bin/sh
# Visible hardware test: start an EMPTY Finder session, restart it twice,
# switch to OS X and back after each restart, then shut down normally.
# Classic must be stopped; do not open applications during this test.
set -eu
app=${1:?absolute app executable path}
state=/var/run/classic-fullscreen-switch/session.state
test ! -e "$state"
host_pid() {
    ps -axww -o pid,command | awk '
      $2 == "/System/Library/CoreServices/Classic" &&
      $3 == "Startup.app/Contents/Resources/TruBlueEnvironment" { print $1 }'
}
wait_state() {
    expected=$1
    attempt=0
    while test "$attempt" -lt 150; do
        actual=$(cat "$state" 2>/dev/null || true)
        test "$actual" = "$expected" && return 0
        test "$actual" = Z && return 1
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}
check_helpers() {
    ps -axww -o pid,ppid,command | awk -v app="$app" -v host="$1" '
      index($0, app) && $0 ~ ("--controller " host "$") { controller++ }
      index($0, app) && index($0, "--emergency " host " ") { watcher++ }
      END { exit !(controller == 1 && watcher == 1) }'
}
sudo "$app" --check-only
sudo "$app" --guardian &
guardian=$!
wait_state C
for cycle in 1 2; do
    old=$(host_pid)
    test -n "$old"
    check_helpers "$old"
    "$app" --action restart
    attempt=0
    while :; do
        new=$(host_pid)
        test -n "$new" && test "$new" != "$old" && break
        test "$attempt" -lt 150
        sleep 1
        attempt=$((attempt + 1))
    done
    # The new host can appear before the old controller clears state C.
    # Wait for both new helpers as well as the new session's ready state.
    attempt=0
    while ! check_helpers "$new" || test "$(cat "$state" 2>/dev/null || true)" != C; do
        test "$attempt" -lt 150
        sleep 1
        attempt=$((attempt + 1))
    done
    ps -p "$guardian" >/dev/null
    # Apple's startup application should finish once the new Finder is active.
    attempt=0
    while ps -axww -o command | awk '
      $1 == "/System/Library/CoreServices/Classic" &&
      $2 == "Startup.app/Contents/MacOS/Classic" && $3 == "Startup" { found=1 }
      END { exit !found }'; do
        test "$attempt" -lt 60
        sleep 1
        attempt=$((attempt + 1))
    done
    "$app" --action finder-osx
    wait_state A
    "$app" --action return
    wait_state C
    echo "PASS: restart $cycle ($old -> $new), new helpers and OS X round trip"
done
"$app" --action stop
wait "$guardian"
test ! -e "$state"
test -z "$(host_pid)"
echo 'PASS: normal shutdown after repeated restarts'
