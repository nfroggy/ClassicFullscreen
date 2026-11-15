/* Execute Finder's real icon serializer and containing-folder predicate in a
 * private PPC process. No live Finder or filesystem changes. */
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned U;
static unsigned char object[0x220], parent[0x220], pb[0x100];
static int missing, checks;
static void check(int ok, const char *s) {
    checks++;
    if (!ok) { fprintf(stderr,"FAIL: %s\n",s); exit(1); }
}
static void get_parent(void **out, void *item) {
    check(item == object, "parent of correct item"); *out = missing ? NULL : parent;
}
static void copy_ref(void **out, void **in) { *out = *in; }
static void release_ref(void **ref, U zero) { (void)ref; check(!zero,"release mode"); }
static int property(void *item, U prop) {
    check(item == object && prop == 0xbe0, "label property"); return 5;
}
static void stub(U off, void *fn) {
    U *p = (U *)(0x30000000 + off), v = (U)fn;
    p[0]=0x3d800000|(v>>16); p[1]=0x618c0000|(v&65535);
    p[2]=0x7d8903a6; p[3]=0x4e800420;
}
extern void sys_icache_invalidate(void *,unsigned long);
int main(int argc,char **argv) {
    FILE *f; vm_address_t a=0x30000000; unsigned access, initial, kind;
    int (*allowed)(void *)=(void *)0x3005bad8;
    void (*serialize)(void *,void *)=(void *)0x3005bc1c;
    check(argc==2,"Finder image argument");
    check(!vm_allocate(mach_task_self(),&a,0x190000,0)&&a==0x30000000,"private mapping");
    f=fopen(argv[1],"rb"); check(f!=NULL,"open image");
    check(fread((void *)a,1,0x190000,f)==0x190000,"complete code"); fclose(f);
    check(*(U *)0x3005bb28==0x5400f7ff,"reviewed no-write test");
    stub(0x5b740,get_parent); stub(0x168bc,copy_ref); stub(0x17a54,release_ref);
    stub(0x25e94,property); sys_icache_invalidate((void *)a,0x190000);
    for(access=0;access<256;access++) for(missing=0;missing<2;missing++) {
        memset(parent,0,sizeof(parent)); parent[0x1a9]=access;
        check(allowed(object)==(!missing&&!(access&4)),"permission, not ownership; missing parent denied");
        for(initial=0;initial<2;initial++) for(kind=0;kind<2;kind++) {
            U old=0x00330044, position=0x00a100b7;
            int save_position=!initial||(!missing&&!(access&4));
            memset(object,0,sizeof(object)); memset(pb,0,sizeof(pb));
            *(U *)(object+0x34)=position; object[0x1a8]=kind?0x10:0;
            object[0x1a9]=0x80; /* item's own owner differs, including directories */
            *(short *)(object+0x1a6)=17; object[0x188]=1;
            *(U *)(object+0x18c)=0x12345678;
            pb[0x28]=initial; *(U *)(pb+0x2a)=old;
            serialize(object,pb);
            check(*(U *)(pb+0x2a)==(save_position?position:old),"file/folder icon position serialized");
            check(pb[0x28]==1&&(pb[0x29]&14)==10,"initialization and label serialized");
            check(*(short *)(pb+0x5e)==17,"extended Finder information serialized");
            check(*(U *)(pb+0x4c)==0x12345678&&!object[0x188],"pending modified date preserved");
        }
    }
    /* Sensitivity: the old instruction rejects a writable, root-owned parent. */
    *(U *)0x3005bb28=0x5400cfff; sys_icache_invalidate((void *)0x3005bb28,4);
    missing=0; parent[0x1a9]=0x80; check(!allowed(object),"old ownership check reproduces rejection");
    printf("PASS: %d exact-PPC Finder icon/metadata checks, both kinds and all permission bytes.\n",checks);
    return 0;
}
