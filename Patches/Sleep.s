/* Position-independent runtime leaves. Loaded into Classic before publishing
 * either entry pointer. No ROM or Power Manager instructions are rewritten.
 * 0: CFM Sleep entry; 0x100: BALForceSleep host dispatch entry.
 * Mailbox at 5e0a4500: magic, request, completion, result, guest-notifying,
 * host-cycle generation, request-generation, reserved. */
.text
L_request:
    lis r11, 0x5e0a
    ori r11, r11, 0x4500
    lwz r0, 0(r11)
    lis r12, 0x436c
    ori r12, r12, 0x536c
    cmpw r0, r12
    bne L_done
    lwz r0, 16(r11)
    cmpwi r0, 0
    bne L_done
    lis r12, 0x5e08
    lwz r0, 0x4538(r12)
    cmpwi r0, 0
    bne L_done
    lis r12, 0x5e09
    lwz r0, -0x2464(r12)
    cmpwi r0, 0
    bne L_done
    addi r10, r11, 4
L_retry:
    lwarx r3, 0, r10
    lwz r0, 8(r11)
    cmpw r3, r0
    bne L_done
    lwz r0, 20(r11)
    stw r0, 24(r11)
    addi r3, r3, 1
    sync
    stwcx. r3, 0, r10
    bne L_retry
L_done:
    li r3, 0
    blr
.org 0x100
/* Reproduce stock BALForceSleep's query/acknowledge semantics. Its only
 * callers are clkint's two sleep paths. Mark notification ownership before
 * either can enter an application's SleepQ callback. The guest clears it
 * after sleepWakeUp callbacks, including those delivered after the host's
 * SystemHasPoweredOn notification has already returned. */
L_bal:
    cmpwi r3, 0
    bne L_ack
    lis r12, 0x5e08
    lwz r0, 0x37bc(r12)
    cmpwi r0, 0x80
    bne L_zero
    b L_notify
L_ack:
    lis r12, 0x5e08
    lwz r0, 0x4538(r12)
    cmpwi r0, 0
    beq L_zero
    li r0, 0x80
    stw r0, 0x37bc(r12)
L_notify:
    lis r12, 0x5e0a
    lwz r0, 0x4510(r12)
    cmpwi r0, 0
    bne L_one
    lwz r3, 0x4514(r12)
    addi r3, r3, 1
    stw r3, 0x4514(r12)
    li r0, 1
    stw r0, 0x4510(r12)
    sync
L_one:
    li r3, 1
    blr
L_zero:
    li r3, 0
    blr
.org 0x180
