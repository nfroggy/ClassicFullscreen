#!/bin/sh
# Build-time checks only, against private fixtures. No installed files are changed.
set -eu
cd "$(dirname "$0")/.."
PATCH_FIXTURES=${1:?private fixture directory (absolute path)}
CHECK_ROOT=$(/usr/bin/mktemp -d -t classic-assembly)
trap 'rm -rf "$CHECK_ROOT"' EXIT HUP INT TERM
/bin/sh ./build-patches.sh "$CHECK_ROOT/objects" "$CHECK_ROOT/resources" "$PATCH_FIXTURES"
/usr/bin/gcc -arch ppc -mmacosx-version-min=10.4 -O2 -Wall -Wextra \
    Tests/PatchPackTests.m -framework Foundation -o "$CHECK_ROOT/PatchPackTests"
"$CHECK_ROOT/PatchPackTests" Patches/Manifest.plist "$CHECK_ROOT/objects" \
    "$CHECK_ROOT/resources" "$PATCH_FIXTURES" "$CHECK_ROOT"

# An unresolved target must never be emitted as a usable patch resource.
printf '.text\nbl missing_patch_target\n' > "$CHECK_ROOT/unresolved.s"
/usr/bin/as -arch ppc "$CHECK_ROOT/unresolved.s" -o "$CHECK_ROOT/objects/Host.o"
if "$CHECK_ROOT/objects/PatchPack" Patches/Manifest.plist "$CHECK_ROOT/objects" \
    "$CHECK_ROOT/resources" "$PATCH_FIXTURES" > "$CHECK_ROOT/result" 2>&1; then
    echo 'FAIL: unresolved branch was accepted' >&2
    exit 1
fi
/usr/bin/grep -q 'Unresolved relocation' "$CHECK_ROOT/result"
echo 'PASS: unresolved branch rejected'
