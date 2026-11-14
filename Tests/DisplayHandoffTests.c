/* Exact installed PPC code, isolated in this disposable test process. No
 * display or live Classic access. Exercise writes between SetMode and End,
 * deferred ownership, duplicate End, failures and cache-address refreshes. */
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int U;
static U ctx[140],display[33],length,*trace=(U*)0x5e0a4400;
static unsigned char *screen,*expected,*owned;
static int fail_alloc,fail_hide,fail_get,null_get,hidden,shows,frees,allocs,refreshing,copies;
static void check(int ok,const char *s){if(!ok){fprintf(stderr,"FAIL %s\n",s);exit(1);}}
static void *allocate(U n){check(n==length&&!owned,"only one private allocation");allocs++;return fail_alloc?0:(owned=malloc(n));}
static void release(void *p){check(p==owned&&p!=screen&&owned,"free owned RAM only");check(ctx[117]==1,"pending protects deferred release");frees++;free(p);owned=0;}
static void *copy(void *d,const void *s,U n){check(hidden==1&&n==length&&ctx[117]==1,"copy protected full image before End clears pending");copies++;return memcpy(d,s,n);}
static int hide(int c){check(c==123&&!hidden,"hide once");if(fail_hide)return 77;hidden=1;return 0;}
static int show(int c){check(c==123&&hidden==1,"show balances hide");hidden=0;shows++;return 0;}
static int base(U id,void **p){check(id==1&&(hidden==1||refreshing),"protected handoff query");*p=null_get?0:screen;return fail_get?88:0;}
static void map(U a,U n){vm_address_t p=a;check(vm_allocate(mach_task_self(),&p,n,0)==0&&p==a,"unused private mapping");}
static void stub(U where,void *fn){U *p=(U*)where,v=(U)fn;p[0]=0x3d800000|(v>>16);p[1]=0x618c0000|(v&65535);p[2]=0x7d8903a6;p[3]=0x4e800420;}
extern void sys_icache_invalidate(void *,unsigned long);
static int invoke(U away){
 int r;void *address=0;ctx[116]=away;ctx[117]=1;trace[4]++;
 r=((int(*)(U*,U*))0x5e003100)(ctx,display);
 if(!r){
  refreshing=1;
  check(((int(*)(U,void**))0x5e003394)(display[0],&address)==0,"post-SetMode cache query");
  refreshing=0;display[2]=(U)address;
  check(address==(away?(void*)owned:(void*)screen),"cache preserves private address");
 }
 return r;
}
static void end(void){
 trace[5]++;
 ((void(*)(U*))0x5e0562a0)(ctx);
 check(ctx[117]==0&&trace[2]==0&&!hidden,"End clears pending and invalidates consumed source");
}
int main(int argc,char **argv){
 U modes[][2]={{640,480},{800,600},{1024,768},{1280,720},{1920,1080},{1920,1200},{3840,2160}};
 FILE *f;U mode,width,height,stride,k,depth,i,descriptors;int result,prior_copies,prior_frees;
 check(argc==2,"test image argument");
 map(0x5e002000,0x80000);map(0x5e0a3000,0x2000);
 f=fopen(argv[1],"rb");check(f!=0,"open payload");check(fread((void*)0x5e002000,1,0x80000,f)==0x80000,"host code region size");fclose(f);
 *(U*)0x5e0a3530=(U)ctx;
 stub(0x5e07c50c,allocate);stub(0x5e07c5fc,release);stub(0x5e07c49c,copy);stub(0x5e07e9cc,hide);stub(0x5e07e73c,show);stub(0x5e07ea9c,base);
 sys_icache_invalidate((void*)0x5e002000,0x80000);
 for(mode=0;mode<7;mode++){width=modes[mode][0];height=modes[mode][1];
 for(depth=8;depth<=32;depth*=2){
  stride=(width*(depth/8)+255)&~255;length=stride*height;screen=malloc(length);expected=malloc(length);check(screen&&expected,"test buffers");
  for(descriptors=1;descriptors<=2;descriptors++)
  for(k=0;k<14;k++){
   
   memset(ctx,0,sizeof(ctx));memset(display,0,sizeof(display));memset(trace,0,44);
   *(U*)0x5e0a4e18=0;
   for(i=0;i<length;i++)expected[i]=(unsigned char)(i*17+i/1920);
   memcpy(screen,expected,length);ctx[0]=123;ctx[115]=1;ctx[5]=descriptors;ctx[4]=(U)display;
   display[0]=1;display[32]=k==13?0:1;display[2]=(U)screen;{float fw=width,fh=height;memcpy(display+5,&fw,4);memcpy(display+6,&fh,4);}display[7]=stride;display[8]=depth;
   fail_alloc=k==1;fail_hide=k==2;fail_get=null_get=hidden=shows=frees=allocs=copies=0;owned=0;
   if(k==7)((unsigned char*)ctx)[503]=1;
   if(k==8)display[5]=0;
   if(k==12){ctx[117]=1;end();check(copies==0&&frees==0,"End without SetMode is inert");}
   result=invoke(1);
   if(k==1||k==2||k==8||k==13){
    check(result!=0&&ctx[116]==0&&display[2]==(U)screen&&!owned&&!memcmp(screen,expected,length)&&!hidden,"away failure preserves physical buffer");
    prior_frees=frees;prior_copies=copies;end();check(frees==prior_frees&&copies==prior_copies,"failed End cannot free physical source");continue;
   }
   if(result||!owned)printf("mode=%u depth=%u case=%u result=%d size=%u h=%08x stride=%u\n",mode,depth,k,result,trace[7],display[6],display[7]);
   check(result==0&&owned&&display[2]==(U)owned&&trace[9]==(U)owned&&trace[10]==length&&!memcmp(owned,expected,length)&&!hidden,"away publishes owned image");
   /* Indexed reconfiguration can erase/recolor pixels while its palette is
    * reset. At 16/32 bits it paints valid new window-frame details after
    * SetMode: model those so a stale snapshot copy is a regression. */
   if(depth==8)memset(owned,0xff,length);
   else for(i=160;i<length;i+=stride){owned[i]^=0x63;expected[i]^=0x63;}
   prior_copies=copies;fail_hide=k==9;
   end();
   if(depth!=8)check(copies==prior_copies&&!memcmp(owned,expected,length),"direct-color away End preserves newly drawn window details without copying");
   else if(k==9){check(*(U*)0x5e0a4e18==77&&owned[0]==0xff,"End hide failure skips unsafe copy");memcpy(owned,expected,length);}
   else check(!memcmp(owned,expected,length),"End preserves original picture after guest clear");
   fail_hide=0;
   prior_copies=copies;prior_frees=frees;ctx[117]=1;end();check(copies==prior_copies&&frees==prior_frees,"duplicate End cannot copy or free stale source");
   memset(screen,0xa5,length);for(i=0;i<length;i+=101){owned[i]^=0x37;expected[i]^=0x37;}
   check(!memcmp(owned,expected,length),"guest draws in RAM while OS X overwrites display");
   fail_get=k==3;null_get=k==4;fail_hide=k==5;
   if(k==6)display[7]+=64;
   result=invoke(0);
   if(k>=3&&k<=6){
    check(result!=0&&ctx[116]==1&&display[2]==(U)owned&&trace[9]==(U)owned&&trace[10]==length&&!memcmp(owned,expected,length)&&frees==0&&!hidden,"failed return retains backing for retry");
    end();check(owned&&frees==0,"failed return End preserves owned RAM");
    fail_get=null_get=fail_hide=0;display[7]=stride;result=invoke(0);
   }
   check(result==0&&ctx[116]==0&&display[2]==(U)screen&&owned&&trace[9]==0&&trace[10]==0&&frees==0&&!hidden&&!memcmp(screen,expected,length),"successful return retains source until End");
   if(depth==8)memset(screen,0xee,length);
   else for(i=164;i<length;i+=stride){screen[i]^=0x59;expected[i]^=0x59;}
   prior_copies=copies;fail_hide=k==10;end();
   if(depth!=8)check(copies==prior_copies&&!memcmp(screen,expected,length),"direct-color return End preserves freshly painted active title bar");
   else if(k==10)check(*(U*)0x5e0a4e18==77&&screen[0]==0xee,"return hide failure avoids copy and leak");
   else check(!memcmp(screen,expected,length),"return End repairs guest clear without losing away updates");
   check(!owned&&frees==1,"End frees returned RAM exactly once");
   prior_copies=copies;ctx[117]=1;end();check(frees==1&&copies==prior_copies,"duplicate return End cannot double-free or copy freed RAM");
   check(((unsigned char*)ctx)[503]==(k==7),"preserve existing flush suspension");
   if(k==11){
    fail_hide=0;check(invoke(1)==0,"next switch after extra Ends");end();check(invoke(0)==0,"second return");end();check(!owned&&frees==2,"End counts need not match SetMode counts");
   }
  }
  free(screen);free(expected);
 }
 }
 puts("PASS: 588 exact-PPC pixel-retention scenarios with one/two enumerated displays, inactive-target rejection, across seven resolutions at 8/16/32 bits: indexed guest clears, direct-color redraw preservation, native overwrite, away drawing, deferred ownership, failed handoffs, hide failure, retries and duplicate End.");return 0;
}
