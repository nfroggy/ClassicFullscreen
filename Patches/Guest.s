/* Revision18 Guest patches, assembled at Classic FILE-relative addresses.
 * Branch labels include unchanged Classic continuations/import stubs.
 * The native build rejects relocations and generates payload/image checksums.
 * Update manifest ranges when changing patch locations or lengths. */
.text
.org 0x26ef4
L_00026ef4:
/* Native application enumeration: expose eligible OS X apps, hide the real OS X Finder. */
.org 0x2983c
    lwz r9, 0x48(r1)
L_00029840:
    lwz r7, 0x40(r1)
    lwz r8, 0(r7)
    lwz r10, 0x24(r9)
    cmplw r8, r10
    bc 12,0,L_00029868
    bc 12,1,L_000298d8
    lwz r8, 4(r7)
    lwz r10, 0x28(r9)
    cmplw r8, r10
    bc 4,0,L_000298d8
L_00029868:
    lwz r8, 0x3c(r9)
    andis. r8, r8, 0x100
    bc 4,2,L_00029878
    stw r9, 0x44(r1)
L_00029878:
    lwz r9, 0x14(r9)
    cmplwi r9, 0
    bc 4,2,L_00029840
    b L_000298d8
L_00029888:
    lwz r11, 0x3c(r4)
    andis. r11, r11, 0x100
    bc 12,2,L_0002a40c
    lwz r11, 8(r4)
    xoris r11, r11, 0x4d41
    cmplwi r11, 0x4353
    bc 12,2,L_0002a400
    b L_0002a40c
L_000298a8:
    lwz r11, 0x2954(r2)
    cmpwi r11, 0
    bc 12,2,L_000298d0
    lwz r12, 0x3c(r11)
    andis. r12, r12, 0x100
    bc 12,2,L_000298d0
    lwz r12, 8(r11)
    xoris r12, r12, 0x4d41
    cmplwi r12, 0x4353
    beqlr
L_000298d0:
    mflr r0
    b L_0003a434
L_000298d8:
.org 0x2a048
    cmpwi r3, 0
    bc 12,2,L_0002a068
    addi r4, r2, 0x23c4
    cmplw r3, r4
    bc 12,2,L_0002a068
    lwz r4, 0x3c(r3)
    andis. r4, r4, 0x100
    bc 12,2,L_0002a07c
L_0002a068:
    li r3, -0x258
    b L_0002a398
    .long 0  /* verified unused padding */
    .long 0  /* verified unused padding */
    .long 0  /* verified unused padding */
L_0002a07c:
.org 0x2a398
L_0002a398:
.org 0x2a3fc
    bc 4,2,L_00029888
L_0002a400:
.org 0x2a40c
L_0002a40c:
/* Keep Finder desktop ownership without the port-breaking Finder rename. */
.org 0x2aad8
    b L_0002ab68
.org 0x2ab68
L_0002ab68:
.org 0x2d154
L_0002d154:
/* Guest application exit handoff. */
.org 0x2d954
    b L_0002d974
L_0002d958:
    lwz r0, 0x7c(r1)
    cmpwi r0, 0
    bc 12,2,L_0002d96c
    bl L_0003a860
    lwz r2, 0x14(r1)
L_0002d96c:
    b L_0003a870
    .long 0  /* verified unused padding */
L_0002d974:
.org 0x2e304
L_0002e304:
.org 0x2ed8c
L_0002ed8c:
/* Remember a valid guest successor before the application exits. */
.org 0x2f670
    li r0, 0
    stw r0, 0x7c(r1)
    lwz r3, -0x30c(r2)
    lbz r4, 0(r3)
    cmpwi r4, 0
    bc 12,2,L_0002f6c8
    lwz r3, -0x1a8(r2)
    lbz r4, 0(r3)
    cmpwi r4, 0
    bc 12,2,L_0002f6c8
    lwz r3, 0x3c(r1)
    lwz r4, 0x3c(r3)
    andis. r4, r4, 0x100
    bc 4,2,L_0002f6c8
    bl L_0004d5c4
    lwz r2, 0x14(r1)
    lwz r3, 0x3c(r1)
    lwz r4, 0x24(r3)
    lwz r5, 0x28(r3)
    stw r4, 0x74(r1)
    stw r5, 0x78(r1)
    stw r3, 0x7c(r1)
L_0002f6c8:
    lwz r3, 0x3c(r1)
    lha r4, 0x40(r1)
    lbz r5, 0x64(r1)
    bl L_0002e304
    bl L_0002ed8c
    b L_0002f758
L_0002f6e0:
    lwz r0, 0x7c(r1)
    cmpwi r0, 0
    bc 12,2,L_0002f750
    lbz r4, 0x54(r1)
    cmpwi r4, 0
    bc 12,2,L_0002f748
    lwz r3, 0x48(r1)
    cmpwi r3, 0
    bc 12,2,L_0002f748
    addi r3, r1, 0x80
    bl L_0004d42c
    lwz r2, 0x14(r1)
    cmpwi r3, 0
    bc 4,2,L_0002f748
    lwz r3, 0x80(r1)
    lwz r4, 0x74(r1)
    cmplw r3, r4
    bc 4,2,L_0002f748
    lwz r3, 0x84(r1)
    lwz r4, 0x78(r1)
    cmplw r3, r4
    bc 4,2,L_0002f748
    lwz r3, 0x48(r1)
    addi r3, r3, 0x24
    bl L_0004d984
    lwz r2, 0x14(r1)
L_0002f748:
    bl L_0003a860
    lwz r2, 0x14(r1)
L_0002f750:
    addi r12, r2, 0x7c8
    b L_0002fa28
L_0002f758:
/* Choose a guest successor rather than falling back to a native OS X process. */
.org 0x2f91c
    b L_0002d958
L_0002f920:
    bl L_0003736c
    lbz r3, 0x54(r1)
    cmpwi r3, 0
    bc 12,2,L_0002fa24
    lwz r3, 0x295c(r2)
    cmpwi r3, 0
    bc 4,2,L_0002f9b0
    bl L_0003d184
    cmpwi r3, 0
    bc 4,2,L_0002f9b0
    lwz r3, -0x2a8(r2)
    lwz r3, 0(r3)
    cmpwi r3, 0
    bc 12,2,L_0002f964
    addi r3, r3, 0x10
    bl L_0002fc54
    b L_0002f9b0
L_0002f964:
    lbz r3, 0x7a8(r2)
    cmpwi r3, 0
    bc 12,2,L_0002f97c
    li r3, 0
    bl L_00026ef4
    b L_0002f9a4
L_0002f97c:
    li r3, 0
    li r4, 1
    bl L_0004cb74
    lwz r2, 0x14(r1)
    cmpwi r3, 0
    bc 4,2,L_0002f9a4
    li r3, 0
    li r4, 0
    bl L_0004cb74
    lwz r2, 0x14(r1)
L_0002f9a4:
    cmpwi r3, 0
    bc 12,2,L_0002f9b0
    lwz r3, 0x98(r3)
L_0002f9b0:
    cmpwi r3, 0
    bc 12,2,L_0002fa18
    lwz r4, 0x3c(r3)
    andis. r4, r4, 0x100
    bc 12,2,L_0002fa18
    lwz r3, 0x297c(r2)
    bl L_0004d5dc
    lwz r2, 0x14(r1)
    li r0, 0x1000
    mtctr r0
L_0002f9d8:
    cmpwi r3, 0
    bc 12,2,L_0002fa18
    lwz r4, 0x98(r3)
    cmpwi r4, 0
    bc 12,2,L_0002fa0c
    lwz r5, 0x3c(r4)
    andis. r5, r5, 0x100
    bc 4,2,L_0002fa0c
    lbz r5, 0x6e(r3)
    cmpwi r5, 0
    bc 12,2,L_0002fa0c
    mr r3, r4
    b L_0002fa18
L_0002fa0c:
    lwz r3, 0x90(r3)
    bc 16,0,L_0002f9d8
    li r3, 0
L_0002fa18:
    stw r3, 0x48(r1)
    lwz r4, -0x2fc(r2)
    stw r3, 0(r4)
L_0002fa24:
    b L_0002f6e0
L_0002fa28:
    lbz r3, 0x7c8(r2)
    cmpwi cr6, r3, 0
    bc 12,2,L_0002fa3c
    bl L_0002d154
    nop
L_0002fa3c:
.org 0x2fc54
L_0002fc54:
.org 0x3736c
L_0003736c:
/* Bounded application-menu lookup. */
.org 0x3a098
    b L_0003a850
L_0003a09c:
.org 0x3a16c
L_0003a16c:
.org 0x3a430
    b L_000298a8
L_0003a434:
/* Application-menu lookup/checkmark guards. */
.org 0x3a814
L_0003a814:
.org 0x3a818
    mr r4, r3
    lwz r5, 0x23fc(r2)
    li r3, 5
L_0003a824:
    cmplwi r5, 0
    bc 12,2,L_0003a844
    cmplw r5, r4
    bc 12,2,L_0003a848
    lwz r5, 0x38(r5)
    addi r3, r3, 1
    cmplwi r3, 0x7fff
    bc 12,0,L_0003a824
L_0003a844:
    li r3, 0
L_0003a848:
    addi r1, r1, 0x40
    blr
L_0003a850:
    bl L_0003a814
    cmpwi r3, 0
    bc 12,2,L_0003a16c
    b L_0003a09c
L_0003a860:
    addi r3, r1, 0x74
    lbz r4, 0x54(r1)
    lha r5, 0x40(r1)
    b L_0004e224
L_0003a870:
    li r0, 0
    stw r0, 0x7c(r1)
    b L_0002f920
    .long 0  /* verified unused padding */
.org 0x3d184
L_0003d184:
.org 0x3e420
    li r3, 0x3f2
    nop
.org 0x4cb74
L_0004cb74:
.org 0x4d42c
L_0004d42c:
.org 0x4d5c4
L_0004d5c4:
.org 0x4d5dc
L_0004d5dc:
.org 0x4d984
L_0004d984:
.org 0x4e224
L_0004e224:
/* BBVShowCursor: use the direct-rendering cursor protection path. */
.org 0xd2124
    li r3, 0
/* BBVShieldCursor: pair shielding with the direct-rendering path. */
.org 0xd2a94
    li r3, 0
.org 0xd2a9c
/* DragManagerINITIALIZE: keep drags inside the OS 9 Drag Manager.
 * CoreDrag only routes drops through native window regions. Finder's desktop
 * has an empty native structure region, so a desktop drop never reaches the
 * guest receive handler in fullscreen. Leave the bridge disabled consistently
 * for registration, tracking, flavor data and drop locations; changing only
 * TrackDrag would mix the two protocols. These patches are session-scoped. */
.org 0x1f20dc
    li r7, 0
