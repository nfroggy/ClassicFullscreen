/* Execute both assembled runtime leaves in a disposable PPC process.
 * No live Classic access, input, or power-management calls. */
#include <mach/mach.h>
#include <mach/vm_attributes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int U;
static void check(int ok,const char *s) { if(!ok){fprintf(stderr,"FAIL: %s\n",s);exit(1);} }
static U pages[]={0x5e083000,0x5e084000,0x5e08d000,0x5e0a4000};
static U expected[4][1024];
static void before(void) { unsigned i;for(i=0;i<4;i++)memcpy(expected[i],(void*)pages[i],4096); }
static void after(void) { unsigned i;for(i=0;i<4;i++)check(!memcmp(expected[i],(void*)pages[i],4096),"unexpected memory write"); }
static void want(U address,U value) { unsigned i;for(i=0;i<4;i++)if(address>=pages[i]&&address<pages[i]+4096)expected[i][(address-pages[i])/4]=value; }
int main(int argc,char **argv) {
    vm_address_t code=0;FILE *f;U i,m,s,p,g,h,checks=0;
    U *mail=(U*)0x5e0a4500,*pending=(U*)0x5e084538,*phase=(U*)0x5e08db9c,*scheduler=(U*)0x5e0837bc;
    U sequences[]={0,1,0x7fffffff,0xffffffff};
    check(argc==2,"Sleep.bin argument");
    for(i=0;i<4;i++){vm_address_t a=pages[i];check(!vm_allocate(mach_task_self(),&a,4096,0),"private state page");memset((void*)a,0xa5,4096);}
    check(!vm_allocate(mach_task_self(),&code,4096,1),"private code page");
    f=fopen(argv[1],"rb");check(f!=NULL,"open payload");
    check(fread((void*)code,1,0x180,f)==0x180&&fgetc(f)==EOF,"exact payload size");fclose(f);
    vm_machine_attribute_val_t attr=MATTR_VAL_CACHE_SYNC;
    check(!vm_machine_attribute(mach_task_self(),code,0x180,MATTR_CACHE,&attr),"PowerPC instruction cache sync");
    check(!vm_protect(mach_task_self(),code,4096,0,VM_PROT_READ|VM_PROT_EXECUTE),"RX code");
    for(m=0;m<3;m++)for(s=0;s<4;s++)for(p=0;p<2;p++)for(g=0;g<2;g++)for(h=0;h<3;h++) {
        mail[0]=m==0?0:m==1?'ClSw':'ClSl';mail[1]=sequences[s];mail[2]=mail[1]-p;
        mail[3]=0x12345678;mail[4]=g;mail[5]=123;mail[6]=456;mail[7]=0xaabbccdd;
        *pending=h==1?1:0;*phase=h==2?1:0;before();
        if(m==2&&!p&&!g&&!h){want(0x5e0a4504,mail[1]+1);want(0x5e0a4518,123);}
        check(((int(*)(void))code)()==0,"normal Sleep return");after();
        check(((int(*)(void))code)()==0,"coalesced Sleep return");after();checks++;
    }
    for(m=0;m<2;m++)for(s=0;s<3;s++)for(p=0;p<3;p++)for(g=0;g<2;g++)for(h=0;h<2;h++) {
        *scheduler=s==0?0:s==1?0x80:0x8000;*pending=p==0?0:p==1?1:0xffffffff;
        mail[4]=g;mail[5]=h?0xffffffff:345;
        U result=m?(*pending!=0):(*scheduler==0x80);before();
        if(m&&result)want(0x5e0837bc,0x80);
        if(result&&!g){want(0x5e0a4510,1);want(0x5e0a4514,mail[5]+1);}
        check(((U(*)(U))(code+0x100))(m)==result,"stock BALForceSleep query/acknowledgment");after();checks++;
    }
    printf("PASS: %u exact PPC request/notification cases, cache synchronization, host/guest guards, coalescing, epoch/wraparound and write boundaries\n",checks);
    return 0;
}
