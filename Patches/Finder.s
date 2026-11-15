/* Revision18 Finder patches, assembled at Classic FILE-relative addresses.
 * Branch labels include unchanged Classic continuations/import stubs.
 * The native build rejects relocations and generates payload/image checksums.
 * Update manifest ranges when changing patch locations or lengths. */
.text
/* Keep stack-backed catalog reads alive until completion. Leave r30 zero so
 * both the legacy read and any extended catalog lookup use existing sync
 * paths, including Finder's normal completion fixup and result handling. */
.org 0x195d8
    b L_000195ec
.org 0x195ec
L_000195ec:
/* Test no-write permission rather than not-owner before serializing folder layout. */
.org 0x50e88
    rlwinm. r0, r0, 0x1e, 0x1f, 0x1f
/* The shared file/folder serializer separately checks the CONTAINING folder
 * before copying icon positions (and folder-layout flags). A writable folder
 * owned by root is not read-only. Keep the absent-container/error paths. */
.org 0x5bb28
    rlwinm. r0, r0, 0x1e, 0x1f, 0x1f
/* Use Finder's existing synchronous catalog-save path. */
.org 0x16ae4c
    b L_0016ae84
.org 0x16ae84
L_0016ae84:
.org 0x16ae88
