#import "CFClassic.h"
#include <fcntl.h>
#include <math.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    uint32_t away, pending, transition, request, bases[4], shadow, trace[11], stride, depth;
    float width, height;
} CFGraphicsSnapshot;
@interface CFControllerState : NSObject {
    task_t task;
    pid_t pid;
    int ours, connection, pipeFD;
    NSMutableArray *hidden, *pendingUI;
    NSMutableDictionary *raised;
    UInt32 guest, native;
    ProcessSerialNumber nativeExitTarget;
    OSStatus nativeExitError;
    double nextNativeExit;
    BOOL away, prepared, coverActive;
    char redrawToken;
    NSData *lastClip;
    vm_address_t clipMemory;
    CGRect lastDisplay;
}
- (id)initWithPID:(pid_t)p;
- (void)run;
- (void)cleanup;
- (CFGraphicsSnapshot)snapshot;
- (BOOL)valid:(CFGraphicsSnapshot)s away:(unsigned)value;
- (void)handoff:(BOOL)value;
- (void)order:(unsigned)window how:(unsigned)how;
- (void)waitIdle:(uint32_t *)mail;
- (void)returnClassic:(UInt32)front;
- (void)showOSX:(UInt32)front finder:(BOOL)finder;
- (void)updateGL:(CFFront)front;
- (void)refreshNativeExit;
@end
static void interrupted(int sig) {
    CFInterrupted = sig;
}
static NSNumber *number(unsigned x) {
    return [NSNumber numberWithUnsignedInt:x];
}
static NSString *psnString(UInt32 p) {
    return [NSString stringWithFormat:@"%08lx", (unsigned long)p];
}
static CGRect rectValue(NSValue *v) {
    CGRect r;
    [v getValue:&r];
    return r;
}
static NSValue *boxRect(CGRect r) {
    return [NSValue value:&r withObjCType:@encode(CGRect)];
}
static void windowGone(void) {
    @throw [NSException exceptionWithName:@"WindowGone"
                                   reason:@"Window moved or disappeared"
                                 userInfo:nil];
}
static void regionOK(int result, void *region) {
    if (result || !region)
        CFFail(@"Region operation failed (%d)", result);
}
static void *rectangle(CGRect r) {
    void *p = NULL;
    int result = CGSNewRegionWithRect(&r, &p);
    regionOK(result, p);
    return p;
}
static void *combine(int kind, void *a, void *b) {
    void *p = NULL;
    int result = kind == 0   ? CGSUnionRegion(a, b, &p)
                 : kind == 1 ? CGSIntersectRegion(a, b, &p)
                             : CGSDiffRegion(a, b, &p);
    regionOK(result, p);
    return p;
}
static void releaseRegion(void *p) {
    if (p)
        CGSReleaseRegion(p);
}
@implementation CFControllerState
- (id)initWithPID:(pid_t)p {
    if ((self = [super init])) {
        pid = p;
        task = MACH_PORT_NULL;
        pipeFD = -1;
        hidden = [[NSMutableArray alloc] init];
        pendingUI = [[NSMutableArray alloc] init];
        raised = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc {
    [hidden release];
    [pendingUI release];
    [raised release];
    [lastClip release];
    if (pipeFD >= 0)
        close(pipeFD);
    if (task)
        mach_port_deallocate(mach_task_self(), task);
    [super dealloc];
}
- (void)writeMailbox:(uint32_t)address data:(const void *)data size:(unsigned)n {
    CFRequire(address >= CF_MAIL && address + n <= CF_MAIL + 40, @"Write outside Classic mailbox");
    CFRequire(vm_write(task, address, (vm_offset_t)data, n) == 0, @"Mailbox write failed");
}
- (void)waitIdle:(uint32_t *)mail {
    int i;
    for (i = 0; i < 250; i++) {
        CFReadMemory(task, CF_MAIL, mail, 32);
        if (mail[1] == mail[2] && !mail[7])
            return;
        usleep(20000);
    }
    CFFail(@"Classic did not acknowledge its window request");
}
- (int)request:(unsigned)wid how:(unsigned)how {
    uint32_t mail[8], args[3] = {wid, how, 0};
    [self waitIdle:mail];
    uint32_t sequence = mail[1] + 1;
    [self writeMailbox:CF_MAIL + 12 data:args size:12];
    [self writeMailbox:CF_MAIL + 4 data:&sequence size:4];
    [self waitIdle:mail];
    return (int)mail[5];
}
- (BOOL)guestAway {
    uint32_t ctx = CFWord(task, 0x5e0a3530);
    CFRequire(ctx != 0, @"Missing Classic graphics context");
    return CFWord(task, ctx + 464) == 1;
}
- (void)order:(unsigned)wid how:(unsigned)how {
    int result = [self request:wid how:how];
    if (result == -47 && how == 0 && ![self guestAway])
        @throw [NSException exceptionWithName:@"ClassicReturnInProgress"
                                       reason:@"Guest returned before window hiding"
                                     userInfo:nil];
    if (result)
        CFFail(@"Classic window request failed (%d)", result);
}
- (NSArray *)windows:(BOOL)onscreen {
    uint32_t ids[1024];
    int n = 0;
    int r = onscreen ? CGSGetOnScreenWindowList(ours, connection, 1024, ids, &n)
                     : CGSGetWindowList(ours, connection, 1024, ids, &n);
    CFRequire(!r && n >= 0 && n < 1024, @"Invalid Classic window list");
    NSMutableArray *a = [NSMutableArray array];
    int i;
    for (i = 0; i < n; i++)
        [a addObject:number(ids[i])];
    return a;
}
- (CFGraphicsSnapshot)snapshot {
    CFGraphicsSnapshot s;
    memset(&s, 0, sizeof(s));
    uint32_t ctx = CFWord(task, 0x5e0a3530);
    CFRequire(ctx != 0, @"Missing graphics context");
    uint32_t display = CFWord(task, ctx + 16), request = CFWord(task, ctx + 384);
    CFRequire(display && request, @"Missing display request");
    uint32_t device = CFWord(task, CFWord(task, 0x8a4)),
             pixmap = CFWord(task, CFWord(task, device + 22));
    s.away = CFWord(task, ctx + 464);
    s.pending = CFWord(task, ctx + 468);
    s.transition = CFWord(task, ctx + 392);
    s.request = CFWord(task, request);
    s.bases[0] = CFWord(task, display + 8);
    s.bases[1] = CFWord(task, 0x824);
    s.bases[2] = CFWord(task, 0x898);
    s.bases[3] = CFWord(task, pixmap);
    s.shadow = CFWord(task, CFWord(task, 0xa03909d4) + 40);
    CFReadMemory(task, 0x5e0a4400, s.trace, 44);
    s.stride = CFWord(task, display + 28);
    s.depth = CFWord(task, display + 32);
    CFReadMemory(task, display + 20, &s.width, 8);
    return s;
}
- (BOOL)valid:(CFGraphicsSnapshot)s away:(unsigned)value {
    BOOL geometry = s.width >= 640 && s.width <= 4096 && s.height >= 480 && s.height <= 2160 &&
                    s.width == (int)s.width && s.height == (int)s.height &&
                    CFSupportedDisplayDepth(s.depth) && s.stride >= s.width * (s.depth / 8) &&
                    s.stride <= 32768;
    BOOL backing =
        s.shadow == 0 &&
        (value == 1 ? (geometry && s.trace[9] == s.bases[0] && s.trace[10] == s.stride * s.height)
                    : (!s.trace[9] && !s.trace[10]));
    return s.away == value && !s.pending && !s.transition && !s.request && s.bases[0] &&
           s.bases[0] == s.bases[1] && s.bases[0] == s.bases[2] && s.bases[0] == s.bases[3] &&
           backing && !s.trace[8];
}
- (CFGraphicsSnapshot)settled {
    unsigned i, stable = 0;
    CFGraphicsSnapshot old;
    memset(&old, 0, sizeof(old));
    for (i = 0; i < 250; i++) {
        @try {
            CFGraphicsSnapshot s = [self snapshot];
            if (s.trace[8])
                @throw [NSException exceptionWithName:@"HandoffRecovery"
                                               reason:@"Graphics handoff needs recovery"
                                             userInfo:nil];
            if (s.away <= 1 && [self valid:s away:s.away]) {
                stable = (s.away == old.away && s.trace[0] == old.trace[0] &&
                          !memcmp(s.bases, old.bases, 16))
                             ? stable + 1
                             : 1;
                if (stable >= 3)
                    return s;
            } else
                stable = 0;
            old = s;
        } @catch (NSException *e) {
            if ([[e name] isEqual:@"HandoffRecovery"])
                @throw;
            stable = 0;
            memset(&old, 0, sizeof(old));
        }
        usleep(40000);
    }
    CFFail(@"Graphics handoff did not settle within ten seconds");
}
- (void)handoff:(BOOL)value {
    unsigned target = value ? 1 : 0;
    CFGraphicsSnapshot before = [self settled];
    CGDirectDisplayID displays[2];
    CGDisplayCount count = 0;
    uint32_t ctx = CFWord(task, 0x5e0a3530), display = CFWord(task, ctx + 16);
    CFRequire(CGGetActiveDisplayList(2, displays, &count) == 0 && count == 1 &&
                  (uint32_t)displays[0] == CFWord(task, display) && CFWord(task, display + 128) == 1,
              @"Switching requires one active display matching Classic's drawing surface");
    if ([self valid:before away:target])
        return;
    CFRequire([self valid:before away:1 - target], @"Graphics handoff already pending");
    [self order:0 how:value ? 2 : 3];
    unsigned stable = 0, i;
    for (i = 0; i < 250; i++) {
        CFGraphicsSnapshot now = [self snapshot];
        CFRequire(!now.trace[8], @"Graphics handoff needs recovery");
        if (now.trace[0] > before.trace[0] && !now.pending) {
            if (now.trace[6])
                CFFail(@"Graphics handoff failed (%08x)", now.trace[6]);
            stable = [self valid:now away:target] ? stable + 1 : 0;
            if (stable >= 3)
                return;
        }
        usleep(40000);
    }
    CFFail(@"Guest did not complete graphics handoff within ten seconds");
}
- (void)redrawOSX {
    redrawToken = redrawToken == 'D' ? 'd' : 'D';
    CFWriteState(redrawToken);
    double end = CFMonotonicTime() + 3;
    while (CFMonotonicTime() < end) {
        if (!CFReadable(pipeFD, 0.05))
            continue;
        char v = 0;
        if (read(pipeFD, &v, 1) != 1)
            continue;
        if (v == redrawToken)
            return;
        if (v == 'E')
            CFFail(@"Native desktop repaint failed");
        if (v == 'S' || v == 'R' || v == 'O')
            [pendingUI addObject:number(v)];
    }
    CFFail(@"Native repaint helper did not respond");
}
- (void)user:(NSString *)action target:(UInt32)target {
    NSArray *a = target ? [NSArray arrayWithObjects:action, psnString(target), nil]
                        : [NSArray arrayWithObject:action];
    int status = CFUserAction(a, 3);
    if (status)
        CFFail(@"Activation failed: %@ (helper status %d)", action, status);
}
- (void)returnClassic:(UInt32)front {
    [self user:@"clear-exit" target:0];
    memset(&nativeExitTarget, 0, sizeof(nativeExitTarget));
    CFWriteState('B');
    [self handoff:YES];
    [self waitIdle:(uint32_t[8]){0}];
    while ([hidden count]) {
        NSNumber *w = [hidden lastObject];
        if ([[self windows:NO] containsObject:w])
            [self order:[w unsignedIntValue] how:1];
        [hidden removeLastObject];
    }
    [self handoff:NO];
    [self user:@"return" target:front];
    CFWriteState('C');
    CFSLog(@"Classic visible; applications remain running");
}
- (void)publishClip:(void *)region {
    const void *bytes = NULL;
    unsigned n = 0;
    CFRequire(CGSGetRegionData(region, &bytes, &n) == 0 && bytes && n && n <= 65536,
              @"Cannot serialize cover region");
    NSData *data = [NSData dataWithBytes:bytes length:n];
    if ([data isEqual:lastClip])
        return;
    if (!clipMemory)
        CFRequire(vm_allocate(task, &clipMemory, 65536, TRUE) == 0,
                  @"Cannot allocate clipping request");
    uint32_t mail[8];
    [self waitIdle:mail];
    CFRequire(vm_write(task, clipMemory, (vm_offset_t)bytes, n) == 0,
              @"Cannot write clipping request");
    uint32_t descriptor[2] = {clipMemory, n}, args[3] = {0, 6, 0}, sequence = mail[1] + 1;
    [self writeMailbox:CF_MAIL + 32 data:descriptor size:8];
    [self writeMailbox:CF_MAIL + 12 data:args size:12];
    [self writeMailbox:CF_MAIL + 4 data:&sequence size:4];
    [self waitIdle:mail];
    CFRequire(mail[5] == 0, @"Classic rejected cover clipping");
    [lastClip release];
    lastClip = [data copy];
}
- (void)clearCover {
    if (!lastClip)
        return;
    void *r = NULL;
    @try {
        r = rectangle(lastDisplay);
        [self publishClip:r];
        [lastClip release];
        lastClip = nil;
        coverActive = NO;
    } @finally {
        releaseRegion(r);
    }
}
- (void)showOSX:(UInt32)target finder:(BOOL)finder {
    [self clearCover];
    CFWriteState('B');
    [self handoff:YES];
    [self user:@"clear-exit" target:0];
    memset(&nativeExitTarget, 0, sizeof(nativeExitTarget));
    [self refreshNativeExit];
    NSArray *windows = [self windows:YES];
    unsigned i;
    for (i = 0; i < [windows count]; i++) {
        NSNumber *w = [windows objectAtIndex:i];
        if (![hidden containsObject:w])
            [hidden addObject:w];
        [self order:[w unsignedIntValue] how:0];
    }
    if (finder)
        [self user:@"finder-osx" target:0];
    else if (target)
        [self user:@"native" target:target];
    [self redrawOSX];
    /* A menu repair is optional presentation recovery, not a reason to shut
     * down a running Classic session if a native application is unresponsive. */
    int menuStatus = CFUserAction([NSArray arrayWithObject:@"repair-menu"], 2);
    if (menuStatus)
        CFSLog(@"Native menu repair did not complete (status %d)", menuStatus);
    [self refreshNativeExit];
    CFWriteState('A');
    CFSLog(@"OS X visible; selected application keeps focus");
}
- (void)refreshNativeExit {
    OSStatus err = CFRefreshNativeExitTarget(pid, &nativeExitTarget);
    if (err && err != nativeExitError)
        CFSLog(@"OS X exit target refresh: %ld", (long)err);
    nativeExitError = err;
    nextNativeExit = CFMonotonicTime() + 0.25;
}
- (NSArray *)glRows:(CGRect)display {
    NSArray *visible = [self windows:YES];
    NSMutableArray *ids = [NSMutableArray arrayWithArray:visible];
    NSArray *keys = [raised allKeys];
    unsigned i;
    for (i = 0; i < [keys count]; i++)
        if (![ids containsObject:[keys objectAtIndex:i]])
            [ids addObject:[keys objectAtIndex:i]];
    NSMutableArray *rows = [NSMutableArray array];
    for (i = 0; i < [ids count]; i++) {
        NSNumber *w = [ids objectAtIndex:i];
        unsigned wid = [w unsignedIntValue], surfaces = 0;
        CGRect r;
        int level;
        ProcessSerialNumber owner;
        if (CGSGetWindowBounds(ours, wid, &r) ||
            (![raised objectForKey:w] && !CFDrawableRect(r, display)) ||
            CGSGetWindowLevel(ours, wid, &level) || CPSGetWindowOwner(wid, &owner))
            continue;
        CGSGetSurfaceCount(ours, wid, &surfaces);
        [rows addObject:[NSDictionary
                            dictionaryWithObjectsAndKeys:w, @"id", boxRect(r), @"rect",
                                                         number(level), @"level",
                                                         number(owner.highLongOfPSN == 0
                                                                    ? owner.lowLongOfPSN
                                                                    : 0),
                                                         @"owner", number(surfaces), @"surfaces",
                                                         number([visible containsObject:w]),
                                                         @"visible", nil]];
    }
    return rows;
}
- (void)syncLevels:(NSArray *)rows display:(CGRect)display front:(UInt32)front {
    NSMutableDictionary *live = [NSMutableDictionary dictionary],
                        *wanted = [NSMutableDictionary dictionary];
    unsigned i;
    for (i = 0; i < [rows count]; i++) {
        NSDictionary *r = [rows objectAtIndex:i];
        NSNumber *w = [r objectForKey:@"id"];
        [live setObject:r forKey:w];
        unsigned level = [[r objectForKey:@"level"] unsignedIntValue];
        if ([[r objectForKey:@"visible"] boolValue] && front &&
            [[r objectForKey:@"owner"] unsignedIntValue] == front &&
            [[r objectForKey:@"surfaces"] unsignedIntValue] > 0 &&
            CFFullscreenRect(rectValue([r objectForKey:@"rect"]), display) &&
            (level == 0 || ([raised objectForKey:w] && level == 2147483631U)))
            [wanted setObject:number(1) forKey:w];
    }
    NSArray *keys = [raised allKeys];
    for (i = 0; i < [keys count]; i++) {
        NSNumber *w = [keys objectAtIndex:i];
        if ([wanted objectForKey:w])
            continue;
        NSDictionary *r = [live objectForKey:w];
        if (!r || [[r objectForKey:@"level"] unsignedIntValue] != 2147483631U ||
            [self request:[w unsignedIntValue] how:5] == 0)
            [raised removeObjectForKey:w];
    }
    keys = [wanted allKeys];
    for (i = 0; i < [keys count]; i++) {
        NSNumber *w = [keys objectAtIndex:i];
        if (![raised objectForKey:w] && [self request:[w unsignedIntValue] how:4] == 0)
            [raised setObject:number(1) forKey:w];
    }
}
- (void *)surfaceArea:(NSDictionary *)row {
    void *total = NULL, *part = NULL, *result = NULL;
    unsigned wid = [[row objectForKey:@"id"] unsignedIntValue];
    CGRect bounds, after, expected = rectValue([row objectForKey:@"rect"]);
    @try {
        if (CGSGetWindowBounds(ours, wid, &bounds) || !CGRectEqualToRect(bounds, expected))
            windowGone();
        unsigned ids[32];
        int count = 0;
        if (CGSGetSurfaceList(ours, wid, 32, ids, &count))
            windowGone();
        CFRequire(count >= 0 && count <= 32, @"Invalid surface count");
        int r = CGSNewEmptyRegion(&total);
        regionOK(r, total);
        int i;
        for (i = 0; i < count; i++) {
            CGRect rect;
            if (CGSGetSurfaceBounds(ours, wid, ids[i], &rect))
                windowGone();
            if (rect.size.width <= 0 || rect.size.height <= 0)
                continue;
            rect.origin.x += bounds.origin.x;
            rect.origin.y += bounds.origin.y;
            part = rectangle(rect);
            void *combined = combine(0, total, part);
            releaseRegion(total);
            total = combined;
            releaseRegion(part);
            part = NULL;
        }
        if (CGSGetWindowBounds(ours, wid, &after) || !CGRectEqualToRect(bounds, after))
            windowGone();
        result = total;
        total = NULL;
    } @finally {
        releaseRegion(total);
        releaseRegion(part);
    }
    return result;
}
- (void)coverRows:(NSArray *)rows display:(CGRect)display cover:(unsigned)cover {
    void *remaining = NULL, *clip = NULL, *shape = NULL, *hole = NULL, *surface = NULL;
    unsigned i;
    coverActive = NO;
    lastDisplay = display;
    @try {
        for (i = 0; i < [rows count]; i++) {
            NSDictionary *r = [rows objectAtIndex:i];
            if ([[r objectForKey:@"visible"] boolValue] &&
                [[r objectForKey:@"surfaces"] unsignedIntValue] > 0 &&
                !CFFullscreenRect(rectValue([r objectForKey:@"rect"]), display))
                coverActive = YES;
        }
        if (!coverActive) {
            [self clearCover];
            return;
        }
        remaining = rectangle(display);
        clip = rectangle(display);
        for (i = 0; i < [rows count]; i++) {
            NSDictionary *row = [rows objectAtIndex:i];
            unsigned wid = [[row objectForKey:@"id"] unsignedIntValue];
            if (![[row objectForKey:@"visible"] boolValue] || wid == cover)
                continue;
            int result = CGSGetWindowShape(ours, wid, &shape);
            if (result == 1001)
                windowGone();
            regionOK(result, shape);
            if ([[row objectForKey:@"surfaces"] unsignedIntValue] > 0 &&
                !CFFullscreenRect(rectValue([row objectForKey:@"rect"]), display)) {
                hole = combine(1, remaining, shape);
                surface = [self surfaceArea:row];
                void *replacement = combine(1, hole, surface);
                releaseRegion(hole);
                hole = replacement;
                releaseRegion(surface);
                surface = NULL;
                replacement = combine(2, clip, hole);
                releaseRegion(clip);
                clip = replacement;
                releaseRegion(hole);
                hole = NULL;
            }
            void *replacement = combine(2, remaining, shape);
            releaseRegion(remaining);
            remaining = replacement;
            releaseRegion(shape);
            shape = NULL;
        }
        [self publishClip:clip];
    } @catch (NSException *e) {
        if (![[e name] isEqual:@"WindowGone"])
            @throw;
        [self clearCover];
    } @finally {
        releaseRegion(remaining);
        releaseRegion(clip);
        releaseRegion(shape);
        releaseRegion(hole);
        releaseRegion(surface);
    }
}
- (void)updateGL:(CFFront)front {
    uint32_t ctx = CFWord(task, 0x5e0a3530), d = CFWord(task, ctx + 16);
    CGRect display;
    CFReadMemory(task, d + 12, &display, 16);
    NSArray *rows = [self glRows:display];
    [self syncLevels:rows display:display front:front.kind == CFGuestFront ? front.psn : 0];
    [self coverRows:rows display:display cover:CFWord(task, d + 124)];
}
/* Return 1=Classic, 2=Aqua, 3=orderly shutdown. target0 means already active. */
- (int)observe:(CFFront)front
     automatic:(BOOL)automatic
        target:(UInt32 *)target
        finder:(BOOL *)finder {
    *target = 0;
    *finder = NO;
    if (front.kind == CFGuestFront) {
        guest = front.psn;
        if (automatic && away) {
            *target = guest;
            return 1;
        }
    } else if (front.kind == CFNativeFront) {
        if (front.foreground)
            native = front.psn;
        if (automatic && !away)
            return 2;
    } else if (front.kind == CFProxyFront && automatic) {
        if (away) {
            *target = guest;
            return 1;
        }
        *finder = YES;
        return 2;
    }
    return 0;
}
- (void)run {
    CFRequire(geteuid() == 0, @"Controller requires root");
    CFPatches *patches = [[[CFPatches alloc] initWithRoot:@""] autorelease];
    CFRequire([CFDigest(CFReadFile(CF_HOST))
                  isEqual:[[patches spec:@"Host"] objectForKey:@"patchedMD5"]],
              @"Unexpected Classic host");
    task = CFClassicTask(pid);
    uint32_t ctx = CFWord(task, 0x5e0a3530);
    CFRequire(CFWord(task, ctx + 460) == 1, @"Classic is not fullscreen");
    connection = CFWord(task, ctx);
    ProcessSerialNumber controllerPSN;
    CFRequire(GetCurrentProcess(&controllerPSN) == 0, @"Process services unavailable");
    ours = CGSMainConnectionID();
    uint32_t mail[8], zero[8] = {0};
    CFReadMemory(task, CF_MAIL, mail, 32);
    CFRequire(!memcmp(mail, zero, 32), @"Mailbox already in use");
    uint32_t magic = 'ClSw';
    [self writeMailbox:CF_MAIL data:&magic size:4];
    CFRequire([self valid:[self snapshot] away:0], @"Initial direct renderer state is invalid");
    struct stat info;
    NSString *fifo = [CF_RUN stringByAppendingPathComponent:@"session.request"];
    CFRequire(lstat([fifo fileSystemRepresentation], &info) == 0 && S_ISFIFO(info.st_mode) &&
                  info.st_uid == CFUserID && CFReadState() == 'P',
              @"Native UI was not prepared before fullscreen");
    pipeFD = open([fifo fileSystemRepresentation], O_RDWR | O_NONBLOCK | O_NOFOLLOW);
    CFRequire(pipeFD >= 0, @"Cannot open switch request channel");
    fcntl(pipeFD, F_SETFD, FD_CLOEXEC);
    prepared = YES;
    CFWriteState('B');
    CFFront front = CFFrontProcess(pid);
    guest = front.kind == CFGuestFront ? front.psn : 0;
    [self user:@"return" target:guest];
    CFWriteState('C');
    CFSLog(@"Native controller ready; menu/Dock switching active");
    double automaticAfter = CFMonotonicTime(), nextGL = automaticAfter;
    BOOL glMessage = NO;
    while (!CFInterrupted && CFTaskAlive(task, pid)) {
        NSAutoreleasePool *iteration = [[NSAutoreleasePool alloc] init];
        @try {
            @try {
                UInt32 target = 0;
                BOOL finder = NO;
                int action = [self observe:CFFrontProcess(pid)
                                 automatic:CFMonotonicTime() >= automaticAfter
                                    target:&target
                                    finder:&finder];
                if (away && ![self guestAway]) {
                    action = 1;
                    target = guest;
                    finder = NO;
                }
                if ([pendingUI count] || CFReadable(pipeFD, 0)) {
                    char value = 0;
                    if ([pendingUI count]) {
                        value = [[pendingUI objectAtIndex:0] intValue];
                        [pendingUI removeObjectAtIndex:0];
                    } else
                        read(pipeFD, &value, 1);
                    if (value == 'S') {
                        action = 3;
                        target = guest;
                        finder = NO;
                    } else if (value == 'O') {
                        action = 2;
                        target = 0;
                        finder = YES;
                    } else if (value == 'R' && away) {
                        action = 1;
                        target = guest;
                        finder = NO;
                    }
                }
                if (action == 2) {
                    CFFront selected = {CFGuestFront, guest, -1, YES};
                    [self updateGL:selected];
                }
                if (action == 2 && [raised count]) {
                    if (!glMessage)
                        CFSLog(@"Quit the fullscreen OpenGL game before switching desktops");
                    glMessage = YES;
                    CFFront current = CFFrontProcess(pid);
                    if (current.kind == CFNativeFront && guest)
                        [self user:@"return" target:guest];
                    action = 0;
                }
                if (action == 1) {
                    [self returnClassic:target];
                    away = NO;
                } else if (action == 2) {
                    [self showOSX:target finder:finder];
                    away = YES;
                } else if (action == 3) {
                    if (away)
                        [self returnClassic:target];
                    CFUserAction([NSArray arrayWithObject:@"stop"], 2);
                    automaticAfter = CFMonotonicTime() + 5;
                    away = NO;
                }
                if (away) {
                    if (CFMonotonicTime() >= nextNativeExit)
                        [self refreshNativeExit];
                    NSArray *appeared = [self windows:YES];
                    unsigned i;
                    for (i = 0; i < [appeared count]; i++) {
                        NSNumber *w = [appeared objectAtIndex:i];
                        if (![hidden containsObject:w])
                            [hidden insertObject:w atIndex:0];
                        [self order:[w unsignedIntValue] how:0];
                    }
                    if ([appeared count]) {
                        [self redrawOSX];
                        CFWriteState('A');
                    }
                }
            } @catch (NSException *e) {
                if (![[e name] isEqual:@"ClassicReturnInProgress"])
                    @throw;
                UInt32 target;
                BOOL finder;
                [self observe:CFFrontProcess(pid) automatic:NO target:&target finder:&finder];
                [self returnClassic:guest];
                away = NO;
            }
            if (!away && CFMonotonicTime() >= nextGL) {
                CFFront current = CFFrontProcess(pid);
                if (current.kind == CFGuestFront)
                    [self updateGL:current];
                nextGL = CFMonotonicTime() + (coverActive ? 0.05 : 0.5);
                if (![raised count])
                    glMessage = NO;
            }
            CFReadable(pipeFD, 0.1);
        } @catch (id exception) {
            /* Tiger's exception runtime does not retain objects across a pool drain. */
            [exception retain];
            [iteration release];
            [exception autorelease];
            @throw exception;
        }
        [iteration release];
    }
}
- (void)cleanup {
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    if (task && CFTaskAlive(task, pid)) {
        @try {
            if (away || [hidden count] || [self guestAway])
                [self returnClassic:guest];
        } @catch (NSException *e) {
            CFSLog(@"Final Classic return: %@", [e reason]);
        }
    }
    if (prepared)
        CFUserAction([NSArray arrayWithObject:@"clear-exit"], 3);
    /* UI and emergency channel belong to the guardian, including on failure. */
}
@end
int CFController(pid_t pid) {
    signal(SIGTERM, interrupted);
    signal(SIGINT, interrupted);
    CFControllerState *controller = [[CFControllerState alloc] initWithPID:pid];
    int result = 0;
    @try {
        [controller run];
    } @catch (NSException *e) {
        if ([CFProcessPath(pid) isEqual:CF_HOST]) {
            CFSLog(@"Controller: %@", [e reason]);
            result = 1;
        }
    } @finally {
        [controller cleanup];
        [controller release];
    }
    return result;
}

/* State-machine tests use no process, graphics service or memory writes. */
void CFControllerPolicyTests(void) {
    CFControllerState *c = [[CFControllerState alloc] initWithPID:0];
    UInt32 target = 0;
    BOOL finder = NO;
    CFFront guestFront = {CFGuestFront, 0x20001, -1, YES},
            nativeFront = {CFNativeFront, 0x40001, 85, YES},
            proxy = {CFProxyFront, 0x50001, 99, YES};
    @try {
        CFRequire([c observe:guestFront automatic:YES target:&target finder:&finder] == 0,
                  @"Guest activation must stay fullscreen");
        CFRequire([c observe:nativeFront automatic:YES target:&target finder:&finder] == 2 &&
                      target == 0 && !finder,
                  @"Native selection must retain selected app");
        [c setValue:[NSNumber numberWithBool:YES] forKey:@"away"];
        guestFront.psn = 0x30001;
        CFRequire([c observe:guestFront automatic:YES target:&target finder:&finder] == 1 &&
                      target == guestFront.psn,
                  @"Dock return must select requested guest");
        CFRequire([c observe:proxy automatic:YES target:&target finder:&finder] == 1 &&
                      target == guestFront.psn,
                  @"Proxy return must retain last guest");
        [c setValue:[NSNumber numberWithBool:NO] forKey:@"away"];
        CFRequire([c observe:proxy automatic:YES target:&target finder:&finder] == 2 && finder,
                  @"Finder alias must select native Finder");
        CFRequire([c observe:nativeFront automatic:NO target:&target finder:&finder] == 0,
                  @"Shutdown focus must not start switching");
        CFGraphicsSnapshot s;
        memset(&s, 0, sizeof(s));
        s.bases[0] = s.bases[1] = s.bases[2] = s.bases[3] = 0x100000;
        CFRequire([c valid:s away:0], @"Valid direct framebuffer rejected");
        s.pending = 1;
        CFRequire(![c valid:s away:0], @"Pending display transaction accepted");
        s.pending = 0;
        s.bases[2] += 4;
        CFRequire(![c valid:s away:0], @"Mismatched drawing addresses accepted");
        s.bases[2] -= 4;
        s.away = 1;
        s.width = 1024;
        s.height = 768;
        s.trace[9] = s.bases[0];
        unsigned depth;
        for (depth = 0; depth <= 64; depth++) {
            BOOL supported = depth == 8 || depth == 16 || depth == 32;
            CFRequire(CFSupportedDisplayDepth(depth) == supported,
                      @"Startup/monitor display-depth policy is inconsistent");
            s.depth = depth;
            s.stride = (1024 * depth + 7) / 8;
            s.trace[10] = s.stride * s.height;
            CFRequire([c valid:s away:1] == supported,
                      @"Private-buffer display-depth policy is inconsistent");
            if (supported) {
                s.stride--;
                s.trace[10] = s.stride * s.height;
                CFRequire(![c valid:s away:1], @"Undersized color-mode stride accepted");
            }
        }
        s.depth = 16;
        s.stride = 2048;
        s.trace[10] = s.stride * s.height;
        s.trace[10]--;
        CFRequire(![c valid:s away:1], @"Invalid RAM allocation size accepted");
        CGRect d = CGRectMake(0, 0, 1024, 768);
        CFRequire(CFFullscreenRect(CGRectMake(-1, -1, 1026, 770), d),
                  @"Fullscreen frame margin rejected");
        CFRequire(!CFFullscreenRect(CGRectMake(10, 30, 640, 480), d),
                  @"Windowed GL classified as fullscreen");
        CFRequire(CFDrawableRect(CGRectMake(10, 30, 640, 480), d), @"Visible GL window rejected");
    } @finally {
        [c release];
    }
    CFSLog(@"PASS: native app/Dock/proxy policy, handoff invariants and GL geometry");
}
