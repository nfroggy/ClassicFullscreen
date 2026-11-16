/* Read-only Tiger/OS 9 sleep diagnostic. Run as root: SleepTrace HOST_PID SECONDS.
 * Uses Mach reads only: no guest calls, input, suspension, or memory writes.
 * Field offsets are from the mini's OS 9 NativePowerMgrLib and Classic 1.9.
 * This is a diagnostic, not part of the application build. */
#include <mach/mach.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
typedef unsigned int U;
static task_t task;
static int readmem(U address, void *buffer, unsigned size) {
    vm_size_t got=0;
    return address && !vm_read_overwrite(task,address,size,(vm_address_t)buffer,&got) && got==size;
}
static U word(U address) { U v=0;readmem(address,&v,4);return v; }
static unsigned short half(U address) { unsigned short v=0;readmem(address,&v,2);return v; }
static unsigned char byte(U address) { unsigned char v=0;readmem(address,&v,1);return v; }
int main(int argc,char **argv) {
    int i,seconds; U pm,descriptor,vector,dispatch; char old[2048]="",row[2048];
    struct timeval now;
    if(argc!=3 || geteuid() || task_for_pid(mach_task_self(),atoi(argv[1]),&task)) return 1;
    seconds=atoi(argv[2]);if(seconds<1||seconds>600)return 2;
    pm=word(0xd18);descriptor=word(pm+0x396);vector=word(descriptor+20);dispatch=word(vector);
    printf("PM=%08x trap=%08x descriptor=%08x vector=%08x dispatch=%08x toc=%08x PEF_FILE_base=%08x\n",
           pm,word(0x628),descriptor,vector,dispatch,word(vector+4),dispatch-0x9bf8);
    printf("plugin=%08x callbacks=%08x/%08x/%08x/%08x/%08x/%08x\n",word(pm+0x382),
           word(word(pm+0x382)+0x40),word(word(pm+0x382)+0x48),word(word(pm+0x382)+0x4c),
           word(word(pm+0x382)+0x50),word(word(pm+0x382)+0x88),word(word(pm+0x382)+0x8c));
    printf("Sleep entry=%08x BALForceSleep=%08x\n", word(word(vector+4)+0x304),word(0x5e0823fc));
    for(i=0;i<seconds*50;i++) {
        U ctx;
        pm=word(0xd18);ctx=word(0x5e0a3530);
        sprintf(row,"pm=%08x enable=%u flags=%02x marker=%08x mp=%u phase=%u/%u result=%08x reason=%04x root=%08x state=%u/%u pendingReason=%04x busy=%u features=%08x/%08x queued=%08x bridge=%08x host=%08x/%08x gfx=%u/%u",
                pm,byte(pm+0xc),byte(pm+0x54),word(pm+0x112),byte(pm+0x2e7),
                byte(pm+0x2f0),byte(pm+0x2f1),word(pm+0x2f6),half(pm+0x2fa),word(pm+0x2fc),
                byte(pm+0x310),byte(pm+0x311),half(pm+0x312),byte(pm+0x314),
                word(pm+0x340),word(pm+0x344),word(pm+0x464),word(pm+0x538),
                word(0x5e084538),word(0x5e08db9c),word(ctx+464),word(ctx+468));
        sprintf(row+strlen(row)," mail=%08x request=%u ack=%u result=%08x notifying=%u epoch=%u requestEpoch=%u",
                word(0x5e0a4500),word(0x5e0a4504),word(0x5e0a4508),word(0x5e0a450c),
                word(0x5e0a4510),word(0x5e0a4514),word(0x5e0a4518));
        if(strcmp(old,row)||i%50==0) {
            gettimeofday(&now,NULL);
            printf("%ld.%06ld tick=%08x %s\n",(long)now.tv_sec,(long)now.tv_usec,word(0x16a),row);
            fflush(stdout);strcpy(old,row);
        }
        usleep(20000);
    }
    mach_port_deallocate(mach_task_self(),task);return 0;
}
