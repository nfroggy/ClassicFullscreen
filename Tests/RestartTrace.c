/* Passive process/graphics trace for Special -> Restart. No input or writes. */
#include <Carbon/Carbon.h>
#include <mach/mach.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern OSStatus CPSGetFrontProcess(ProcessSerialNumber *);
typedef unsigned int U;
static task_t task;
static U word(U address) {
    U value = 0; vm_size_t got = 0;
    if (!address || vm_read_overwrite(task, address, 4, (vm_address_t)&value, &got) || got != 4) return 0;
    return value;
}
int main(int argc, char **argv) {
    int ticks, tick; U last = 0;
    if (argc != 3 || geteuid() || task_for_pid(mach_task_self(), atoi(argv[1]), &task)) return 1;
    ticks = atoi(argv[2]) * 4; if (ticks <= 0 || ticks > 1200) return 2;
    for (tick = 0; tick < ticks; tick++) {
        ProcessSerialNumber front = {0,0}, p = {0,kNoProcess};
        U ctx = word(0x5e0a3530), display = word(ctx+16), hash = 2166136261U;
        char rows[16384], *next = rows; struct timeval now;
        CPSGetFrontProcess(&front);
        next += sprintf(next, "front=%08lx ctx=%08x display=%08x base=%08x/%08x away=%u pending=%u count=%u mail=%08x/%u/%u\n",
                        front.lowLongOfPSN,ctx,display,word(display+8),word(0x824),word(ctx+464),word(ctx+468),
                        word(0x5e0a4400),word(0x5e0a4100),word(0x5e0a4104),word(0x5e0a4108));
        while (next-rows < 15000 && GetNextProcess(&p) == noErr) {
            ProcessInfoRec info; Str255 name; pid_t pid = -1;
            memset(&info,0,sizeof(info)); info.processInfoLength=sizeof(info);info.processName=name;name[0]=0;
            if (!GetProcessInformation(&p,&info)) {
                OSStatus status = GetProcessPID(&p,&pid);
                next += sprintf(next," %08lx pid=%d/%ld mode=%08lx creator=%08lx %.*s\n",
                                p.lowLongOfPSN,(int)pid,(long)status,info.processMode,info.processSignature,name[0],name+1);
            }
        }
        { char *c; for(c=rows;c<next;c++)hash=(hash^(unsigned char)*c)*16777619U; }
        if(hash!=last || tick%20==0) {
            gettimeofday(&now,NULL); printf("%ld.%06ld %s",(long)now.tv_sec,(long)now.tv_usec,rows);fflush(stdout);last=hash;
        }
        usleep(250000);
    }
    mach_port_deallocate(mach_task_self(),task);return 0;
}
