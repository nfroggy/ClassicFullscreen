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
/* Panel/digital variant of the Display Manager in gpch 144. At the start
 * of its per-device loop, clear low-memory NTSC and take the existing path
 * that clears QuickDraw's roundedDevice flag. OS 9 draws both the desktop
 * region and the themed menu bar from those values. */
.org 0x60098
    .short 0x4238, 0x0b3e              /* clr.b NTSC.w */
    .short 0x6018                      /* bra.s $600b6 (square-device path) */
