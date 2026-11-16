/* Exercise the shipping CFPower class with a real CFRunLoop and fake IOKit
 * entry points. This executable never links IOKit or requests real sleep.
 * gcc -O2 -Wall -Wextra -fobjc-exceptions -ISources Tests/PowerTests.m \
 *     Sources/Power.m -framework Foundation -framework Carbon -o PowerTests
 */
#import "CFClassic.h"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static IOServiceInterestCallback callback;
static void *context;
static CFRunLoopSourceRef source;
static natural_t messages[4];
static int mode,remaining,position,requests,acks,connections,disposed,aliveCalls;
volatile sig_atomic_t CFInterrupted=0;
uint32_t CFWord(task_t task,uint32_t address) {
    (void)task;
    if ((mode==9||mode==10) && address==CF_SLEEP_MAIL+16) return position>=2 && aliveCalls<3;
    return (mode==8||mode==10) && address==CF_SLEEP_MAIL+20 ? 1 : 0;
}
static void requireTest(BOOL ok,const char *why) { if(!ok){fprintf(stderr,"FAIL: %s\n",why);exit(1);} }
void CFSLog(NSString *format,...) { (void)format; }
BOOL CFTaskAlive(task_t task,pid_t pid) {
    requireTest(task==123&&pid==456,"task identity preserved");
    aliveCalls++; return mode!=6 || aliveCalls<3;
}
double CFMonotonicTime(void) { static double now=0;now+=(mode==9||mode==10)?1:50;return now; }
static void deliver(void *unused) {
    (void)unused;
    if(position<remaining)callback(context,0,messages[position++],(void*)321);
    if(position<remaining)CFRunLoopSourceSignal(source);
}
io_connect_t IORegisterForSystemPower(void *ref,IONotificationPortRef *port,
                                    IOServiceInterestCallback cb,io_object_t *notifier) {
    if(mode==7)return 0;
    CFRunLoopSourceContext c;memset(&c,0,sizeof(c));c.perform=deliver;
    source=CFRunLoopSourceCreate(NULL,0,&c);
    callback=cb;context=ref;*notifier=17;*port=(IONotificationPortRef)source;
    if(mode==10){messages[remaining++]=kIOMessageSystemWillSleep;
        messages[remaining++]=kIOMessageSystemHasPoweredOn;CFRunLoopSourceSignal(source);}
    return 19;
}
CFRunLoopSourceRef IONotificationPortGetRunLoopSource(IONotificationPortRef port) {
    requireTest(port==(IONotificationPortRef)source,"notification port");return source;
}
void IONotificationPortDestroy(IONotificationPortRef port) {
    requireTest(port==(IONotificationPortRef)source,"destroy notification port");
    CFRelease(source);source=NULL;disposed++;
}
IOReturn IODeregisterForSystemPower(io_object_t *notifier) {
    requireTest(*notifier==17,"deregister notifier");*notifier=0;disposed++;return 0;
}
IOReturn IOServiceClose(io_connect_t connection) {
    requireTest(connection==19||connection==23,"close known connection");
    connections++;return 0;
}
io_connect_t IOPMFindPowerManagement(mach_port_t port) {
    requireTest(port==MACH_PORT_NULL,"default power domain");return mode==2?0:23;
}
IOReturn IOAllowPowerChange(io_connect_t connection,long identifier) {
    requireTest(connection==19&&identifier==321,"acknowledge actual notification");acks++;return 0;
}
IOReturn IOPMSleepSystem(io_connect_t connection) {
    requireTest(connection==23,"sleep through request connection");requests++;
    if(mode==1)return kIOReturnNotPermitted;
    if(mode==3)return 0; /* Accepted, but no transition: bounded timeout. */
    messages[remaining++]=kIOMessageSystemWillSleep;
    if(mode==4)messages[remaining++]=kIOMessageSystemWillNotSleep;
    else if(mode!=6)messages[remaining++]=kIOMessageSystemHasPoweredOn;
    if(mode==5)CFInterrupted=SIGTERM;
    CFRunLoopSourceSignal(source);return 0;
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];int test;
    for(test=0;test<11;test++) {
        mode=test;remaining=position=requests=acks=connections=disposed=aliveCalls=0;
        CFInterrupted=0;CFPower *power=[[CFPower alloc] init];
        if(mode==7)requireTest(!power&&!source,"registration failure disables bridge");
        else {
            requireTest(power!=nil,"registered notifier");
            IOReturn result=[power sleepWithTask:123 pid:456];
            IOReturn expected=(mode==0||mode==8||mode==9||mode==10)?0:mode==1?kIOReturnNotPermitted:
                mode==2?kIOReturnNotReady:mode==3?kIOReturnTimeout:kIOReturnAborted;
            requireTest(result==expected,"wake/failure/interruption result");
            requireTest(requests==((mode==2||mode==8||mode==10)?0:1),"request submitted exactly once");
            requireTest(acks==((mode==0||mode==4||mode==6||mode==9||mode==10)?1:0),"system-will-sleep acknowledged once");
            [power release];
            requireTest(!source&&disposed==2&&connections==((mode==2||mode==8||mode==10)?1:2),"all resources released");
        }
    }
    puts("PASS: power bridge wake, denied request, unavailable service, missing transition, canceled sleep, interruption, guest exit, registration failure overtaking host sleep and delayed guest wake callbacks");
    [pool release];return 0;
}
