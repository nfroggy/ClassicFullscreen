#!/bin/sh
# Visible hardware test, empty Finder only. Classic must initially be stopped.
# Expire the idle deadline, observe real BAL sleep, then activate the launcher's
# proxy exactly as a generic Dock click does. No guest activation precedes it.
set -eu
app=${1:?application executable}
probe=${2:?IdleWakeProbe executable}
state=/var/run/classic-fullscreen-switch/session.state
test ! -e "$state"
wait_state() {
    for attempt in $(jot 120); do
        test "$(cat "$state" 2>/dev/null || true)" = "$1" && return 0
        sleep 1
    done
    return 1
}
sudo -S -p '' "$app" --guardian </dev/null &
guardian=$!
wait_state C
host=$(ps -axww -o pid,command | awk '
    $2 == "/System/Library/CoreServices/Classic" &&
    $3 == "Startup.app/Contents/Resources/TruBlueEnvironment" {print $1}')
test -n "$host"
ui=$(ps -axww -o pid,ppid,command | awk -v guardian="$guardian" '
    $2 == guardian && $NF == "--ui-only" {print $1}')
test -n "$ui"
proxy=$("$app" --action list 2>&1 | awk -v pid="pid=$ui" '
    $2 == pid && $3 == "mode=000000c0" && $4 == "creator=436c5377" {
        split($1,p,":");print p[2]}')
test -n "$proxy"
for cycle in 1 2 3; do
    for attempt in $(jot 30); do
        status=$(sudo -S -p '' "$probe" status "$host" </dev/null)
        case "$status" in 'sleep=0 mode=40 '*'away=0 pending=0 request=0 '*) break;; esac
        sleep 1
    done
    before=$(sudo -S -p '' "$probe" expire-foreground "$host" </dev/null)
    sleep 3
    status=$(sudo -S -p '' "$probe" status "$host" </dev/null)
    case "$status" in 'sleep=0 mode=40 '*'away=0 pending=0 request=0 '*) ;; *) exit 1;; esac
    case "$status" in *'deadline=00000000:00000000') exit 1;; esac
    test "$(echo "$status" | cut -d' ' -f3)" != "$(echo "$before" | cut -d' ' -f3)"
    echo "PASS: Finder kept ticking through an expired foreground deadline"
    "$app" --action finder-osx
    wait_state A
    sudo -S -p '' "$probe" expire-idle "$host" </dev/null
    for attempt in $(jot 15); do
        status=$(sudo -S -p '' "$probe" status "$host" </dev/null)
        case "$status" in 'sleep=1 mode=80 '*) break;; esac
        sleep 1
    done
    case "$status" in 'sleep=1 mode=80 '*) ;; *) exit 1;; esac
    echo "Sleeping: $status"
    "$app" --action native "$proxy"
    wait_state C
    # Wait beyond the previous ten-second handoff failure and confirm the
    # original host, guardian and controller survived, with no pending request.
    sleep 12
    status=$(sudo -S -p '' "$probe" status "$host" </dev/null)
    case "$status" in 'sleep=0 '*'away=0 pending=0 request=0 '*) ;; *) exit 1;; esac
    ps -p "$guardian" >/dev/null
    test "$(cat "$state")" = C
    echo "PASS: idle wake $cycle via native proxy; original Classic PID $host: $status"
done
if test "${3:-}" = failure; then
    # Stall only this empty test host. The wake failure must not initiate a
    # graphics transaction, terminate Classic, or kill its controller.
    "$app" --action finder-osx
    wait_state A
    sudo -S -p '' "$probe" expire-idle "$host" </dev/null
    sleep 2
    status=$(sudo -S -p '' "$probe" status "$host" </dev/null)
    case "$status" in 'sleep=1 mode=80 '*) ;; *) exit 1;; esac
    trap 'sudo -S -p "" /bin/kill -CONT "$host" </dev/null' EXIT HUP INT TERM
    sudo -S -p '' /bin/kill -STOP "$host" </dev/null
    "$app" --action native "$proxy"
    sleep 8
    test "$(cat "$state")" = A
    ps -p "$guardian" >/dev/null
    status=$(sudo -S -p '' "$probe" status "$host" </dev/null)
    case "$status" in *'away=1 pending=0 request=0 '*) ;; *) exit 1;; esac
    sudo -S -p '' /bin/kill -CONT "$host" </dev/null
    trap - EXIT HUP INT TERM
    "$app" --action native "$proxy"
    wait_state C
    echo 'PASS: unresponsive wake preserves session in OS X; retry returns normally'
fi
"$app" --action stop
wait "$guardian"
test ! -e "$state"
echo 'PASS: normal shutdown and restoration after idle wake cycles'
