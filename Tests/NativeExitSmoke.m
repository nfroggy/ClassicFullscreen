/* Disposable OS X windows for testing the fullscreen controller's exit policy.
 * Build on Tiger: gcc Tests/NativeExitSmoke.m -framework Cocoa -framework Carbon -o /tmp/native-exit-smoke
 * Run two copies with different title arguments. SIGUSR1 brings one forward;
 * SIGTERM quits through its event loop. Neither copy opens or saves documents.
 * --front reports the actual foreground PSN and Unix PID without guest metadata.
 */
#include <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern OSStatus CPSGetFrontProcess(ProcessSerialNumber *);
static volatile sig_atomic_t command;
static ProcessSerialNumber self;
static BOOL cocoa;
static void signalCommand(int number) { command = number; }
static void tick(EventLoopTimerRef timer, void *context) {
    int pending = command;
    (void)timer; (void)context;
    command = 0;
    if (pending == SIGUSR1) SetFrontProcess(&self);
    if (pending == SIGTERM) {
        if (cocoa) [NSApp terminate:nil];
        else QuitApplicationEventLoop();
    }
}
@interface SmokeTimer : NSObject
- (void)tick:(NSTimer *)timer;
@end
@implementation SmokeTimer
- (void)tick:(NSTimer *)timer { (void)timer; tick(NULL, NULL); }
@end
int main(int argc, char **argv) {
    WindowRef window;
    EventLoopTimerRef timer;
    Rect bounds = {150, 150, 350, 500};
    CFStringRef title;
    pid_t pid = -1;
    if (GetCurrentProcess(&self)) return 3;
    if (argc == 2 && !strcmp(argv[1], "--front")) {
        OSStatus status = CPSGetFrontProcess(&self);
        if (status) return 1;
        GetProcessPID(&self, &pid);
        printf("%08lx:%08lx %d\n", self.highLongOfPSN, self.lowLongOfPSN, (int)pid);
        return 0;
    }
    if (argc != 2) return 2;
    if (TransformProcessType(&self, kProcessTransformToForegroundApplication)) return 3;
    signal(SIGUSR1, signalCommand);
    signal(SIGTERM, signalCommand);
    cocoa = getenv("CLASSIC_TEST_COCOA") != NULL;
    if (cocoa) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(150, 350, 350, 200)
            styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
            backing:NSBackingStoreBuffered defer:NO];
        [w setTitle:[NSString stringWithUTF8String:argv[1]]];
        [w makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        SmokeTimer *handler = [[[SmokeTimer alloc] init] autorelease];
        [NSTimer scheduledTimerWithTimeInterval:0.05 target:handler selector:@selector(tick:)
            userInfo:nil repeats:YES];
        printf("%08lx:%08lx %d Cocoa\n", self.highLongOfPSN, self.lowLongOfPSN, (int)getpid());
        fflush(stdout);
        [NSApp run];
        [pool release];
        return 0;
    }
    if (CreateNewWindow(kDocumentWindowClass, kWindowStandardDocumentAttributes,
                        &bounds, &window)) return 3;
    title = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    SetWindowTitleWithCFString(window, title);
    CFRelease(title);
    InstallEventLoopTimer(GetMainEventLoop(), 0, 0.05,
                         NewEventLoopTimerUPP(tick), NULL, &timer);
    ShowWindow(window);
    SetFrontProcess(&self);
    printf("%08lx:%08lx %d\n", self.highLongOfPSN, self.lowLongOfPSN, (int)getpid());
    fflush(stdout);
    RunApplicationEventLoop();
    DisposeWindow(window);
    return 0;
}
