#import "CFClassic.h"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

@interface CFPower (Notifications)
- (void)message:(natural_t)message argument:(void *)argument;
@end
static void powerChanged(void *context, io_service_t service, natural_t message, void *argument) {
    (void)service;
    [(CFPower *)context message:message argument:argument];
}
@implementation CFPower
- (id)init {
    if ((self = [super init])) {
        IONotificationPortRef port = NULL;
        powerConnection = IORegisterForSystemPower(self, &port, powerChanged, &powerNotifier);
        notificationPort = port;
        if (!powerConnection || !port) {
            [self release];
            return nil;
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(port),
                           kCFRunLoopDefaultMode);
    }
    return self;
}
- (void)dealloc {
    if (notificationPort)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
            IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopDefaultMode);
    if (powerNotifier)
        IODeregisterForSystemPower(&powerNotifier);
    if (powerConnection)
        IOServiceClose(powerConnection);
    if (notificationPort)
        IONotificationPortDestroy(notificationPort);
    [super dealloc];
}
- (void)message:(natural_t)message argument:(void *)argument {
    if (message == kIOMessageCanSystemSleep || message == kIOMessageSystemWillSleep) {
        if (message == kIOMessageSystemWillSleep) {
            willSleep = YES;
            CFSLog(@"Power: system will sleep");
        }
        /* Classic has its own independent notification client. Do not call
         * its guest Power Manager here or wait for it before acknowledging. */
        IOAllowPowerChange(powerConnection, (long)argument);
    } else if (message == kIOMessageSystemHasPoweredOn) {
        woke = YES;
        willSleep = NO;
        CFSLog(@"Power: system has powered on");
    } else if (message == kIOMessageSystemWillNotSleep) {
        canceled = YES;
        willSleep = NO;
        CFSLog(@"Power: system canceled sleep");
    }
}
- (void)drain {
    while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true) == kCFRunLoopRunHandledSource) {}
}
- (IOReturn)sleepWithTask:(task_t)task pid:(pid_t)pid {
    [self drain];
    BOOL guestNotifying = CFWord(task, CF_SLEEP_MAIL + 16) != 0;
    BOOL changedCycle = CFWord(task, CF_SLEEP_MAIL + 20) != CFWord(task, CF_SLEEP_MAIL + 24);
    BOOL hostPending = CFWord(task, 0x5e084538) != 0 || CFWord(task, 0x5e08db9c) != 0;
    if (willSleep || guestNotifying || changedCycle || hostPending) {
        /* A lid/native sleep overtook the queued guest request. Join that
         * cycle, including one which already finished while we were asleep.
         * Never let its stale request immediately put the Mac back to sleep. */
        CFSLog(@"Power: guest request coalesced with host sleep");
        if (!willSleep && !guestNotifying && !hostPending)
            return kIOReturnSuccess;
    } else {
        woke = canceled = NO;
        io_connect_t connection = IOPMFindPowerManagement(MACH_PORT_NULL);
        if (!connection)
            return kIOReturnNotReady;
        CFSLog(@"Power: requesting system sleep from guest Power Manager (desktop retained)");
        IOReturn result = IOPMSleepSystem(connection);
        IOServiceClose(connection);
        if (result != kIOReturnSuccess)
            return result;
    }
    double deadline = CFMonotonicTime() + 45;
    BOOL observedWake = NO;
    while (!CFInterrupted && CFTaskAlive(task, pid)) {
        /* Run notifications before checking deadlines: the computer may have
         * spent hours asleep. No display/guest RPC is made during this wait. */
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        [self drain];
        if (woke && !observedWake) {
            /* The guest finishes wake callbacks independently of our IOKit
             * notification. Give those callbacks a fresh, bounded interval
             * even when hours elapsed while the hardware was asleep. */
            observedWake = YES;
            deadline = CFMonotonicTime() + 10;
        }
        if (woke && !CFWord(task, CF_SLEEP_MAIL + 16) && !CFWord(task, 0x5e08db9c))
            return kIOReturnSuccess;
        if (canceled)
            return kIOReturnAborted;
        if (!willSleep && CFMonotonicTime() >= deadline)
            return kIOReturnTimeout;
    }
    return kIOReturnAborted;
}
@end
