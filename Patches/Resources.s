/* Classic resource edits, at resource-FORK file offsets.
 * These application/INIT records and the 68K branch opcode are data to the
 * PowerPC assembler. The native build generates their payload/image checksums. */
.text
/* disl1 entry 49: allow the Control Strip control panel. */
.org 0x3070d
    .long 0
/* Allow real Finder launch. */
.org 0x309fb
    .long 0
/* disl1 entry 75: allow the Control Strip background application. */
.org 0x30c21
    .long 0
/* ftsk1 entry 44: allow the Control Strip extension INIT. */
.org 0x36503
    .long 0
/* 68K resource: change BEQ.s to BRA.s, retaining the existing displacement. */
.org 0x52734
    .byte 0x60
.org 0x52739
