/* Execute DeleteAppFromApplicationMenu from the assembled guest on PowerPC.
 * The list/menu service mocks are private; no live Classic process is used.
 * In particular, a native app can become background-only after insertion. */
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int U;
#define BASE 0x30000000U
static unsigned char toc_store[0x4000], system_entry[0x400], entries[4][0x400];
static unsigned char *toc = toc_store + 0x800;
static U bluebox, restored_toc;
static int delete_calls, decrement_calls, paste_calls, expected_index;
static void *dying;
static U *word(void *p, int off) { return (U *)((char *)p + off); }
static void check(int ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static int linked(void *p) {
    U current = *word(system_entry, 0x38); int bound = 0;
    while (current && bound++ < 8) {
        if (current == (U)p) return 1;
        current = *word((void *)current, 0x38);
    }
    check(bound < 8, "bounded list"); return 0;
}
static void delete_item(U menu, short index) {
    check(menu == 0x12345678 && index == expected_index, "matching menu and item");
    check(!linked(dying), "unlink before menu-service callback");
    check(!delete_calls++ && !decrement_calls && !paste_calls, "delete called once, first");
}
static void decrement(short index) {
    check(index == expected_index && delete_calls == 1 && !decrement_calls++ && !paste_calls,
          "external menu indexes updated after deletion");
}
static void pasteboard(void) {
    check(delete_calls == 1 && decrement_calls == 1 && !paste_calls++, "pasteboard ordering");
}
static void put(U off, U value) { *(U *)(BASE + off) = value; }
static void stub(U off, void *function, int cfm) {
    U target = (U)function;
    if (cfm) { put(off,0x90410014); put(off+4,0x3c40dead); off+=8; }
    else {
        put(off,0x7c0802a6); put(off+4,0x90010008); put(off+8,0x9421ffc0);
        put(off+12,0x90410038); off+=16;
    }
    put(off,0x3d800000|(target>>16)); put(off+4,0x618c0000|(target&65535));
    put(off+8,0x7d8903a6);
    if(cfm) put(off+12,0x4e800420);
    else {
        put(off+12,0x4e800421); put(off+16,0x80410038); put(off+20,0x38210040);
        put(off+24,0x80010008); put(off+28,0x7c0803a6); put(off+32,0x4e800020);
    }
}
extern void sys_icache_invalidate(void *, unsigned long);
extern void runMenuDelete(void *, void *, U *);
__asm__(".text\n.align 2\n_runMenuDelete:\n"
        "mflr r0\n stw r0,8(r1)\n stwu r1,-64(r1)\n"
        "stw r2,56(r1)\n stw r5,60(r1)\n mr r2,r4\n"
        "lis r12,0x3003\n ori r12,r12,0xa624\n mtctr r12\n bctrl\n"
        "lwz r5,60(r1)\n stw r2,0(r5)\n lwz r2,56(r1)\n"
        "addi r1,r1,64\n lwz r0,8(r1)\n mtlr r0\n blr\n");
int main(int argc, char **argv) {
    vm_address_t address = BASE; FILE *f;
    int native, background, position, enabled, dirty, i, cases = 0;
    check(argc == 2, "patched guest image required");
    check(!vm_allocate(mach_task_self(), &address, 0x50000, 0) && address == BASE, "private image");
    f=fopen(argv[1],"rb"); check(f != NULL, "open guest");
    check(fread((void *)BASE,1,0x50000,f)==0x50000,"read guest"); fclose(f);
    stub(0x4dce4,delete_item,1); stub(0x3b63c,decrement,0); stub(0x41368,pasteboard,0);
    sys_icache_invalidate((void *)BASE,0x50000);
    *word(toc,-0x2d8)=(U)system_entry; *word(toc,0x29d4)=0x12345678;
    *word(toc,-0x30c)=(U)&bluebox;
    for(native=0;native<2;native++) for(background=0;background<2;background++)
    for(position=0;position<4;position++) for(enabled=0;enabled<2;enabled++) for(dirty=0;dirty<2;dirty++) {
        int removes=(native||!background)&&position<3;
        memset(entries,0,sizeof(entries)); memset(system_entry,0,sizeof(system_entry));
        *word(system_entry,0x38)=(U)entries[0];
        for(i=0;i<2;i++) *word(entries[i],0x38)=(U)entries[i+1];
        dying=entries[position]; expected_index=5+position;
        *word(dying,0x3c)=(native?0x01000000:0)|(background?0x400:0)|0x58c0;
        ((unsigned char *)dying)[0x3e7]=dirty;
        /* A stale layer must never be examined by this cleanup. */
        *word(dying,0x70)=0xdead0000;
        bluebox=enabled?0x01000000:0; restored_toc=0;
        delete_calls=decrement_calls=paste_calls=0;
        runMenuDelete(dying,toc,&restored_toc);
        check(restored_toc==(U)toc,"CFM call restores Process Manager TOC");
        check(delete_calls==removes && decrement_calls==removes,"delete only a linked eligible process");
        check(paste_calls==(removes&&enabled&&dirty),"unchanged pasteboard cleanup");
        check(((unsigned char *)dying)[0x3e7]==(removes&&enabled?0:dirty),"pasteboard dirty flag");
        for(i=0;i<4;i++) check(linked(entries[i])==(i<3&&!(removes&&i==position)),"remaining links intact");
        cases++;
    }
    /* Sensitivity: the original guard leaves a native background proxy linked. */
    put(0x3a63c,0x5484056a); put(0x3a640,0x28040000);
    put(0x3a644,0x41820008); put(0x3a648,0x480000e0);
    sys_icache_invalidate((void *)(BASE+0x3a63c),16);
    memset(entries,0,sizeof(entries)); *word(system_entry,0x38)=(U)entries[0];
    *word(entries[0],0x3c)=0x01015cc0; dying=entries[0];
    delete_calls=decrement_calls=paste_calls=0;
    runMenuDelete(dying,toc,&restored_toc);
    check(linked(dying)&&!delete_calls&&!decrement_calls,"original guard reproduces dangling menu entry");
    printf("PASS: %d exact-PPC cleanup cases; native background transition, absent entries, head/middle/tail, guest policy, menu/pasteboard ordering and TOC. Original guard reproduces the bug.\n",cases);
    return 0;
}
