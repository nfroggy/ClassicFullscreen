#!/bin/sh
# Interactive-display hardware test. Classic must be stopped, with no apps to
# preserve. Explicitly selects a depth at the current resolution, starts an
# empty Finder session, tests menu/Dock-equivalent activation, then stops it.
# Usage: sh SmokeColorModes.sh APP_EXECUTABLE DISPLAY_MODES_HELPER DEPTH
set -eu
app=${1:?app executable}
modes=${2:?DisplayModes helper}
depth=${3:?8, 16 or 32}
case "$depth" in 8|16|32) ;; *) exit 2 ;; esac
state=/var/run/classic-fullscreen-switch/session.state
test ! -e "$state"
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
sudo "$app" --check-only
"$modes" set "$depth"
sudo "$app" --guardian &
guardian=$!
wait_state C
"$modes" check "$depth"
"$app" --action finder-osx
wait_state A
"$modes" check "$depth"
"$app" --action return
wait_state C
"$modes" check "$depth"
"$app" --action finder-osx
wait_state A
"$modes" check "$depth"
"$app" --action return
wait_state C
"$modes" check "$depth"
"$app" --action stop
wait "$guardian"
test ! -e "$state"
echo "PASS: $depth-bit startup, two OS X round trips and normal shutdown"
