#import "CFClassic.h"
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
static ProcessSerialNumber uiPSN;
static char displayState;
static EventHotKeyRef emergencyKey;
static BOOL announced, seenSession, startPending, restoreRequested, authorized;
static double startDeadline;
static BOOL sendRequest(NSString *name, char command) {
    int fd = open([[CF_RUN stringByAppendingPathComponent:name] fileSystemRepresentation],
                  O_WRONLY | O_NONBLOCK | O_NOFOLLOW);
    if (fd < 0)
        return NO;
    BOOL sent = write(fd, &command, 1) == 1;
    close(fd);
    return sent;
}
static void alert(NSString *message) {
    DialogRef dialog = NULL;
    OSStatus r = CreateStandardAlert(kAlertStopAlert, CFSTR("ClassicFullscreen"),
                                     (CFStringRef)message, NULL, &dialog);
    if (!r)
        RunStandardAlert(dialog, NULL, NULL);
}
static OSStatus repaint(void) {
    WindowRef window;
    Rect bounds, local;
    GrafPtr port;
    CGRect screen = CGDisplayBounds(CGMainDisplayID());
    SetRect(&bounds, (short)screen.origin.x, (short)screen.origin.y, (short)CGRectGetMaxX(screen),
            (short)CGRectGetMaxY(screen));
    OSStatus err =
        CreateNewWindow(kPlainWindowClass, kWindowNoShadowAttribute | kWindowIgnoreClicksAttribute,
                        &bounds, &window);
    if (err)
        return err;
    SetWindowGroup(window, GetWindowGroupOfClass(kOverlayWindowClass));
    err = SetWindowAlpha(window, 0.0f);
    if (!err) {
        GetPort(&port);
        SetPortWindowPort(window);
        GetWindowPortBounds(window, &local);
        EraseRect(&local);
        ShowWindow(window);
        QDFlushPortBuffer(GetWindowPort(window), NULL);
        SetPort(port);
    }
    DisposeWindow(window);
    return err;
}
static void authorizeGuardian(void) {
    AuthorizationRef authorization = NULL;
    FILE *communications = NULL;
    const char *path = [CFExecutable fileSystemRepresentation];
    AuthorizationItem item = {kAuthorizationRightExecute, (UInt32)strlen(path), (void *)path, 0};
    AuthorizationRights rights = {1, &item};
    OSStatus err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                       kAuthorizationFlagDefaults, &authorization);
    if (!err)
        err = AuthorizationCopyRights(authorization, &rights, kAuthorizationEmptyEnvironment,
                                      kAuthorizationFlagInteractionAllowed |
                                          kAuthorizationFlagExtendRights |
                                          kAuthorizationFlagPreAuthorize,
                                      NULL);
    char pid[32];
    snprintf(pid, sizeof(pid), "%d", getpid());
    char *arguments[] = {restoreRequested ? "--guardian-recover" : "--guardian", pid, NULL};
    if (!err)
        err = AuthorizationExecuteWithPrivileges(authorization, path, kAuthorizationFlagDefaults,
                                                 arguments, &communications);
    if (communications)
        fclose(communications);
    if (authorization)
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
    if (err) {
        if (err != errAuthorizationCanceled)
            alert([NSString
                stringWithFormat:@"Cannot start the session supervisor (authorization error %ld).",
                                 (long)err]);
        QuitApplicationEventLoop();
        return;
    }
    authorized = YES;
    startDeadline = CFMonotonicTime() + 120;
}
static pascal void tick(EventLoopTimerRef timer, void *context) {
    (void)timer;
    (void)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    @try {
        if (startPending) {
            startPending = NO;
            authorizeGuardian();
        }
        char value = CFReadState();
        if (value)
            seenSession = YES;
        if (value && !announced)
            announced = sendRequest(@"session.request", 'Y');
        if ((value == 'D' || value == 'd') && displayState != value) {
            OSStatus err = repaint();
            if (sendRequest(@"session.request", err ? 'E' : value))
                displayState = value;
        }
        if (value == 'C' || value == 'A' || value == 'P') {
            if (value != displayState &&
                !CPSSetProcessName(&uiPSN, value == 'C' ? "Finder (OS X)" : "Classic"))
                displayState = value;
        }
        if (value == 'Z') {
            NSString *result = [[[NSString alloc]
                initWithData:CFReadFile([CF_RUN stringByAppendingPathComponent:@"session.result"])
                    encoding:NSUTF8StringEncoding] autorelease];
            sendRequest(@"session.request", 'X');
            if ([result hasPrefix:@"1\n"])
                alert([result substringFromIndex:2]);
            QuitApplicationEventLoop();
        } else if (!value && seenSession)
            QuitApplicationEventLoop();
        else if (!value && CFMonotonicTime() > startDeadline) {
            alert(@"The session supervisor did not start. See /var/log/ClassicFullscreen.log for "
                  @"details.");
            QuitApplicationEventLoop();
        }
    } @catch (NSException *e) {
        alert([e reason]);
        QuitApplicationEventLoop();
    } @finally {
        [pool release];
    }
}
static pascal OSStatus eventHandler(EventHandlerCallRef next, EventRef event, void *data) {
    (void)next;
    (void)data;
    UInt32 cls = GetEventClass(event), kind = GetEventKind(event);
    if (cls == kEventClassKeyboard && kind == kEventHotKeyPressed) {
        EventHotKeyID id;
        if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(id),
                              NULL, &id) ||
            id.signature != 'ClSw' || id.id != 2)
            return eventNotHandledErr;
        sendRequest(@"session.emergency", 'K');
        return noErr;
    }
    if (cls == kEventClassCommand && kind == kEventCommandProcess) {
        HICommand c;
        if (GetEventParameter(event, kEventParamDirectObject, typeHICommand, NULL, sizeof(c), NULL,
                              &c))
            return eventNotHandledErr;
        switch (c.commandID) {
        case 'ClRe':
            sendRequest(@"session.request", 'R');
            return noErr;
        case 'ClOx':
            sendRequest(@"session.request", 'O');
            return noErr;
        case 'ClSt':
        case kHICommandQuit:
            if (!seenSession && !authorized)
                QuitApplicationEventLoop();
            else
                sendRequest(@"session.request", 'S');
            return noErr;
        }
    }
    return eventNotHandledErr;
}
int CFUI(BOOL authorize, BOOL recovery) {
    CFRequire(getuid() == CFUserID, @"Launch the app from your desktop account, without sudo.");
    CFRequireConsoleUser();
    if (authorize && [CFClassicPIDs() count]) {
        alert(@"Please stop Classic before starting or restoring a fullscreen session.");
        return 1;
    }
    signal(SIGPIPE, SIG_IGN);
    restoreRequested = recovery;
    startPending = authorize;
    startDeadline = CFMonotonicTime() + 120;
    CFRequire(GetCurrentProcess(&uiPSN) == 0, @"Cannot register native UI");
    ProcessInfoRec info;
    memset(&info, 0, sizeof(info));
    info.processInfoLength = sizeof(info);
    OSStatus err = GetProcessInformation(&uiPSN, &info);
    if (!err && (info.processMode & modeOnlyBackground))
        err = TransformProcessType(&uiPSN, kProcessTransformToForegroundApplication);
    if (!err)
        err = CPSSetProcessName(&uiPSN, "Classic");
    CFRequire(err == 0, @"Cannot prepare native UI");
    MenuRef menu;
    CFRequire(CreateNewMenu(128, 0, &menu) == 0, @"Cannot create session menu");
    SetMenuTitleWithCFString(menu, CFSTR("Desktop"));
    AppendMenuItemTextWithCFString(menu, CFSTR("Return to Classic"), 0, 'ClRe', NULL);
    AppendMenuItemTextWithCFString(menu, CFSTR("Switch to Finder (OS X)"), 0, 'ClOx', NULL);
    AppendMenuItemTextWithCFString(menu, CFSTR("Shut Down Classic..."), 0, 'ClSt', NULL);
    InsertMenu(menu, 0);
    DrawMenuBar();
    EventTypeSpec types[] = {{kEventClassKeyboard, kEventHotKeyPressed},
                             {kEventClassCommand, kEventCommandProcess}};
    EventHotKeyID key = {'ClSw', 2};
    EventLoopTimerRef timer = NULL;
    err = InstallEventHandler(GetApplicationEventTarget(), eventHandler, 2, types, NULL, NULL);
    if (!err)
        err = RegisterEventHotKey(111, cmdKey | optionKey | controlKey, key,
                                  GetApplicationEventTarget(), 0, &emergencyKey);
    if (!err)
        err = InstallEventLoopTimer(GetMainEventLoop(), 0.1, 0.1, tick, NULL, &timer);
    if (err) {
        alert(
            @"Cannot register the emergency shortcut. Another fullscreen session may be running.");
        return 1;
    }
    RunApplicationEventLoop();
    if (timer)
        RemoveEventLoopTimer(timer);
    if (emergencyKey)
        UnregisterEventHotKey(emergencyKey);
    return 0;
}
