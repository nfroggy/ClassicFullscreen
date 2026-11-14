/* Execute the exact Finder catalog-read wrapper in this disposable PPC process.
 * All imports are mocked. No live process, filesystem or display is accessed.
 * Usage: gcc -O2 FinderCatalogTests.c -o test; ./test Finder.patched */
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int U;
static unsigned char pb[512];
static int volume_async,context_sync,extended,legacy_error,extended_error;
static int waits,prepares,syncs,asyncs,fixups,finishes,extensions,contexts,async_extension;
static void check(int ok,const char *s){if(!ok){fprintf(stderr,"FAIL: %s\n",s);exit(1);}}
static short *half(U n){return (short *)(pb+n);}
static U *word(U n){return (U *)(pb+n);}
static void wait_previous(void *p){check(p==pb,"wait PB identity");waits++;*half(0x10)=*half(0xa4)=0;}
static U supports(short volume){check(volume==-1,"volume preserved");return volume_async;}
static U context(void){contexts++;return context_sync;}
static void prepare(void *p){check(p==pb,"prepare PB identity");prepares++;}
static int read_sync(void *p){check(p==pb&&*half(0x10)<=0&&*half(0xa4)<=0,"sync after previous request");syncs++;*half(0x10)=legacy_error;return legacy_error;}
static int read_async(void *p){check(p==pb,"async PB identity");asyncs++;*half(0x10)=legacy_error;return legacy_error;}
static void fixup(void *p){check(p==pb&&syncs==1,"sync completion fixup");fixups++;}
static int finish(void *p,U zero){check(p==pb&&!zero,"finish PB/flag");finishes++;return *half(0x10);}
static U needs_extended(void *p){check(p==pb,"extended predicate PB");return extended;}
static int read_extended(void *p,U async){check(p==pb,"extended PB identity");extensions++;async_extension=async;return extended_error;}
static void map(U a,U n){vm_address_t p=a;check(!vm_allocate(mach_task_self(),&p,n,0)&&p==a,"private code mapping");}
static void stub(U off,void *fn){U *p=(U *)(0x30000000+off),v=(U)fn;p[0]=0x3d800000|(v>>16);p[1]=0x618c0000|(v&65535);p[2]=0x7d8903a6;p[3]=0x4e800420;}
extern void sys_icache_invalidate(void *,unsigned long);
static void reset(U k){
 memset(pb,0,sizeof(pb));*half(0x16)=-1;*word(0x30)=(k&16)?1:42;*word(0x8c)=42;
 *half(0x10)=(k&4)?1:0;*half(0xa4)=(k&8)?1:0;
 volume_async=k&1;context_sync=(k>>1)&1;extended=(k>>5)&1;
 legacy_error=(k&64)?-43:0;extended_error=(k&128)?-77:0;
 waits=prepares=syncs=asyncs=fixups=finishes=extensions=contexts=async_extension=0;
}
int main(int argc,char **argv){
 FILE *f;U k;int result;int(*invoke)(void *)=(void *)0x30019560;
 check(argc==2,"Finder fixture argument");map(0x30000000,0x190000);
 f=fopen(argv[1],"rb");check(f!=0,"open Finder");check(fread((void*)0x30000000,1,0x190000,f)==0x190000,"complete code region");fclose(f);
 check(*(U*)0x300195d8==0x48000014,"reviewed branch selects synchronous read and extended lookup");
 stub(0x16b138,wait_previous);stub(0x1086c,supports);stub(0x10930,context);stub(0x10954,prepare);
 stub(0x198a4,read_async);stub(0x198bc,read_sync);stub(0x1744e0,fixup);stub(0x198d4,finish);
 stub(0x19ad8,needs_extended);stub(0x16af8c,read_extended);
 sys_icache_invalidate((void*)0x30000000,0x190000);
 for(k=0;k<256;k++){
  reset(k);result=invoke(pb);
  check(result==(legacy_error?legacy_error:extended?extended_error:0),"original error/result propagation");
  check(waits==((k&12)!=0)&&prepares==1&&syncs==1&&!asyncs&&fixups==1&&finishes==1,"prior request, synchronous call, fixup, cleanup exactly once");
  check(!contexts&&extensions==(!legacy_error&&extended)&&!async_extension,"both catalog paths synchronous regardless of volume/context");
  check(*half(0x16)==-1,"volume preserved after call");
  if(k&16)check(*word(0x30)==2&&*word(0x8c)==2&&*half(0x1c)==-1,"root directory normalization preserved");
 }
 reset(0);*half(0x1c)=-1;*word(0x30)=0;
 check(invoke(pb)==-120&&!prepares&&!syncs&&!fixups&&!finishes,"invalid directory fails before I/O");
 /* Sensitivity: restoring the old branch really exercises the async route. */
 *(U*)0x300195d8=0x41820014;sys_icache_invalidate((void*)0x300195d8,4);
 reset(33);check(invoke(pb)==0&&asyncs==1&&!syncs&&!fixups&&contexts==1&&extensions==1&&async_extension==1,"original branch takes both asynchronous paths");
 puts("PASS: 256 exact-PPC Finder catalog cases, invalid-directory rejection, original async control; prior-request waits, sync completion/cleanup, extended lookup, normalization and error propagation.");return 0;
}
