#!/bin/sh
# Visible Tiger hardware test, EMPTY Finder only, Classic initially stopped.
# Stage a verified current Host patch (never garbage) to simulate an interrupted
# installation. Test startup both with and without its saved session record.
# The Python 2.3 setup below is test-only; the application uses no Python.
set -eu
app=${1:?absolute application executable path}
fixtures=${2:?private fixture directory with reviewed Host.patched}
state=/var/run/classic-fullscreen-switch/session.state
test "$(id -u)" != 0
test ! -e "$state"
folder=$("$app" --action system-folder)
wait_state() {
    attempt=0
    while test "$attempt" -lt 150; do
        actual=$(cat "$state" 2>/dev/null || true)
        test "$actual" = "$1" && return 0
        test "$actual" = Z && return 1
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}
for journal in yes no; do
    sudo -S -p '' "$app" --check-only </dev/null
    sudo -S -p '' /usr/bin/python - "$app" "$fixtures" "$(id -u)" "$folder" "$journal" <<'PY'
import fcntl, md5, os, plistlib, stat, sys, tempfile
from StringIO import StringIO
app, fixtures, uid, folder, journal = sys.argv[1:]
lock = os.open('/var/run/classic-fullscreen-session.lock', os.O_WRONLY | os.O_CREAT, 0600)
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
run = '/var/run/classic-fullscreen-switch'
assert not os.path.exists(run + '/session.state')
assert not os.path.exists(run + '/session.configuration')
# Tiger's Python parser requires a dictionary at the root, not an array.
xml = file(os.path.dirname(os.path.dirname(app)) + '/Resources/Patches/Manifest.plist', 'rb').read()
xml = xml.replace('<plist version="1.0">', '<plist version="1.0"><dict><key>specs</key>', 1)
xml = xml.replace('</plist>', '</dict></plist>', 1)
manifest = plistlib.Plist.fromFile(StringIO(xml))['specs']
host = [s for s in manifest if s['name'] == 'Host'][0]
path = host['path']
backup = path + host['backup']
for p in (path, backup):
    info = os.lstat(p)
    assert stat.S_ISREG(info.st_mode) and info.st_nlink == 1
    assert md5.new(file(p, 'rb').read()).hexdigest() == host['baseMD5']
data = file(os.path.join(fixtures, 'Host.patched'), 'rb').read()
assert len(data) == host['length'] and md5.new(data).hexdigest() == host['patchedMD5']
info = os.stat(path)
if not os.path.exists(run): os.mkdir(run, 0755)
if journal == 'yes':
    directory = os.stat(folder)
    saved = plistlib.Plist(UserID=int(uid), SystemFolder=folder,
                          Device=int(directory.st_dev), Inode=int(directory.st_ino))
    fd = os.open(run + '/session.configuration', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0600)
    out = os.fdopen(fd, 'wb')
    saved.write(out)
    out.flush()
    os.fsync(out.fileno())
    out.close()
fd, temporary = tempfile.mkstemp(prefix='.classic-auto-test-', dir=os.path.dirname(path))
try:
    out = os.fdopen(fd, 'wb')
    out.write(data)
    out.flush()
    os.chown(temporary, info.st_uid, info.st_gid)
    os.chmod(temporary, stat.S_IMODE(info.st_mode))
    os.fsync(out.fileno())
    out.close()
    os.rename(temporary, path)
finally:
    if os.path.exists(temporary): os.unlink(temporary)
print 'Staged verified Host patch; interrupted-session record:', journal
PY
    "$app" --action preferences-on
    sudo -S -p '' "$app" --guardian </dev/null &
    guardian=$!
    wait_state C
    ps -p "$guardian" >/dev/null
    echo "PASS: automatic recovery continued to fullscreen Finder (saved record: $journal)"
    "$app" --action stop
    wait "$guardian"
    test ! -e "$state"
    test ! -e /var/run/classic-fullscreen-switch/session.configuration
    sudo -S -p '' "$app" --check-only </dev/null
    echo "PASS: normal shutdown and stock restoration (saved record: $journal)"
done
