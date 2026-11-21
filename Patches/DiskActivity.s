/* File Manager completion vector ($03e6). A0 is the completed parameter
 * block and D0.w its result. Tiger's assembler has no 68k backend. Encode
 * the guest instructions as words and let the assembler resolve branches.
 * The controller fills the final JMP's operand before publishing the hook. */
.const
.align 2
.globl _CFDiskActivity, _CFDiskContinuation
_CFDiskActivity:
    .short 0x42e7                       /* move.w ccr,-(sp) */
    .short 0x48e7,0xe0c0                /* movem.l d0-d2/a0-a1,-(sp) */
    .short 0x4a40                       /* tst.w d0 */
    .short 0x6700,L_check-.             /* beq.w */
    .short 0x0c40,-39                   /* cmpi.w #eofErr,d0 */
    .short 0x6600,L_done-.              /* bne.w */
L_check:
    .short 0x3228,6                     /* move.w ioTrap(a0),d1 */
    .short 0x0241,0xf0ff                /* andi.w #$f0ff,d1 (strip trap flags) */
    .short 0x0c41,0xa002                /* cmpi.w #_Read,d1 */
    .short 0x6700,L_transfer-.
    .short 0x0c41,0xa003                /* cmpi.w #_Write,d1 */
    .short 0x6700,L_transfer-.
    .short 0x0c41,0x0051                /* FSDispatch ReadFork */
    .short 0x6700,L_transfer-.
    .short 0x0c41,0x0052                /* FSDispatch WriteFork */
    .short 0x6600,L_done-.
L_transfer:
    .short 0x4aa8,36                    /* tst.l ioReqCount(a0) */
    .short 0x6700,L_done-.
    .short 0x4aa8,40                    /* tst.l ioActCount(a0) */
    .short 0x6700,L_done-.
    .short 0x7003                       /* moveq #HDActivity,d0 */
    .short 0x4840,0x303c,0x0024,0xa09e  /* UpdateSystemActivity via _PowerMgrDispatch */
L_done:
    .short 0x4cdf,0x0307                /* movem.l (sp)+,d0-d2/a0-a1 */
    .short 0x44df                       /* move.w (sp)+,ccr */
    .short 0x4ef9                       /* jmp original.l */
_CFDiskContinuation:
    .long 0
