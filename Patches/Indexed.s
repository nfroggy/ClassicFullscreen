/* Revision18 Indexed patches, assembled at Classic FILE-relative addresses.
 * Branch labels include unchanged Classic continuations/import stubs.
 * The native build rejects relocations and generates payload/image checksums.
 * Update manifest ranges when changing patch locations or lengths. */
.text
.org 0xadf48
    stw r14, 0x18(r1)
    stw r15, 0x1c(r1)
    stw r16, 0x20(r1)
    stw r17, 0x24(r1)
    stw r18, 0x28(r1)
    stw r19, 0x2c(r1)
    stw r20, 0x30(r1)
    stw r21, 0x34(r1)
    lwz r14, 0x38(r1)
    lwz r15, 0x40(r1)
    lwz r16, 0x68(r1)
    extsh r16, r16
    lwz r17, 0x6c(r1)
    lwz r18, 0x70(r1)
    lwz r19, 0x58(r1)
    lwz r20, 0x60(r1)
    lwz r21, 0x5c(r1)
    lwz r0, 0x64(r1)
    lwz r3, 0x7c(r1)
    lwz r4, 0x78(r1)
    lwz r6, 0x74(r1)
    lwz r8, 0(r14)
    lwz r9, 4(r14)
    addi r14, r14, 8
    slw r10, r8, r3
    srw r12, r9, r4
    or r10, r10, r12
    nor r5, r10, r10
    cmpwi cr6, r16, 0
    bc 12,24,L_000ae058
L_000adfc0:
    cmplw cr7, r10, r5
    bc 12,30,L_000adffc
    mr r5, r10
    mr r7, r21
    cmpwi cr1, r7, 0
    bc 12,4,L_000adffc
L_000adfd8:
    slw r6, r6, r20
    srw r11, r10, r0
    slwi r11, r11, 2
    lwzx r12, r19, r11
    or r6, r6, r12
    slw r10, r10, r20
    addi r7, r7, -1
    cmpwi cr1, r7, 0
    bc 4,4,L_000adfd8
L_000adffc:
    cmpwi cr6, r17, -1
    bc 4,26,L_000ae00c
    stw r6, 0(r15)
    b L_000ae024
L_000ae00c:
    lwz r12, 0(r15)
    andc r12, r12, r17
    and r11, r6, r17
    or r12, r12, r11
    stw r12, 0(r15)
    li r17, -1
L_000ae024:
    addi r15, r15, 4
    mr r8, r9
    lwz r9, 0(r14)
    addi r14, r14, 4
    slw r10, r8, r3
    srw r12, r9, r4
    or r10, r10, r12
    cmpwi cr7, r16, 1
    bc 4,30,L_000ae04c
    mr r17, r18
L_000ae04c:
    addi r16, r16, -1
    cmpwi cr1, r16, 0
    bc 4,4,L_000adfc0
L_000ae058:
    stw r6, 0x74(r1)
    lwz r14, 0x18(r1)
    lwz r15, 0x1c(r1)
    lwz r16, 0x20(r1)
    lwz r17, 0x24(r1)
    lwz r18, 0x28(r1)
    lwz r19, 0x2c(r1)
    lwz r20, 0x30(r1)
    lwz r21, 0x34(r1)
    b L_000ae148
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
L_000ae148:
.org 0xae14c
