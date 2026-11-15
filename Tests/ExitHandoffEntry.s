# Isolated native test entry; emulates the existing ExitToShell stack frame.
.text
.org 0x2f670
L_early:
.org 0x2f6e0
L_late:
.org 0x2f91c
L_ipc_entry:
.org 0x2f924
L_selection:
.org 0x51000
L_test_entry:
    mflr r0
    stw r0,8(r1)
    stwu r1,-0x150(r1)
    stw r2,0x140(r1)
    stw r30,0x144(r1)
    mr r30,r3
    mr r2,r4
    lwz r3,0(r30)
    stw r3,0x3c(r1)
    lwz r3,4(r30)
    stb r3,0x54(r1)
    lwz r3,8(r30)
    sth r3,0x40(r1)
    li r3,0
    stb r3,0x64(r1)
    stw r3,16(r30)
    b L_early
.org 0x51080
L_after_early:
    li r3,1
    stw r3,16(r30)
    lwz r4,0(r30)
    li r3,-1
    stw r3,0x24(r4)
    stw r3,0x28(r4)
    li r3,0
    stw r3,0x3c(r4)  /* saved kind must survive the freed process record */
    stw r3,0x3c(r1)
    lwz r3,12(r30)
    stw r3,0x48(r1)
    lwz r3,28(r30)
    cmpwi r3,1
    beq L_test_selection
    cmpwi r3,2
    beq L_test_ipc
    b L_late
L_test_selection:
    b L_selection
L_test_ipc:
    b L_ipc_entry
.org 0x51100
L_after_late:
    stw r12,20(r30)
    stw r2,24(r30)
    lwz r2,0x140(r1)
    lwz r30,0x144(r1)
    addi r1,r1,0x150
    lwz r0,8(r1)
    mtlr r0
    blr
