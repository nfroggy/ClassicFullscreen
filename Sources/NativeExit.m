#import "CFClassic.h"

typedef struct {
    ProcessSerialNumber psn;
    pid_t pid;
    UInt32 mode, creator;
    BOOL visible, finder;
} CFExitApplication;
typedef struct {
    ProcessSerialNumber owner;
    int level;
    CGRect bounds;
} CFExitWindow;

static BOOL equalPSN(ProcessSerialNumber a, ProcessSerialNumber b) {
    return a.highLongOfPSN == b.highLongOfPSN && a.lowLongOfPSN == b.lowLongOfPSN;
}
static BOOL eligible(CFExitApplication a, pid_t host) {
    return a.psn.lowLongOfPSN && a.pid > 0 && a.pid != host &&
           !(a.mode & modeOnlyBackground) && a.creator != 'ClSw';
}
/* Follow visible native window order, excluding the application that will
 * exit. Finder remains the fallback even if all its folder windows are shut.
 * Individual Classic PSNs have no Unix PID; the host and our Dock proxy must
 * also be excluded. No guest metadata or activation requests are needed. */
static ProcessSerialNumber choose(CFExitApplication *apps, unsigned count,
                                  CFExitWindow *windows, unsigned windowCount,
                                  ProcessSerialNumber front, pid_t host) {
    ProcessSerialNumber fallback = {0, 0};
    unsigned i, j;
    for (i = 0; i < count; i++)
        if (eligible(apps[i], host) && apps[i].finder)
            fallback = apps[i].psn;
    for (i = 0; i < windowCount; i++) {
        CFExitWindow w = windows[i];
        if (equalPSN(w.owner, front) || CGRectIsEmpty(w.bounds) ||
            w.level < CGWindowLevelForKey(kCGNormalWindowLevelKey) ||
            w.level >= CGWindowLevelForKey(kCGDockWindowLevelKey))
            continue;
        for (j = 0; j < count; j++)
            if (equalPSN(w.owner, apps[j].psn) && eligible(apps[j], host) && apps[j].visible)
                return apps[j].psn;
    }
    return fallback;
}

OSStatus CFRefreshNativeExitTarget(pid_t host, ProcessSerialNumber *installed) {
    CFExitApplication apps[512];
    CFExitWindow windows[1024];
    unsigned count = 0, windowCount = 0, i;
    ProcessSerialNumber front = {0, 0}, p = {0, kNoProcess};
    OSStatus err = CPSGetFrontProcess(&front);
    if (err)
        return err;
    BOOL nativeFront = NO;
    while (count < 512 && GetNextProcess(&p) == noErr) {
        pid_t unixPID = 0;
        ProcessInfoRec info;
        /* Filter before GetProcessInformation: asking a suspended guest for
         * file/name metadata can block its activation protocol. */
        if (GetProcessPID(&p, &unixPID) || unixPID <= 0 || unixPID == host)
            continue;
        memset(&info, 0, sizeof(info));
        info.processInfoLength = sizeof(info);
        if (GetProcessInformation(&p, &info))
            continue;
        CFExitApplication a = {p, unixPID, info.processMode, info.processSignature, NO, NO};
        if (!eligible(a, host))
            continue;
        a.visible = IsProcessVisible(&p);
        a.finder = info.processSignature == 'MACS' &&
            [CFProcessPath(unixPID) isEqual:@"/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"];
        apps[count++] = a;
        if (equalPSN(p, front))
            nativeFront = YES;
    }
    /* A Dock selection may already be returning to Classic. Do not replace
     * the guest's exit policy while that activation is in flight. */
    if (!nativeFront)
        return noErr;
    int ours = CGSMainConnectionID(), n = 0;
    unsigned ids[1024];
    err = CGSGetOnScreenWindowList(ours, 0, 1024, ids, &n);
    if (err || n < 0 || n > 1024)
        return err ? err : paramErr;
    for (i = 0; i < (unsigned)n; i++) {
        CFExitWindow w;
        if (CPSGetWindowOwner(ids[i], &w.owner) ||
            CGSGetWindowLevel(ours, ids[i], &w.level) ||
            CGSGetWindowBounds(ours, ids[i], &w.bounds))
            continue; /* Windows may close during enumeration. */
        windows[windowCount++] = w;
    }
    ProcessSerialNumber target = choose(apps, count, windows, windowCount, front, host), current;
    if (!target.lowLongOfPSN)
        return procNotFound;
    if (CPSGetFrontProcess(&current) || !equalPSN(current, front))
        return noErr;
    if (equalPSN(target, *installed))
        return noErr;
    err = CPSSetProcessToBringForwardAtNextApplicationExit(target.highLongOfPSN,
                                                          target.lowLongOfPSN);
    if (!err) {
        *installed = target;
        CFSLog(@"OS X exit target: %08lx:%08lx", target.highLongOfPSN, target.lowLongOfPSN);
    }
    return err;
}

void CFNativeExitPolicyTests(void) {
    CFExitApplication apps[] = {
        {{0, 1}, 100, 0, 'test', YES, NO}, /* current native application */
        {{0, 2}, -1, 0, 'test', YES, NO}, /* guest */
        {{0, 3}, 200, 0, 'ClSw', YES, NO}, /* fullscreen proxy */
        {{0, 4}, 300, 0, 'bbox', YES, NO}, /* Classic host */
        {{0, 5}, 400, modeOnlyBackground, 'dock', YES, NO},
        {{0, 6}, 500, 0, 'test', NO, NO}, /* hidden native application */
        {{0, 7}, 600, 0, 'test', YES, NO},
        {{0, 8}, 700, 0, 'MACS', YES, YES}
    };
    CFExitWindow windows[8];
    unsigned i;
    for (i = 0; i < 8; i++) {
        windows[i].owner = apps[i].psn;
        windows[i].level = 0;
        windows[i].bounds = CGRectMake(0, 0, 100, 100);
    }
    ProcessSerialNumber result = choose(apps, 8, windows, 8, apps[0].psn, 300);
    CFRequire(equalPSN(result, apps[6].psn), @"Exit policy selected a guest/helper/hidden/current app");
    windows[6].bounds = CGRectZero;
    result = choose(apps, 8, windows, 8, apps[0].psn, 300);
    CFRequire(equalPSN(result, apps[7].psn), @"Empty window prevented native Finder fallback");
    windows[6].bounds = CGRectMake(0, 0, 100, 100);
    windows[6].level = CGWindowLevelForKey(kCGMainMenuWindowLevelKey);
    result = choose(apps, 8, windows, 8, apps[0].psn, 300);
    CFRequire(equalPSN(result, apps[7].psn), @"Menu-bar window became an exit target");
    apps[6].pid = 0;
    windows[6].level = 0;
    result = choose(apps, 8, windows, 7, apps[0].psn, 300);
    CFRequire(equalPSN(result, apps[7].psn), @"Vanished application prevented Finder fallback");
    apps[7].visible = NO;
    result = choose(apps, 8, NULL, 0, apps[0].psn, 300);
    CFRequire(equalPSN(result, apps[7].psn), @"Finder fallback requires an open/visible folder window");
    apps[7].pid = 0;
    result = choose(apps, 8, windows, 7, apps[0].psn, 300);
    CFRequire(!result.lowLongOfPSN, @"No native successor must not select Classic");
    CFSLog(@"PASS: native exit window order, guest/helper/hidden exclusion, Finder fallback and vanished apps");
}
