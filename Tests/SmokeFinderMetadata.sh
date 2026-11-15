#!/bin/sh
# Visible integration test. Prepare a disposable root:admin 0775 parent with
# root:admin 0664 TEXT/ttxt File, root:admin 0775 Folder, and user-owned TEXT/ttxt
# UserFile. All must be accessible to OS 9 (e.g. under Applications (Mac OS 9)).
# Run seed, close/reopen, then verify. Repeat verify after shutdown/relaunch.
# A zero file type is NOT a valid fixture: stock Finder treats it as busy.
set -eu
helper=${1:?AppleEvent helper}
finder=${2:?exact OS 9 Finder executable path}
fixture=${3:?disposable fixture folder}
phase=${4:?seed or verify}
event() { "$helper" "$finder" "$@"; }
expect() {
    want=$1; shift
    actual=$(event "$@")
    test "$actual" = "$want" || { echo "FAIL: $*: $actual (expected $want)" >&2; exit 1; }
}
if test "$phase" = seed; then
    event open "$fixture"
    event set "$fixture/File" posn point 140 110
    event set "$fixture/Folder" posn point 260 170
    event set "$fixture/UserFile" posn point 80 230
    event set "$fixture/File" labi long 3
    event set "$fixture/Folder" labi long 5
    event set "$fixture/File" comt text 'Metadata persistence test'
    event set "$fixture/Folder" comt text 'Folder metadata test'
    event setwin "$fixture" pbnd rect 130 230 500 750
    event open "$fixture/Folder"
    event setwin "$fixture/Folder" pvew enum pnam
    event setwin "$fixture/Folder" pbnd rect 200 350 550 850
    event close "$fixture/Folder"
    event close "$fixture"
elif test "$phase" != verify; then exit 2; fi
event open "$fixture"
expect QDpt:006e008c get "$fixture/File" posn
expect QDpt:00aa0104 get "$fixture/Folder" posn
expect QDpt:00e60050 get "$fixture/UserFile" posn
expect long:00000003 get "$fixture/File" labi
expect long:00000005 get "$fixture/Folder" labi
expect TEXT:4d657461646174612070657273697374656e63652074657374 get "$fixture/File" comt
expect TEXT:466f6c646572206d657461646174612074657374 get "$fixture/Folder" comt
expect qdrt:008200e601f402ee getwin "$fixture" pbnd
event open "$fixture/Folder"
expect enum:706e616d getwin "$fixture/Folder" pvew
expect qdrt:00c8015e02260352 getwin "$fixture/Folder" pbnd
event close "$fixture/Folder"
event close "$fixture"
echo 'PASS: Finder file/folder icon positions, labels, comments, window bounds and list view'
