#!/bin/sh
# Tiger hardware test. Run as the desktop user, with Classic stopped.
# UI-only processes never request authorization or install/restore patches.
set -eu
app=${1:?canonical absolute app executable path}
probe=${2:?absolute LaunchPathProbe executable path}
bundle=$(dirname "$(dirname "$(dirname "$app")")")
test ! -e /var/run/classic-fullscreen-switch/session.state
test "$(id -u)" != 0
scratch=$(mktemp -d /tmp/classic-launch-paths.XXXXXX)
ui=
cleanup() {
    if test -n "$ui"; then
        kill "$ui" 2>/dev/null || true
        wait "$ui" 2>/dev/null || true
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ln -s "$app" "$scratch/Linked Classic"
check() {
    "$1" --ui-only >"$scratch/ui.log" 2>&1 &
    ui=$!
    sleep 2
    kill -0 "$ui"
    "$probe" "$ui" "$app" "$(id -u)"
    test ! -e /var/run/classic-fullscreen-switch/session.state
    kill "$ui"
    wait "$ui" 2>/dev/null || true
    ui=
    echo "PASS: $1"
}
check "$app"
cd "$(dirname "$bundle")"
check "$(basename "$bundle")/Contents/MacOS/$(basename "$app")"
cd "$(dirname "$app")"
check "./$(basename "$app")"
check "../MacOS/./$(basename "$app")"
check "$scratch/Linked Classic"
cd "$scratch"
check './Linked Classic'
echo 'PASS: canonical identity and original PID/account for all six launch paths'
