#!/bin/sh
set -eu
cd "$(dirname "$0")"
PATCH_BUILD=${1:?object directory}
PATCH_OUTPUT=${2:?resource directory}
PATCH_BASELINES=${3:-${PATCH_BASELINES:-}}
mkdir -p "$PATCH_BUILD" "$PATCH_OUTPUT"
/usr/bin/gcc -arch ppc -mmacosx-version-min=10.4 -O2 -Wall -Wextra PatchPack.m -framework Foundation -framework Carbon -o "$PATCH_BUILD/PatchPack"
for name in Host Guest Finder Resources Indexed Sleep; do
 /usr/bin/as -arch ppc "Patches/$name.s" -o "$PATCH_BUILD/$name.o"
done
"$PATCH_BUILD/PatchPack" Patches/Manifest.plist "$PATCH_BUILD" "$PATCH_OUTPUT" "$PATCH_BASELINES"
