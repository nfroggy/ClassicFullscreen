# Finder metadata persistence (revision 32)

Two independent checks prevented saving layouts in writable folders owned by
another account, such as Macintosh HD and Applications (Mac OS 9).

* Finder's shared file/folder serializer at file `0x5bc1c` copies icon positions
  only when its containing-folder predicate at `0x5bad8` allows it. That predicate
  tested `kioACUserNotOwner` (`0x80`), so both files and folders lost their icon
  positions in a writable root-owned parent. The patch at `0x5bb28` tests
  `kioACUserNoMakeChanges` (`0x04`) instead. Its missing-container path is intact.
  The other caller, the folder layout serializer, also saves its layout flag.
  The existing folder-window permission fix at `0x50e88` remains necessary.
* Tiger's legacy `PBSetCatInfoSync` submits three timestamps along with both
  FinderInfo blocks. It fails with `afpAccessDenied` on writable non-owned objects
  even when those timestamps are unchanged. The existing host fallback only
  accepted directories. It now handles files too: resolve an FSRef and FSSpec,
  reread legacy metadata using the resolved parent/name, verify the same node ID
  and all three timestamps, and retry only FinderInfo/FinderXInfo via FSRef.

The metadata payload still occupies the original host file range `0x1500..0x16e4`;
its runtime address is `0x5e003500`. The following display/switching code is not
relocated. Only this range and one additional Finder instruction changed. The
manifest's generated hashes cover the complete outputs. Source assembly, not a
second copy of a byte array or compiled C payload, defines the shipping patch.

The fallback copies both complete 16-byte metadata blocks, preserving fields
such as type/creator, icon position, labels, flags, window bounds, scrolling and
view state. Comment text is stored through the Desktop Manager separately;
the integration test checks it too. Nothing changes filesystem ownership,
permissions, timestamps, or file contents to enable a metadata write. The normal
legacy setter still runs first. Other errors, failed lookups, a changed node,
requested timestamp changes, and actual write denial keep their original error.

## Native instruction tests

Build these on PowerPC Tiger with GCC 4.0/Xcode 2.5. Use reviewed private images
produced by the patch build; do not run a live modified executable in a harness.

```
gcc -O2 -Wall -Wextra Tests/FinderIconTests.c -o /tmp/FinderIconTests
/tmp/FinderIconTests /path/to/Finder.patched
gcc -O2 -Wall -Wextra Tests/FinderCatalogTests.c -o /tmp/FinderCatalogTests
/tmp/FinderCatalogTests /path/to/Finder.patched
gcc -O2 -Wall -Wextra Tests/FinderMetadataTests.c -framework Carbon -o /tmp/FinderMetadataTests
```

The icon test executes the actual Finder predicate and serializer with all 256
permission bytes, files/folders, initialized/uninitialized locations, and absent
parents. It checks labels, extended metadata and pending dates, and verifies
that restoring the original instruction reproduces the rejection (15,369 checks).
The existing catalog test covers 256 synchronous read/completion/error cases.

The host test executes the actual assembled fallback with mocked services and
real HFS+ objects. Supply six disposable paths, in this order: a root:admin 0775
folder, root:admin 0555 folder, user-owned writable folder, root:admin 0664 file,
root:admin 0444 file, and user-owned writable file. Run as the session user,
never root. It tests parent/name, directory-ID and full-path requests, both full
FinderInfo blocks, lookup failures, identity changes, all three date guards,
return/PB preservation, real permissions and restoration (383 checks).

```
/tmp/FinderMetadataTests /path/to/Host.patched ROOT_WRITABLE_DIR ROOT_READONLY_DIR USER_DIR ROOT_WRITABLE_FILE ROOT_READONLY_FILE USER_FILE
```

## Live Finder test

`FinderMetadataEvents.c` targets the running OS 9 Finder by its executable path.
It never addresses OS X Finder by the ambiguous application name. Compile it
with `-framework Carbon`, and use `SmokeFinderMetadata.sh` with disposable
fixtures as described in that script. Run `seed`, then `verify` after normal
Classic shutdown and a fresh launch. The assertions cover file/folder icon
positions, labels, comments, window bounds and list view.

Use real Mac file types for Finder test documents (`TEXT`/`ttxt` is suitable).
Stock Finder deliberately treats type zero and `bzy ` through `bzy?` as busy
in its catalog-save guard at `0x16b0c8`. Shell-created untyped files therefore
give a misleading failure even when the metadata bridge works. That guard is
unchanged; the test does not disable copying/busy-file protection.

`FinderMetadataProbe.c` reads both metadata blocks and catalog IDs; its optional
`--same` mode compares unchanged-value legacy/modern setters. The GDB script and
`FinderCodeAddress.c` are diagnostic tools only, never installed into Classic.

Also run the app's `--self-test` and `Tests/check-assembly.sh` against reviewed
fixtures to verify packaging, installation, failure rollback and exact restore.
