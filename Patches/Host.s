/* Revision18 Host patches, assembled at Classic FILE-relative addresses.
 * Branch labels include unchanged Classic continuations/import stubs.
 * The native build rejects relocations and generates payload/image checksums.
 * Update manifest ranges when changing patch locations or lengths. */
.text
/* Cooperative framebuffer/private-RAM handoff. Preserve old pixels through guest End. */
.org 0x1100
L_00001100:
    mfcr r2
    mflr r0
    stmw r22, -0x28(r1)
    lis r9, 0x5e0a
    mr r30, r3
    mr r28, r4
    ori r9, r9, 0x4400
    addi r25, r3, 0x1f7
    stw r0, 8(r1)
    li r0, 0
    addi r23, r3, 0x1d0
    stw r2, 4(r1)
    stwu r1, -0x80(r1)
    addi r24, r4, 8
    stw r0, 0x38(r1)
    lwz r2, 0(r9)
    lwz r29, 0x1d0(r3)
    lwz r26, 8(r4)
    addi r2, r2, 1
    stw r2, 0(r9)
    stw r29, 4(r9)
    stw r26, 8(r9)
    lwz r0, 0x1cc(r3)
    cmpwi cr7, r0, 1
    bc 4,30,L_00001340
    /* The iBook enumerates an inactive second display. Require the target
     * descriptor to be active, not the total descriptor count to equal one. */
    lwz r0, 0x80(r4)
    cmpwi cr7, r0, 1
    bc 4,30,L_00001340
    lwz r0, 0x10(r3)
    cmpw cr7, r0, r4
    bc 4,30,L_00001340
    cmpwi cr7, r26, 0
    bc 12,30,L_00001340
    cmplwi cr7, r29, 1
    bc 12,29,L_00001340
    lwz r0, 0x20(r9)
    cmpwi cr7, r0, 0
    bc 4,30,L_00001340
    lwz r0, 0xc(r4)
    cmpwi cr7, r0, 0
    bc 4,30,L_00001340
    lwz r0, 0x10(r4)
    cmpwi cr7, r0, 0
    bc 4,30,L_00001340
    lwz r0, 0x14(r4)
    cmpwi cr7, r0, 0
    bc 12,30,L_00001340
    lfs f0, 0x18(r4)
    fctiwz f0, f0
    stfd f0, 0x40(r1)
    lwz r27, 0x44(r1)
    addi r0, r27, -0x1e0
    cmplwi cr7, r0, 0x690
    bc 12,29,L_00001340
    lwz r0, 0x20(r4)
    cmpwi cr7, r0, 8
    bc 12,30,L_000011ec
    cmpwi cr7, r0, 0x20
    bc 4,30,L_00001340
L_000011ec:
    lwz r2, 0x1c(r4)
    addi r2, r2, -1
    cmplwi cr7, r2, 0x7fff
    bc 12,29,L_00001340
    addi r2, r4, 0x1c
    nop
    cmpwi cr4, r29, 0
    lwz r0, 0(r2)
    mullw r27, r0, r27
    bc 12,18,L_00001244
    lis r2, 0x5e0a
    ori r2, r2, 0x4400
    lwz r0, 0x24(r2)
    cmpwi cr7, r0, 0
    bc 4,30,L_00001348
    mr r3, r27
    li r31, -0x6c
    bl L_0007a50c
    cmpwi cr7, r3, 0
    stw r3, 0x38(r1)
    bc 4,30,L_00001264
    b L_0000134c
L_00001244:
    lis r2, 0x5e0a
    ori r2, r2, 0x4400
    lwz r0, 0x24(r2)
    cmpw cr7, r26, r0
    bc 4,30,L_00001348
    lwz r0, 0x28(r2)
    cmpw cr7, r27, r0
    bc 4,30,L_00001348
L_00001264:
    li r0, 1
    lbz r22, 0(r25)
    stb r0, 0(r25)
    lwz r3, 0(r30)
    bl L_0007c9cc
    cmpwi cr3, r3, 0
    mr r31, r3
    bc 4,14,L_00001328
    bc 4,18,L_000012b8
    lwz r3, 0(r28)
    addi r4, r1, 0x38
    bl L_0007ca9c
    cmpwi cr3, r3, 0
    mr r31, r3
    bc 4,14,L_00001320
    lwz r0, 0x38(r1)
    cmpwi cr7, r0, 0
    bc 12,30,L_00001318
    cmpw cr7, r26, r0
    bc 4,30,L_000012bc
    b L_00001318
L_000012b8:
    lwz r0, 0x38(r1)
L_000012bc:
    mr r3, r0
    mr r4, r26
    mr r5, r27
    bl L_0007a49c
    lwz r0, 0x38(r1)
    stw r0, 0(r24)
    bc 12,18,L_000012f4
    li r31, 0
    lis r2, 0x5e0a
    cmpwi cr3, r31, 0
    ori r2, r2, 0x4400
    stw r0, 0x24(r2)
    stw r27, 0x28(r2)
    b L_00001320
L_000012f4:
    lis r2, 0x5e0a
    li r31, 0
    mr r3, r26
    ori r2, r2, 0x4400
    cmpwi cr3, r31, 0
    stw r29, 0x24(r2)
    stw r29, 0x28(r2)
    nop
    b L_00001320
L_00001318:
    li r31, -0x6c
    cmpwi cr3, r31, 0
L_00001320:
    lwz r3, 0(r30)
    bl L_0007c73c
L_00001328:
    stb r22, 0(r25)
    bc 12,14,L_00001358
    bc 12,18,L_0000134c
    lwz r3, 0x38(r1)
    bl L_0007a5fc
    b L_0000134c
L_00001340:
    cmpwi cr4, r29, 0
    li r27, 0
L_00001348:
    li r31, -0x32
L_0000134c:
    mfcr r0
    rlwinm r0, r0, 0x13, 0x1f, 0x1f
    stw r0, 0(r23)
L_00001358:
    lwz r0, 0(r24)
    lis r2, 0x5e0a
    addi r1, r1, 0x80
    mr r3, r31
    ori r2, r2, 0x4400
    stw r0, 0xc(r2)
    stw r27, 0x1c(r2)
    stw r31, 0x18(r2)
    lwz r11, 4(r1)
    lwz r0, 8(r1)
    lmw r22, -0x28(r1)
    mtlr r0
    mtocrf 0x10, r11
    mtocrf 8, r11
    blr
L_00001394:
    lis r11, 0x5e0a
    lwz r11, 0x3530(r11)
    cmpwi r11, 0
    bc 12,2,L_000013f0
    lwz r12, 0x1cc(r11)
    cmpwi r12, 1
    bc 4,2,L_000013f0
    lwz r12, 0x1d0(r11)
    cmpwi r12, 1
    bc 4,2,L_000013f0
    lwz r11, 0x10(r11)
    cmpwi r11, 0
    bc 12,2,L_000013f0
    lwz r12, 0(r11)
    cmpw r12, r3
    bc 4,2,L_000013f0
    lis r12, 0x5e0a
    lwz r12, 0x4424(r12)
    cmpwi r12, 0
    bc 12,2,L_000013f0
    stw r12, 0(r4)
    li r3, 0
    blr
L_000013f0:
    b L_0007ca9c
.org 0x1400
L_00001400:
    lis r11, 0x5e0a
    lwz r11, 0x3530(r11)
    cmpwi r11, 0
    bc 12,2,L_0000146c
    lwz r12, 0x1cc(r11)
    cmpwi r12, 1
    bc 4,2,L_0000146c
    lwz r12, 0x14(r11)
    cmpwi r12, 1
    bc 4,2,L_0000146c
    lbz r12, 0x1f6(r11)
    cmpwi r12, 1
    bc 4,2,L_0000146c
    lwz r11, 0x10(r11)
    cmpwi r11, 0
    bc 12,2,L_0000146c
    lwz r11, 8(r11)
    cmpwi r11, 0
    bc 12,2,L_0000146c
    li r12, 0x824
    lwz r12, 0(r12)
    cmpwi r12, 0
    bc 12,2,L_0000146c
    cmpw r11, r12
    bc 12,2,L_0000146c
    li r3, 0
    blr
L_0000146c:
    mflr r3
    b L_00057794
L_00001474:
    lis r11, 0x5e0a
    li r0, 0
    stw r0, 0x4600(r11)
    lwz r12, 0x3530(r11)
    cmpwi r12, 0
    bc 12,2,L_000014f4
    lwz r0, 0x1cc(r12)
    cmpwi r0, 1
    bc 4,2,L_000014f4
    lwz r12, 0x10(r12)
    lwz r0, 0x20(r12)
    cmpwi r0, 8
    bc 4,2,L_000014f4
    lwz r3, 0x8a4(0)
    lwz r3, 0(r3)
    lwz r3, 0x16(r3)
    lwz r3, 0(r3)
    lwz r3, 0x2a(r3)
    lwz r3, 0(r3)
    lhz r0, 6(r3)
    cmpwi r0, 0xff
    bc 4,2,L_000014f4
    addi r4, r11, 0x4608
    li r5, 0x202
    mtctr r5
L_000014d8:
    lwz r5, 0(r3)
    stw r5, 0(r4)
    addi r3, r3, 4
    addi r4, r4, 4
    bc 16,0,L_000014d8
    li r0, 1
    stw r0, 0x4600(r11)
L_000014f4:
    mflr r3
    b L_0004b8c0
    .long 0  /* verified unused padding */
L_00001500:
    mflr r0
    stmw r27, -0x14(r1)
    mr r31, r3
    stw r0, 8(r1)
    lis r0, 0x5e07
    stwu r1, -0x200(r1)
    ori r0, r0, 0xce3c
    mtctr r0
    mr r12, r0
    bctrl
    cmpwi cr7, r3, -0x1388
    bc 4,30,L_000016d0
    lis r30, 0x5e07
    li r4, 0
    li r5, 0x48
    addi r3, r1, 0x38
    ori r30, r30, 0xc56c
    addi r28, r1, 0x80
    mtctr r30
    mr r12, r30
    bctrl
    lwz r2, 0x12(r31)
    lhz r9, 0x16(r31)
    lis r0, 0x5e07
    addi r3, r1, 0x38
    lwz r11, 0x30(r31)
    stw r28, 0x74(r1)
    ori r0, r0, 0xd71c
    mtctr r0
    stw r2, 0x4a(r1)
    sth r9, 0x4e(r1)
    stw r11, 0x68(r1)
    mr r12, r0
    bctrl
    cmpwi cr7, r3, 0
    bc 4,30,L_000016cc
    lis r0, 0x5e07
    addi r27, r1, 0x13c
    mr r3, r28
    li r4, 0x16
    ori r0, r0, 0xce2c
    mr r5, r27
    li r6, 0
    li r7, 0
    mtctr r0
    li r8, 0
    mr r12, r0
    bctrl
    cmpwi cr7, r3, 0
    bc 4,30,L_000016cc
    lhz r0, 0x13c(r1)
    andi. r2, r0, 0x10
    bc 12,2,L_000016cc
    mtctr r30
    addi r29, r1, 0xd0
    li r4, 0
    li r5, 0x6c
    mr r12, r30
    mr r3, r29
    bctrl
    lhz r0, 0x13e(r1)
    lwz r2, 0x144(r1)
    lis r9, 0x5e07
    mr r3, r29
    ori r9, r9, 0xce8c
    mtctr r9
    sth r0, 0xe6(r1)
    li r0, -1
    stw r2, 0x100(r1)
    sth r0, 0xec(r1)
    mr r12, r9
    bctrl
    cmpwi cr7, r3, 0
    bc 4,30,L_000016cc
    lbz r0, 0xee(r1)
    andi. r2, r0, 0x10
    bc 12,2,L_000016cc
    lwz r0, 0x48(r31)
    lwz r2, 0x118(r1)
    cmpw cr7, r2, r0
    bc 4,30,L_000016cc
    lwz r0, 0x4c(r31)
    lwz r2, 0x11c(r1)
    cmpw cr7, r2, r0
    bc 4,30,L_000016cc
    lwz r0, 0x50(r31)
    lwz r2, 0x120(r1)
    cmpw cr7, r2, r0
    bc 4,30,L_000016cc
    lis r29, 0x5e07
    addi r4, r31, 0x20
    li r5, 0x10
    addi r3, r1, 0x184
    ori r29, r29, 0xc49c
    mtctr r29
    mr r12, r29
    bctrl
    mtctr r29
    addi r4, r31, 0x54
    li r5, 0x10
    mr r12, r29
    addi r3, r1, 0x194
    bctrl
    lis r0, 0x5e07
    mr r3, r28
    mr r5, r27
    li r4, 0x1800
    ori r0, r0, 0xcdcc
    mtctr r0
    mr r12, r0
    bctrl
    or. r0, r3, r3
    bc 4,2,L_000016cc
    sth r0, 0x10(r31)
    b L_000016d0
L_000016cc:
    li r3, -0x1388
L_000016d0:
    addi r1, r1, 0x200
    lwz r0, 8(r1)
    lmw r27, -0x14(r1)
    mtlr r0
    blr
L_000016e4:
    lis r12, 0x5e0a
    lwz r11, 0x4410(r12)
    addi r11, r11, 1
    stw r11, 0x4410(r12)
    b L_00001474
    .long 0  /* verified unused padding */
    .long 0  /* verified unused padding */
L_00001700:
    mflr r0
    stw r0, 8(r1)
    stwu r1, -0x50(r1)
    bl L_00001740
L_00001710:
    lwz r0, 0x58(r1)
    addi r1, r1, 0x50
    mtlr r0
    b L_00001400
L_00001720:
    stw r3, 0x3c(r1)
    lwz r3, 0x20(r31)
    cmplwi r3, 0x1000
    bc 12,0,L_000018a8
    lwz r4, 0x24(r31)
    addi r0, r4, -1
    cmplwi r0, 0xffff
    b L_000018c4
L_00001740:
    stw r30, 0x48(r1)
    stw r31, 0x4c(r1)
    lis r31, 0x5e0a
    ori r31, r31, 0x4100
    lis r0, 0x436c
    ori r0, r0, 0x5377
    lwz r3, 0(r31)
    cmpw r3, r0
    bc 4,2,L_000018b8
    lwz r3, 0x18(r31)
    addi r3, r3, 1
    stw r3, 0x18(r31)
    lwz r30, 4(r31)
    lwz r0, 8(r31)
    cmpw r30, r0
    bc 12,2,L_000018b8
    lwz r0, 0x1c(r31)
    cmpwi r0, 0
    bc 4,2,L_000018b8
    sync
    lwz r3, -0xbd0(r31)
    li r0, -0x32
    stw r0, 0x14(r31)
    cmpwi r3, 0
    bc 12,2,L_000018b0
    lwz r0, 0x1cc(r3)
    cmpwi r0, 1
    bc 4,2,L_000018b0
    lwz r0, 0x10(r3)
    cmpwi r0, 0
    bc 12,2,L_000018b0
    lwz r11, 0x180(r3)
    cmpwi r11, 0
    bc 12,2,L_000018b0
    li r0, -0x2f
    stw r0, 0x14(r31)
    lwz r0, 0x1d4(r3)
    cmpwi r0, 0
    bc 4,2,L_000018b8
    lwz r0, 0x188(r3)
    cmpwi r0, 0
    bc 4,2,L_000018b8
    lwz r0, 0(r11)
    cmpwi r0, 0
    bc 4,2,L_000018b8
    li r0, 1
    stw r0, 0x1c(r31)
    lwz r5, 0x10(r31)
    cmplwi r5, 6
    bc 12,1,L_000018a8
    cmpwi r5, 2
    bc 12,0,L_00001840
    cmpwi r5, 3
    bc 12,1,L_00001868
    subfic r4, r5, 3
    lwz r0, 0x1d0(r3)
    cmpw r0, r4
    bc 12,2,L_000018a8
    stw r4, 0x1d0(r3)
    sync
    addi r5, r5, 1
    stw r5, 0(r11)
    li r3, 0
    b L_000018a4
L_00001840:
    cmpwi r5, 1
    bc 12,2,L_00001854
    lwz r0, 0x1d0(r3)
    cmpwi r0, 1
    bc 4,2,L_000018a8
L_00001854:
    lwz r3, 0(r3)
    lwz r4, 0xc(r31)
    li r6, 0
    bl L_0007c8ac
    b L_000018a4
L_00001868:
    lwz r0, 0x1d0(r3)
    cmpwi r0, 0
    bc 4,2,L_000018a8
    cmpwi r5, 6
    bc 12,2,L_00001720
    lwz r4, 0xc(r31)
    cmpwi r4, 0
    bc 12,2,L_000018a8
    lwz r3, 0(r3)
    cmpwi r5, 5
    li r5, 0
    bc 12,2,L_000018a0
    lis r5, 0x7fff
    ori r5, r5, 0xffef
L_000018a0:
    bl L_0007c8bc
L_000018a4:
    stw r3, 0x14(r31)
L_000018a8:
    li r0, 0
    stw r0, 0x1c(r31)
L_000018b0:
    sync
    stw r30, 8(r31)
L_000018b8:
    lwz r30, 0x48(r1)
    lwz r31, 0x4c(r1)
    b L_00001710
L_000018c4:
    bc 12,1,L_000018a8
    addi r5, r1, 0x38
    lis r12, -0x6fc5
    ori r12, r12, 0x972c
    mtctr r12
    bctrl
    cmpwi r3, 0
    bc 4,2,L_000018a4
    lwz r3, 0x3c(r1)
    lwz r4, 0x10(r3)
    lwz r4, 0x7c(r4)
    lwz r3, 0(r3)
    lwz r7, 0x38(r1)
    li r0, 0
    stw r0, 0x44(r1)
    lfs f1, 0x44(r1)
    fmr f2, f1
    b L_00070e88
L_0000190c:
    lis r11, 0x5e0a
    lwz r5, 0x4600(r11)
    cmpwi r5, 2
    bc 12,0,L_00001998
    lwz r0, 0x1d4(r30)
    cmpwi r0, 1
    bc 4,2,L_00001998
    lwz r0, 0x4418(r11)
    cmpwi r0, 0
    bc 4,2,L_00001998
    cmpwi r31, 0
    bc 4,2,L_00001998
    cmpwi r27, 0xff
    bc 4,2,L_00001998
    lwz r3, 0x8a4(0)
    lwz r3, 0(r3)
    lwz r3, 0x16(r3)
    lwz r3, 0(r3)
    lwz r3, 0x2a(r3)
    lwz r3, 0(r3)
    addi r12, r3, 8
    cmpw r25, r12
    bc 4,2,L_00001998
    addi r5, r5, 1
    stw r5, 0x4600(r11)
    lwz r0, 0(r3)
    stw r0, 0x4604(r11)
    addi r4, r11, 0x4608
    li r5, 0x202
    mtctr r5
L_00001984:
    lwz r0, 0(r4)
    stw r0, 0(r3)
    addi r3, r3, 4
    addi r4, r4, 4
    bc 16,0,L_00001984
L_00001998:
    lwz r3, 0x78(r28)
    b L_0004a1b8
L_000019a0:
    lis r12, 0x5e0a
    lwz r11, 0x4414(r12)
    addi r11, r11, 1
    stw r11, 0x4414(r12)
    b L_000549f8
    nop
    nop
    nop
.org 0x125ec
    li r3, 1
.org 0x1e348
    bl L_00001500
.org 0x1e450
    bl L_00001500
.org 0x4a06c
    bl L_00001100
    b L_0007ffe4
.org 0x4a0e0
L_0004a0e0:
.org 0x4a1b4
    b L_0000190c
L_0004a1b8:
.org 0x4b8bc
    b L_000016e4
L_0004b8c0:
.org 0x4b8fc
    b L_000019a0
L_0004b900:
.org 0x4cdb0
    li r3, 1
.org 0x4cdec
    b L_0004ce04
.org 0x4ce04
L_0004ce04:
.org 0x52b18
    nop
.org 0x52ee8
    bl L_00001394
.org 0x52f5c
    bl L_00001394
.org 0x53be8
    bl L_00001394
.org 0x542c0
    lis r11, 0x5e0a
    lwz r0, 0x4418(r11)
    cmpwi r0, 0
    bc 4,2,L_00054af0
    lwz r0, 0x4408(r11)
    b L_00054aa0
    nop
.org 0x54364
L_00054364:
.org 0x5496c
    nop
.org 0x549cc
    nop
/* Retain the original palette seed after validating all color entries. */
.org 0x549f8
L_000549f8:
    lis r11, 0x5e0a
    lwz r0, 0x4600(r11)
    cmpwi r0, 2
    bc 12,0,L_00054a90
    lwz r12, 0x8a4(0)
    cmpwi r12, 0
    bc 12,2,L_00054a90
    lwz r12, 0(r12)
    cmpwi r12, 0
    bc 12,2,L_00054a90
    lwz r12, 0x16(r12)
    cmpwi r12, 0
    bc 12,2,L_00054a90
    lwz r12, 0(r12)
    cmpwi r12, 0
    bc 12,2,L_00054a90
    lwz r12, 0x2a(r12)
    cmpwi r12, 0
    bc 12,2,L_00054a90
    lwz r12, 0(r12)
    cmpwi r12, 0
    bc 12,2,L_00054a90
    lhz r0, 6(r12)
    cmpwi r0, 0xff
    bc 4,2,L_00054a90
    addi r3, r12, 4
    addi r4, r11, 0x460c
    li r5, 0x201
    mtctr r5
L_00054a6c:
    lwz r0, 0(r3)
    lwz r5, 0(r4)
    cmpw r0, r5
    bc 4,2,L_00054a90
    addi r3, r3, 4
    addi r4, r4, 4
    bc 16,0,L_00054a6c
    lwz r0, 0x4608(r11)
    stw r0, 0(r12)
L_00054a90:
    li r0, 0
    stw r0, 0x4600(r11)
    mflr r2
    b L_0004b900
L_00054aa0:
    cmpwi r0, 0
    bc 12,2,L_00054af0
    lwz r3, 0(r31)
    bl L_0007c9cc
    lis r11, 0x5e0a
    stw r3, 0x4e18(r11)
    cmpwi r3, 0
    bc 4,2,L_00054ad8
    lwz r3, 0x440c(r11)
    lwz r4, 0x4408(r11)
    lwz r5, 0x441c(r11)
    bl L_0007a49c
    lwz r3, 0(r31)
    bl L_0007c73c
L_00054ad8:
    lis r11, 0x5e0a
    lwz r0, 0x4404(r11)
    cmpwi r0, 0
    bc 4,2,L_00054af0
    lwz r3, 0x4408(r11)
    bl L_0007a5fc
L_00054af0:
    lis r11, 0x5e0a
    li r0, 0
    stw r0, 0x4408(r11)
    stw r0, 0x1d4(r31)
    b L_00054364
.org 0x556f8
    bc 12,25,L_00055708
.org 0x55708
L_00055708:
    li r0, 1
    b L_0005572c
    lwz r2, 0x16c(r31)
    cmpwi r2, 0
    bc 4,1,L_00055728
.org 0x55728
L_00055728:
    li r0, 0
L_0005572c:
.org 0x55e08
    lwz r3, 0x1cc(r3)
    or r3, r3, r2
    nop
.org 0x55f54
    b L_00055f80
.org 0x55f68
    nop
.org 0x55f80
L_00055f80:
.org 0x56704
    nop
.org 0x56754
    nop
.org 0x57790
    b L_00001700
L_00057794:
.org 0x58014
    li r4, 0
.org 0x5b0c0
    li r3, 0
.org 0x5c91c
    li r3, 0
.org 0x5d680
    bc 12,2,L_0005d698
.org 0x5d698
L_0005d698:
.org 0x5d708
    bc 12,2,L_0005d720
.org 0x5d720
L_0005d720:
/* Finish cover-region update and release the temporary region. */
.org 0x70e88
L_00070e88:
    bl L_0007d16c
    stw r3, 0x40(r1)
    lwz r3, 0x38(r1)
    bl L_0007d15c
    lwz r3, 0x40(r1)
    b L_000018a4
.org 0x7a49c
L_0007a49c:
.org 0x7a50c
L_0007a50c:
.org 0x7a5fc
L_0007a5fc:
.org 0x7c73c
L_0007c73c:
.org 0x7c8ac
L_0007c8ac:
.org 0x7c8bc
L_0007c8bc:
.org 0x7c9cc
L_0007c9cc:
.org 0x7ca9c
L_0007ca9c:
.org 0x7d15c
L_0007d15c:
.org 0x7d16c
L_0007d16c:
/* Palette preservation commit marker. */
.org 0x7ffe4
L_0007ffe4:
    lis r11, 0x5e0a
    lwz r0, 0x4600(r11)
    cmpwi r0, 1
    bc 4,2,L_0007fffc
    li r0, 2
    stw r0, 0x4600(r11)
L_0007fffc:
    b L_0004a0e0
.org 0x80004
