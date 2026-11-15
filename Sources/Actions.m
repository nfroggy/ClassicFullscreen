#import "CFClassic.h"
#include <unistd.h>
static BOOL samePSN(ProcessSerialNumber a, ProcessSerialNumber b) {
    Boolean same = false;
    return !SameProcess(&a, &b, &same) && same;
}
static int activate(ProcessSerialNumber p) {
    ProcessSerialNumber front = {0, 0};
    if (!GetFrontProcess(&front) && samePSN(p, front))
        return 0;
    OSStatus err = SetFrontProcess(&p);
    if (err) {
        CFSLog(@"SetFrontProcess %08lx:%08lx: %ld", p.highLongOfPSN, p.lowLongOfPSN, (long)err);
        return 1;
    }
    int i;
    for (i = 0; i < 50; i++) {
        if (!GetFrontProcess(&front) && samePSN(p, front))
            return 0;
        usleep(10000);
    }
    CFSLog(@"Activation acknowledgement timed out: requested %08lx:%08lx, front %08lx:%08lx",
           p.highLongOfPSN, p.lowLongOfPSN, front.highLongOfPSN, front.lowLongOfPSN);
    return 1;
}
static BOOL infoFor(ProcessSerialNumber p, ProcessInfoRec *info, NSString **path, NSString **name) {
    FSSpec spec;
    FSRef ref;
    Str255 n;
    UInt8 file[1024];
    memset(info, 0, sizeof(*info));
    info->processInfoLength = sizeof(*info);
    info->processAppSpec = path ? &spec : NULL;
    info->processName = name ? n : NULL;
    if (GetProcessInformation(&p, info))
        return NO;
    if (path)
        *path = (!FSpMakeFSRef(&spec, &ref) && !FSRefMakePath(&ref, file, sizeof(file)))
                    ? [NSString stringWithUTF8String:(char *)file]
                    : @"";
    if (name)
        *name = [[[NSString alloc] initWithBytes:n + 1
                                          length:n[0]
                                        encoding:NSMacOSRomanStringEncoding] autorelease];
    return YES;
}
/* Quake's fullscreen -> windowed transition can leave Tiger's shared Carbon
 * menu window at 0x0. It is still registered and marked visible, so ordering
 * it in or reasserting the same foreground process cannot restore it. Finder
 * has its own intact menu window; activating it rebuilds the shared backstop,
 * and reactivating the selected application redraws that application's menus.
 * Run only after the controller has hidden Classic and finished its repaint. */
static BOOL menuBounds(ProcessSerialNumber p, CGRect *bounds) {
    int ours = CGSMainConnectionID(), connection = 0, window = 0;
    CFTypeRef value = NULL;
    if (CGSGetConnectionIDForPSN(ours, &p, &connection) ||
        CGSGetConnectionProperty(ours, connection, CFSTR("menuHidden"), &value) || !value ||
        CFGetTypeID(value) != CFBooleanGetTypeID() || CFBooleanGetValue((CFBooleanRef)value))
        return NO;
    value = NULL;
    if (CGSGetConnectionProperty(ours, connection, CFSTR("menuBar"), &value) || !value ||
        CFGetTypeID(value) != CFNumberGetTypeID() ||
        !CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &window) || window <= 0)
        return NO;
    /* These CGS values are connection-autoreleased, not caller-owned. */
    return CGSGetWindowBounds(ours, (unsigned)window, bounds) == 0;
}
static int repairNativeMenu(void) {
    ProcessSerialNumber selected, current, finder = {0, kNoProcess};
    pid_t pid = 0;
    BOOL found = NO;
    CGRect bounds;
    if (GetFrontProcess(&selected) || GetProcessPID(&selected, &pid) || pid <= 0 ||
        !menuBounds(selected, &bounds) || !CGRectIsEmpty(bounds))
        return 0;
    /* Allow an ordinary activation to finish before treating this as damage. */
    usleep(20000);
    if (GetFrontProcess(&current) || !samePSN(current, selected) ||
        !menuBounds(selected, &bounds) || !CGRectIsEmpty(bounds))
        return 0;
    while (GetNextProcess(&finder) == noErr) {
        ProcessInfoRec info;
        NSString *path = nil;
        pid = 0;
        if (GetProcessPID(&finder, &pid) || pid <= 0 || samePSN(finder, selected))
            continue;
        if (infoFor(finder, &info, &path, NULL) &&
            [path isEqual:@"/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"]) {
            found = YES;
            break;
        }
    }
    if (!found || !menuBounds(finder, &bounds) || CGRectIsEmpty(bounds) || GetFrontProcess(&current) ||
        !samePSN(current, selected))
        return 0;
    if (activate(finder))
        return 1;
    int i;
    for (i = 0; i < 25; i++) {
        if (menuBounds(selected, &bounds) && !CGRectIsEmpty(bounds))
            break;
        usleep(10000);
    }
    /* Do not override a third application selected while the repair ran. */
    if (GetFrontProcess(&current) || !samePSN(current, finder))
        return 0;
    if (activate(selected))
        return 1;
    if (!menuBounds(selected, &bounds) || CGRectIsEmpty(bounds))
        return 1;
    CFSLog(@"Restored collapsed native menu bar for %08lx", selected.lowLongOfPSN);
    return 0;
}
static int preferences(NSString *op) {
    CFStringRef domain = CFSTR("com.apple.Classic");
    CFStringRef keys[2] = {CFSTR("Fullscreen"), CFSTR("UseRealFinder")};
    int i;
    if ([op isEqual:@"preferences-check"] || [op isEqual:@"preferences-on"]) {
        for (i = 0; i < 2; i++) {
            CFPropertyListRef v = CFPreferencesCopyValue(keys[i], domain, kCFPreferencesCurrentUser,
                                                         kCFPreferencesCurrentHost);
            if (v) {
                CFRelease(v);
                CFSLog(@"Classic session preference already exists");
                return 1;
            }
        }
    }
    if ([op isEqual:@"preferences-check"])
        return 0;
    int one = 1;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &one);
    for (i = 0; i < 2; i++)
        CFPreferencesSetValue(keys[i], [op isEqual:@"preferences-on"] ? number : NULL, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    CFRelease(number);
    return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
               ? 0
               : 1;
}
int CFActions(NSArray *args) {
    CFRequire([args count] >= 1, @"Missing action");
    NSString *op = [args objectAtIndex:0];
    if ([op isEqual:@"system-folder"]) {
        const char *path = [CFConfiguredSystemFolder() UTF8String];
        CFWriteAll(STDOUT_FILENO, path, strlen(path));
        return 0;
    }
    if ([op isEqual:@"identity"]) {
        printf("%u %u %s", (unsigned)getuid(), (unsigned)getgid(), [CFUserName UTF8String]);
        return 0;
    }
    if ([op hasPrefix:@"preferences-"])
        return preferences(op);
    if ([op isEqual:@"open-classic"]) {
        CFEnsureSystemFolder();
        CFRequire([CFConfiguredSystemFolder() isEqual:CFSystemFolder],
                  @"Classic's selected System Folder changed during startup; please start again.");
        FSRef ref;
        CFRequire(FSPathMakeRef((const UInt8 *)"/System/Library/CoreServices/Classic Startup.app",
                                &ref, NULL) == 0,
                  @"Classic Startup is missing");
        return LSOpenFSRef(&ref, NULL) != noErr;
    }
    /* CPS does not lazily register a command-line client. Do this before
     * any private process call, including the early clear-exit return. */
    ProcessSerialNumber actionPSN;
    CFRequire(GetCurrentProcess(&actionPSN) == noErr, @"Cannot register process action");
    if ([op isEqual:@"repair-menu"])
        return repairNativeMenu();
    if ([op isEqual:@"clear-exit"]) {
        OSStatus status = CPSSetProcessToBringForwardAtNextApplicationExit(0, 0);
        if (status)
            CFSLog(@"Clear exit target: %ld", (long)status);
        return status != noErr;
    }
    ProcessSerialNumber p = {0, kNoProcess}, guestFinder = {0, 0}, nativeFinder = {0, 0},
                        target = {0, 0};
    UInt32 requested = 0;
    BOOL listing = [op isEqual:@"list"];
    BOOL nativeOperation = [op isEqual:@"native"] || [op isEqual:@"finder-osx"];
    if ([args count] > 1) {
        const char *t = [[args objectAtIndex:1] UTF8String];
        char *end = NULL;
        requested = strtoul(t, &end, 16);
        CFRequire(requested && !*end && strlen(t) <= 8, @"Invalid process serial number");
    }
    if (requested && [op isEqual:@"return"]) {
        /* A Dock selection already provides a registered guest PSN. Validate
         * that record without requesting any guest names, files or Finder
         * metadata while the guest is servicing its resume event. */
        ProcessSerialNumber selected = {0, requested};
        ProcessInfoRec info;
        pid_t pid = 0;
        CFSLog(@"Return requested for %08lx", (unsigned long)requested);
        if (GetProcessPID(&selected, &pid) == procNotFound && pid <= 0 &&
            infoFor(selected, &info, NULL, NULL) && !(info.processMode & modeOnlyBackground)) {
            if (CPSSetProcessToBringForwardAtNextApplicationExit(0, 0))
                return 1;
            if (!activate(selected)) {
                CFSLog(@"Return acknowledged for %08lx", (unsigned long)requested);
                return 0;
            }
        }
        CFSLog(@"Saved Classic app unavailable; locating OS 9 Finder");
    }
    while (GetNextProcess(&p) == noErr) {
        ProcessInfoRec info;
        NSString *path = nil, *name = nil;
        pid_t pid = -1;
        OSStatus status = GetProcessPID(&p, &pid);
        BOOL guest = status == procNotFound && pid <= 0;
        /* Native activation must not ask the suspended guest for file/name
         * information. In particular, return immediately after finding Finder,
         * as the original native switch helper did. */
        if (!listing && (nativeOperation ? pid <= 0 : !guest))
            continue;
        if (!infoFor(p, &info, (listing || nativeOperation) ? &path : NULL,
                     listing ? &name : NULL))
            continue;
        if (guest && info.processType == 'FNDR' && info.processSignature == 'MACS') {
            if (!path && !infoFor(p, &info, &path, NULL))
                continue;
            if ([path isEqual:CFFinderPath()])
                guestFinder = p;
        }
        if (pid > 0 &&
            [path isEqual:@"/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"])
            nativeFinder = p;
        if (requested && p.highLongOfPSN == 0 && p.lowLongOfPSN == requested &&
            !(info.processMode & modeOnlyBackground) &&
            (([op isEqual:@"return"] && guest) || ([op isEqual:@"native"] && pid > 0)))
            target = p;
        if (listing)
            CFSLog(@"%08lx:%08lx pid=%d mode=%08lx creator=%08lx %@ %@", p.highLongOfPSN,
                   p.lowLongOfPSN, pid, info.processMode, info.processSignature, name, path);
        else if (nativeOperation) {
            if (target.lowLongOfPSN)
                return activate(target);
            if (nativeFinder.lowLongOfPSN && (!requested || [op isEqual:@"finder-osx"]))
                return activate(nativeFinder);
        } else if (guestFinder.lowLongOfPSN &&
                   (![op isEqual:@"return"] || !requested || target.lowLongOfPSN)) {
            break;
        }
    }
    if ([op isEqual:@"list"])
        return 0;
    if ([op isEqual:@"native"] || [op isEqual:@"finder-osx"]) {
        if (!target.lowLongOfPSN)
            target = nativeFinder;
        if (!target.lowLongOfPSN)
            CFSLog(@"Native Finder process was not found");
        return !target.lowLongOfPSN || activate(target);
    }
    if (!guestFinder.lowLongOfPSN)
        return 1;
    if ([op isEqual:@"stop"] || [op isEqual:@"restart"]) {
        BOOL restart = [op isEqual:@"restart"];
        AEAddressDesc address = {typeNull, NULL};
        AppleEvent event = {typeNull, NULL};
        OSStatus err =
            AECreateDesc(typeProcessSerialNumber, &guestFinder, sizeof(guestFinder), &address);
        if (!err)
            err = AECreateAppleEvent('FNDR', restart ? kAERestart : kAEShutDown,
                                     &address, kAutoGenerateReturnID,
                                     kAnyTransactionID, &event);
        if (!err)
            err = AESendMessage(&event, NULL, kAENoReply | kAECanInteract, kAEDefaultTimeout);
        AEDisposeDesc(&event);
        AEDisposeDesc(&address);
        CFSLog(@"Normal Classic %@ request: %ld", restart ? @"restart" : @"shutdown", (long)err);
        return err != 0;
    }
    if ([op isEqual:@"return"]) {
        if (CPSSetProcessToBringForwardAtNextApplicationExit(0, 0))
            return 1;
        if (!target.lowLongOfPSN)
            target = guestFinder;
        if (!activate(target))
            return 0;
        return activate(guestFinder);
    }
    if ([op isEqual:@"finder-classic"])
        return activate(guestFinder);
    CFFail(@"Unknown action %@", op);
}
CFFront CFFrontProcess(pid_t host) {
    CFFront f = {CFNoFront, 0, 0, NO};
    ProcessSerialNumber p;
    UInt32 words[9];
    ProcessInfoRec info;
    if (CPSGetFrontProcess(&p) || CPSGetProcessInfo(&p, words, NULL, 0, NULL, NULL, 0))
        return f;
    memset(&info, 0, sizeof(info));
    info.processInfoLength = sizeof(info);
    if (GetProcessInformation(&p, &info))
        return f;
    if (p.highLongOfPSN || !p.lowLongOfPSN || !words[8] || words[8] == (UInt32)host)
        return f;
    f.foreground = (info.processMode & modeOnlyBackground) == 0;
    if (words[8] == 0xffffffffU && !f.foreground)
        return f;
    f.psn = p.lowLongOfPSN;
    f.pid = (pid_t)words[8];
    f.kind = words[8] == 0xffffffffU ? CFGuestFront
             : words[7] == 'ClSw'    ? CFProxyFront
                                     : CFNativeFront;
    return f;
}
BOOL CFFullscreenRect(CGRect r, CGRect d) {
    return r.origin.x >= d.origin.x - 1 && r.origin.x <= d.origin.x &&
           r.origin.y >= d.origin.y - 1 && r.origin.y <= d.origin.y &&
           CGRectGetMaxX(r) >= CGRectGetMaxX(d) && CGRectGetMaxX(r) <= CGRectGetMaxX(d) + 1 &&
           CGRectGetMaxY(r) >= CGRectGetMaxY(d) && CGRectGetMaxY(r) <= CGRectGetMaxY(d) + 1 &&
           d.size.width >= 640 && d.size.height >= 480;
}
BOOL CFDrawableRect(CGRect r, CGRect d) {
    return r.size.width > 0 && r.size.height > 0 && d.size.width > 0 && d.size.height > 0 &&
           r.origin.x < CGRectGetMaxX(d) && r.origin.y < CGRectGetMaxY(d) &&
           CGRectGetMaxX(r) > d.origin.x && CGRectGetMaxY(r) > d.origin.y;
}
