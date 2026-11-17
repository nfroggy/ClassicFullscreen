#import "CFClassic.h"
#include <errno.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <pwd.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
static void stopSignal(int s) {
    CFInterrupted = s;
}
static int sessionFile(NSString *name, int flags, mode_t mode) {
    return open([[CF_RUN stringByAppendingPathComponent:name] fileSystemRepresentation],
                flags | O_NOFOLLOW, mode);
}
static void validateDirectory(void) {
    struct stat s;
    if (lstat([CF_RUN fileSystemRepresentation], &s) < 0) {
        CFRequire(errno == ENOENT && mkdir([CF_RUN fileSystemRepresentation], 0755) == 0,
                  @"Cannot create session directory");
        CFRequire(lstat([CF_RUN fileSystemRepresentation], &s) == 0,
                  @"Cannot inspect session directory");
    }
    CFRequire(S_ISDIR(s.st_mode) && s.st_uid == 0 && !(s.st_mode & 0022),
              @"Unsafe session directory");
}
static void removeSessionFile(NSString *name) {
    NSString *path = [CF_RUN stringByAppendingPathComponent:name];
    struct stat s;
    if (lstat([path fileSystemRepresentation], &s) == 0) {
        BOOL pipe = [name isEqual:@"session.request"] || [name isEqual:@"session.emergency"];
        /* The locked, root-owned directory may contain a prior user's stale
         * channel. Never follow links; only these exact session names qualify. */
        CFRequire(pipe ? S_ISFIFO(s.st_mode) : S_ISREG(s.st_mode),
                  @"Unsafe session file");
        CFRequire(unlink([path fileSystemRepresentation]) == 0, @"Cannot remove session file");
    } else
        CFRequire(errno == ENOENT, @"Cannot inspect session file");
}
static NSArray *sessionNames(void) {
    return [NSArray arrayWithObjects:@"session.request", @"session.emergency", @"session.state",
                                     @"session.state.new", @"session.result", nil];
}
static void cleanupChannels(void) {
    NSArray *names = sessionNames();
    unsigned i;
    for (i = 0; i < [names count]; i++)
        removeSessionFile([names objectAtIndex:i]);
}
static NSString *configurationPath(void) {
    return [CF_RUN stringByAppendingPathComponent:@"session.configuration"];
}
static BOOL configureSession(NSString *path) {
    struct stat file;
    BOOL interrupted = NO;
    if (lstat([path fileSystemRepresentation], &file) == 0) {
        CFRequire(S_ISREG(file.st_mode) && file.st_uid == 0 && file.st_nlink == 1 &&
                      (file.st_mode & 0777) == 0600 && file.st_size <= 8192,
                  @"Invalid saved session configuration");
        NSDictionary *saved = [NSPropertyListSerialization propertyListFromData:CFReadFile(path)
            mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
        CFRequire([saved isKindOfClass:[NSDictionary class]] &&
                      [[saved objectForKey:@"UserID"] unsignedIntValue] == CFUserID,
                  @"Log into the account that started the interrupted session to recover it.");
        NSString *folder = [saved objectForKey:@"SystemFolder"];
        CFRequire([folder isKindOfClass:[NSString class]], @"Missing saved System Folder");
        struct stat directory;
        CFRequire(lstat([folder fileSystemRepresentation], &directory) == 0 &&
                      S_ISDIR(directory.st_mode) &&
                      (unsigned long long)directory.st_dev == [[saved objectForKey:@"Device"] unsignedLongLongValue] &&
                      (unsigned long long)directory.st_ino == [[saved objectForKey:@"Inode"] unsignedLongLongValue],
                  @"The interrupted session's System Folder is unavailable or has moved.");
        CFSetSystemFolder(folder);
        interrupted = YES;
    } else {
        CFRequire(errno == ENOENT, @"Cannot inspect saved session configuration");
        CFEnsureSystemFolder();
    }
    CFSLog(@"Session account: %@ (uid %u, gid %u); Classic System Folder: %@",
           CFUserName, (unsigned)CFUserID, (unsigned)CFGroupID, CFSystemFolder);
    return interrupted;
}
static void saveConfiguration(NSString *path) {
    struct stat directory;
    CFRequire(lstat([CFSystemFolder fileSystemRepresentation], &directory) == 0 &&
                  S_ISDIR(directory.st_mode), @"Classic System Folder disappeared");
    NSDictionary *saved = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInt:CFUserID], @"UserID", CFSystemFolder, @"SystemFolder",
        [NSNumber numberWithUnsignedLongLong:directory.st_dev], @"Device",
        [NSNumber numberWithUnsignedLongLong:directory.st_ino], @"Inode", nil];
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:saved
        format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
    CFRequire(data != nil, @"Cannot encode session configuration");
    int fd = open([path fileSystemRepresentation],
                  O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    CFRequire(fd >= 0, @"Cannot save session configuration");
    @try {
        CFWriteAll(fd, [data bytes], [data length]);
        CFRequire(fsync(fd) == 0, @"Cannot sync session configuration");
    } @catch (id exception) {
        unlink([path fileSystemRepresentation]);
        @throw;
    } @finally {
        close(fd);
    }
}
void CFSessionConfigurationTests(NSString *scratch) {
    NSString *original = [CFSystemFolder copy];
    uid_t user = CFUserID;
    NSString *folder = [scratch stringByAppendingPathComponent:@"Original OS 9"],
             *other = [scratch stringByAppendingPathComponent:@"Other OS 9"],
             *journal = [scratch stringByAppendingPathComponent:@"configuration.plist"];
    CFRequire(mkdir([folder fileSystemRepresentation], 0755) == 0 &&
                  mkdir([other fileSystemRepresentation], 0755) == 0, @"Cannot prepare recovery test");
    @try {
        CFSetSystemFolder(folder);
        saveConfiguration(journal);
        CFSetSystemFolder(other);
        CFRequire(configureSession(journal) && [CFSystemFolder isEqual:folder],
                  @"Recovery followed a changed folder selection");
        BOOL refused = NO;
        @try { saveConfiguration(journal); }
        @catch (NSException *e) { (void)e; refused = YES; }
        CFRequire(refused, @"New session overwrote interrupted-session configuration");
        CFConfigureUser(getpwnam("daemon")->pw_uid);
        refused = NO;
        @try { configureSession(journal); }
        @catch (NSException *e) { (void)e; refused = YES; }
        CFConfigureUser(user);
        CFRequire(refused, @"Recovery accepted another user's session");
        NSString *moved = [folder stringByAppendingString:@" moved"];
        CFRequire(rename([folder fileSystemRepresentation], [moved fileSystemRepresentation]) == 0 &&
                      mkdir([folder fileSystemRepresentation], 0755) == 0,
                  @"Cannot prepare replacement-folder test");
        refused = NO;
        @try { configureSession(journal); }
        @catch (NSException *e) { (void)e; refused = YES; }
        CFRequire(refused, @"Recovery accepted a replacement directory at the saved path");
        CFSLog(@"PASS: recovery pins folder identity/account and preserves the interrupted-session record");
    } @finally {
        CFConfigureUser(user);
        [CFSystemFolder release];
        CFSystemFolder = original;
    }
}
static int prepareFIFO(NSString *name) {
    NSString *path = [CF_RUN stringByAppendingPathComponent:name];
    CFRequire(mkfifo([path fileSystemRepresentation], 0600) == 0 &&
                  chown([path fileSystemRepresentation], CFUserID, CFGroupID) == 0,
              @"Cannot prepare request FIFO");
    int fd = sessionFile(name, O_RDWR | O_NONBLOCK, 0);
    CFRequire(fd >= 0, @"Cannot open request FIFO");
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    return fd;
}
static void canceled(int emergency) {
    char c;
    while (CFReadable(emergency, 0) && read(emergency, &c, 1) == 1)
        if (c == 'K')
            CFFail(@"Startup canceled by F12");
    if (CFInterrupted)
        CFFail(@"Startup canceled");
}
static void finishUI(int pipe, NSString *message) {
    @try {
        int fd = sessionFile(@"session.result", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        CFRequire(fd >= 0, @"Cannot write session result");
        NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
        @try {
            CFWriteAll(fd, [data bytes], [data length]);
        } @finally {
            close(fd);
        }
        CFWriteState('Z');
        double end = CFMonotonicTime() + 2;
        while (CFMonotonicTime() < end) {
            char c;
            if (CFReadable(pipe, 0.05) && read(pipe, &c, 1) == 1 && c == 'X')
                break;
        }
    } @catch (NSException *e) {
        CFSLog(@"UI completion: %@", [e reason]);
    }
}
static uint32_t graphicsWord(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}
void CFVerifyCoreGraphics(NSData *data) {
    /* The verified mini and iBook images differ only in seven dylib build
     * timestamps. Keep the entire image fingerprint, normalizing only those
     * fields in memory. No code, versions, addresses or binding data are masked. */
    CFRequire([data length] == 4607756, @"Unsupported CoreGraphics file size");
    const unsigned char *b = [data bytes];
    CFRequire(graphicsWord(b) == MH_MAGIC && graphicsWord(b + 4) == CPU_TYPE_POWERPC &&
                  graphicsWord(b + 12) == MH_DYLIB,
              @"Expected the supported 32-bit PowerPC CoreGraphics library");
    uint32_t count = graphicsWord(b + 16), size = graphicsWord(b + 20);
    CFRequire(size <= [data length] - 28 && count > 0 && count <= size / 8,
              @"Invalid CoreGraphics load-command table");
    NSMutableData *canonical = [data mutableCopy];
    @try {
        unsigned i, off = 28, end = 28 + size, timestamps = 0, identity = 0;
        for (i = 0; i < count; i++) {
            CFRequire(end - off >= 8, @"Truncated CoreGraphics load command");
            uint32_t cmd = graphicsWord(b + off), n = graphicsWord(b + off + 4);
            CFRequire(n >= 8 && !(n & 3) && n <= end - off,
                      @"Invalid CoreGraphics load-command size");
            if (cmd == LC_ID_DYLIB || cmd == LC_LOAD_DYLIB) {
                CFRequire(n >= 24, @"Truncated CoreGraphics dylib command");
                uint32_t name = graphicsWord(b + off + 8);
                CFRequire(name >= 24 && name < n && memchr(b + off + name, 0, n - name),
                          @"Invalid CoreGraphics dylib name");
                memset((char *)[canonical mutableBytes] + off + 12, 0, 4);
                timestamps++;
                if (cmd == LC_ID_DYLIB)
                    identity++;
            }
            off += n;
        }
        CFRequire(off == end && timestamps == 7 && identity == 1,
                  @"Unsupported CoreGraphics load-command layout");
        if (![CFDigest(canonical) isEqual:@"f8e32deedfa13b4e5eb63791f951719d"])
            CFFail(@"Unsupported CoreGraphics file (MD5 %@). Its contents differ from the "
                   @"supported Tiger 258.85 build after excluding linker timestamps.", CFDigest(data));
    } @finally {
        [canonical release];
    }
}
static NSString *selectedSystemFolder(void) {
    return [[[NSString alloc]
        initWithData:CFUserOutput([NSArray arrayWithObject:@"system-folder"])
        encoding:NSUTF8StringEncoding] autorelease];
}
static void recoverBeforeLaunch(CFPatches *patches, BOOL interrupted, int emergency) {
    NSArray *names = [patches recoveryPlan];
    if (!interrupted && ![names count])
        return;
    canceled(emergency);
    if (!interrupted)
        saveConfiguration(configurationPath());
    CFSLog(@"Automatic recovery before launch: %@%@", [names componentsJoinedByString:@", "],
           interrupted ? @" (interrupted session)" : @"");
    unsigned i;
    for (i = 0; i < [names count]; i++) {
        canceled(emergency);
        [patches recover:[names objectAtIndex:i]];
    }
    [patches verifyRecovery];
    CFUserAction([NSArray arrayWithObject:@"clear-exit"], 3);
    CFRequire(CFUserAction([NSArray arrayWithObject:@"preferences-off"], 5) == 0 &&
                  CFUserAction([NSArray arrayWithObject:@"preferences-check"], 5) == 0,
              @"Cannot remove interrupted fullscreen preferences");
    CFRequire(unlink([configurationPath() fileSystemRepresentation]) == 0,
              @"Cannot remove recovered session configuration");
    CFSLog(@"Automatic recovery complete; continuing startup checks");
    /* Failure above leaves the journal and backups intact for another launch
     * or --recover. Normal install/cleanup has not begun yet. */
}
void CFPreflight(void) {
    CFRequire(geteuid() == 0, @"Preflight requires administrator access");
    CFRequireConsoleUser();
    CFEnsureSystemFolder();
    NSString *selected = selectedSystemFolder();
    CFRequire([selected isEqual:CFSystemFolder],
              @"Classic's selected System Folder changed; please start again.");
    CFRequire([CFClassicPIDs() count] == 0, @"Classic must be stopped");
    CFPatches *p = [[CFPatches alloc] initWithRoot:@""];
    @try {
        [p verifyBaseline];
    } @finally {
        [p release];
    }
    NSString *cg = @"/System/Library/Frameworks/ApplicationServices.framework/Versions/A/"
                   @"Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics";
    CFVerifyCoreGraphics(CFReadFile(cg));
    CFRequire(CFUserAction([NSArray arrayWithObject:@"preferences-check"], 5) == 0,
              @"Fullscreen or UseRealFinder preference already exists");
    CGDirectDisplayID d = CGMainDisplayID();
    CGDisplayCount displays = 0;
    CFRequire(CGGetActiveDisplayList(0, NULL, &displays) == 0 && displays == 1,
              @"This version supports one active display. Disable additional displays before starting.");
    unsigned w = CGDisplayPixelsWide(d), h = CGDisplayPixelsHigh(d),
             depth = CGDisplayBitsPerPixel(d), stride = CGDisplayBytesPerRow(d);
    CFRequire(CFSupportedDisplayDepth(depth) && w >= 640 && w <= 4096 && h >= 480 && h <= 2160 &&
                  stride >= w * (depth / 8) && stride <= 32768 && CGDisplayIsActive(d) &&
                  !CGDisplayIsCaptured(d),
              @"Display must be awake and uncaptured, at 256, Thousands, or Millions of Colors");
    CFSLog(@"Preflight passed: %ux%u, %u-bit; display settings left unchanged", w, h, depth);
}
static void stopController(pid_t *child, pid_t classic) {
    if (*child <= 0)
        return;
    kill(*child, SIGTERM);
    double end = CFMonotonicTime() + 2;
    int status;
    for (;;) {
        pid_t r = waitpid(*child, &status, WNOHANG);
        if (r == *child || (r < 0 && errno == ECHILD)) {
            *child = 0;
            return;
        }
        if (CFMonotonicTime() > end && ![CFProcessPath(classic) isEqual:CF_HOST]) {
            kill(*child, SIGKILL);
            waitpid(*child, &status, 0);
            *child = 0;
            return;
        }
        usleep(100000);
    }
}
static BOOL childExited(pid_t *child) {
    if (*child <= 0)
        return YES;
    int status;
    pid_t r = waitpid(*child, &status, WNOHANG);
    if (r == *child || (r < 0 && errno == ECHILD)) {
        *child = 0;
        return YES;
    }
    return NO;
}
static void startEmergency(pid_t classic, pid_t *watcher) {
    int readyPipe[2];
    CFRequire(pipe(readyPipe) == 0, @"Cannot prepare watcher readiness channel");
    fcntl(readyPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(readyPipe[1], F_SETFD, FD_CLOEXEC);
    @try {
        *watcher = CFSpawn(
            [NSArray arrayWithObjects:@"--emergency", [NSString stringWithFormat:@"%d", classic],
                     [CF_RUN stringByAppendingPathComponent:@"session.emergency"], nil],
            NO, readyPipe[1]);
        close(readyPipe[1]);
        readyPipe[1] = -1;
        char c = 0;
        CFRequire(CFReadable(readyPipe[0], 5) && read(readyPipe[0], &c, 1) == 1 && c == 'R',
                  @"Emergency watcher did not become ready");
    } @finally {
        close(readyPipe[0]);
        if (readyPipe[1] >= 0)
            close(readyPipe[1]);
    }
}
static void stopEmergency(pid_t *watcher) {
    if (*watcher > 0) {
        kill(*watcher, SIGTERM);
        CFWait(*watcher, 2, YES);
        *watcher = 0;
    }
}
static pid_t replacementClassic(pid_t previous, pid_t ui) {
    /* Special -> Restart exits TruBlueEnvironment and launches another copy
     * through Apple's Classic Startup app. Allow the launch gap without
     * treating the old task's death as the end of the fullscreen session. */
    double start = CFMonotonicTime(), deadline = start + 2;
    NSString *launcher = @"/System/Library/CoreServices/Classic Startup.app/Contents/MacOS/Classic Startup";
    while (!CFInterrupted && CFMonotonicTime() < deadline) {
        NSArray *pids = CFClassicPIDs();
        pid_t next = 0;
        unsigned i;
        for (i = 0; i < [pids count]; i++) {
            pid_t candidate = [[pids objectAtIndex:i] intValue];
            if (candidate != previous) {
                CFRequire(!next, @"More than one replacement Classic process");
                next = candidate;
            }
        }
        if (next)
            return next;
        CFRequire([CFProcessPath(ui) isEqual:CFExecutable], @"Native UI exited during restart");
        if ([CFProcessesAtPath(launcher) count])
            /* Keep waiting while Startup is alive, but finish promptly if it
             * exits without a replacement (for example after a force quit). */
            deadline = MIN(start + 120, CFMonotonicTime() + 2);
        usleep(100000);
    }
    return 0;
}
static void monitor(task_t task, pid_t pid, pid_t ui, pid_t *controller, pid_t *emergency) {
    CGDirectDisplayID display = CGMainDisplayID();
    unsigned width = CGDisplayPixelsWide(display), height = CGDisplayPixelsHigh(display);
    BOOL ready = NO, cursor = NO, activated = NO, mismatchReported = NO;
    int mismatch = 0;
    unsigned oldDepth = 0, oldStride = 0;
    while (CFTaskAlive(task, pid) && !CFInterrupted) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        @try {
            if (childExited(emergency) && CFTaskAlive(task, pid))
                CFFail(@"Emergency watcher exited; requesting normal shutdown");
            if (ui > 0 && ![CFProcessPath(ui) isEqual:CFExecutable])
                CFFail(@"Native UI exited; requesting normal shutdown");
            BOOL formatAvailable = NO;
            unsigned depth = 0, stride = 0, w = 0, h = 0;
            uint32_t ctx = 0;
            @try {
                ctx = CFWord(task, 0x5e0a3530);
                if (ctx) {
                    uint32_t dev = CFWord(task, CFWord(task, 0x8a4)),
                             pix = CFWord(task, CFWord(task, dev + 22));
                    unsigned char bytes[50];
                    CFReadMemory(task, pix, bytes, 50);
                    UInt16 row, dep;
                    SInt16 bounds[4];
                    memcpy(&row, bytes + 4, 2);
                    memcpy(&dep, bytes + 32, 2);
                    memcpy(bounds, bytes + 6, 8);
                    depth = dep;
                    stride = row & 0x3fff;
                    w = bounds[3] - bounds[1];
                    h = bounds[2] - bounds[0];
                    formatAvailable = YES;
                }
            } @catch (NSException *e) {
                (void)e;
            }
            if (ctx && !cursor) {
                CFRequire(CFWord(task, ctx + 360) == 1, @"Native cursor is disabled");
                cursor = YES;
                CFSLog(@"Native cursor verified");
            }
            if (formatAvailable) {
                if (depth != oldDepth || stride != oldStride) {
                    CFSLog(@"Guest format: %ux%u, depth %u, stride %u", w, h, depth, stride);
                    oldDepth = depth;
                    oldStride = stride;
                }
                if (w == width && h == height)
                    ready = YES;
                if (ready) {
                    CFRequire(!CFWord(task, 0x5e0a4420),
                              @"Graphics handoff retained an emergency image");
                }
                if (ready && !activated)
                    activated = CFUserAction([NSArray arrayWithObject:@"finder-classic"], 2) == 0;
                if (activated && !*controller) {
                    *controller = CFSpawn(
                        [NSArray arrayWithObjects:@"--controller",
                                                  [NSString stringWithFormat:@"%d", pid], nil],
                        NO, -1);
                    CFSLog(@"Controller PID %d", *controller);
                }
                BOOL valid = CFSupportedDisplayDepth(depth) && stride > 0;
                BOOL unequal = depth != CGDisplayBitsPerPixel(display) ||
                               stride != CGDisplayBytesPerRow(display);
                mismatch = ready && valid && unequal ? mismatch + 1 : 0;
                if (mismatch >= 4 && !mismatchReported) {
                    mismatchReported = YES;
                    CFSLog(@"Persistent display mismatch; requesting normal shutdown");
                    CFUserAction([NSArray arrayWithObject:@"stop"], 2);
                }
            }
            if (*controller && childExited(controller) && CFTaskAlive(task, pid))
                CFFail(@"Switch controller exited; requesting normal shutdown");
            usleep(1000000);
        } @catch (id exception) {
            /* Restart can retire the task between two reads. The next task
             * gets a fresh monitor; a dead task is not a controller failure. */
            if (!CFTaskAlive(task, pid)) {
                [pool release];
                break;
            }
            /* Tiger's exception runtime does not retain objects across a pool drain. */
            [exception retain];
            [pool release];
            [exception autorelease];
            @throw exception;
        }
        [pool release];
    }
}
int CFGuardian(pid_t ui, BOOL recovery) {
    CFRequire(geteuid() == 0, @"Guardian requires administrator access");
    CFRequireConsoleUser();
    signal(SIGTERM, stopSignal);
    signal(SIGINT, stopSignal);
    signal(SIGPIPE, SIG_IGN);
    int lock =
        open("/var/run/classic-fullscreen-session.lock", O_WRONLY | O_CREAT | O_NOFOLLOW, 0600);
    CFRequire(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0,
              @"Another fullscreen session is active");
    fcntl(lock, F_SETFD, FD_CLOEXEC);
    int request = -1, emergencyFD = -1;
    pid_t controller = 0, emergency = 0, classic = 0, uiChild = 0;
    task_t task = 0;
    BOOL prefs = NO, attempted = NO, channels = NO, launched = NO, restorationFailed = NO;
    NSString *error = nil;
    CFPatches *patches = nil;
    @try {
        CFRequire([CFClassicPIDs() count] == 0, @"Classic must be stopped");
        validateDirectory();
        cleanupChannels();
        channels = YES;
        request = prepareFIFO(@"session.request");
        emergencyFD = prepareFIFO(@"session.emergency");
        CFWriteState('P');
        if (!ui) {
            uiChild = CFSpawn([NSArray arrayWithObject:@"--ui-only"], YES, -1);
            ui = uiChild;
        } else
            CFRequire([CFProcessPath(ui) isEqual:CFExecutable] && CFProcessUserID(ui) == CFUserID,
                      @"Unexpected native UI process or account");
        double end = CFMonotonicTime() + 120;
        BOOL ready = NO;
        while (CFMonotonicTime() < end) {
            canceled(emergencyFD);
            if (CFReadable(request, 0.05)) {
                char c;
                if (read(request, &c, 1) == 1) {
                    if (c == 'S')
                        CFFail(@"Startup canceled");
                    if (c == 'Y') {
                        ready = YES;
                        break;
                    }
                }
            }
            CFRequire([CFProcessPath(ui) isEqual:CFExecutable], @"Native UI did not start");
        }
        CFRequire(ready, @"Native UI did not confirm readiness");
        CFSLog(@"Native UI ready before fullscreen");
        BOOL interrupted = configureSession(configurationPath());
        patches = [[CFPatches alloc] initWithRoot:@""];
        if (recovery) {
            attempted = YES;
            prefs = YES;
        } else {
            recoverBeforeLaunch(patches, interrupted, emergencyFD);
            if (interrupted) {
                /* Recover the recorded folder first, then honor the user's
                 * current Classic selection for this new launch. */
                NSString *selected = selectedSystemFolder();
                if (![selected isEqual:CFSystemFolder]) {
                    CFSetSystemFolder(selected);
                    [patches release];
                    patches = nil;
                    patches = [[CFPatches alloc] initWithRoot:@""];
                    recoverBeforeLaunch(patches, NO, emergencyFD);
                }
            }
            CFPreflight();
            canceled(emergencyFD);
            saveConfiguration(configurationPath());
            attempted = YES;
            [patches install:@"Resources" enabled:YES];
            canceled(emergencyFD);
            [patches install:@"Guest" enabled:YES];
            [patches install:@"Finder" enabled:YES];
            [patches install:@"Host" enabled:YES];
            canceled(emergencyFD);
            prefs = YES;
            CFRequire(CFUserAction([NSArray arrayWithObject:@"preferences-on"], 5) == 0,
                      @"Cannot enable fullscreen Finder");
            launched = YES;
            CFRequire(CFUserAction([NSArray arrayWithObject:@"open-classic"], 10) == 0,
                      @"Classic could not be launched");
            unsigned i;
            for (i = 0; i < 80; i++) {
                NSArray *pids = CFClassicPIDs();
                CFRequire([pids count] <= 1, @"More than one Classic process");
                if ([pids count]) {
                    classic = [[pids objectAtIndex:0] intValue];
                    break;
                }
                usleep(250000);
            }
            CFRequire(classic > 0, @"Classic process did not appear");
            for (;;) {
                task = CFClassicTask(classic);
                startEmergency(classic, &emergency);
                CFSLog(@"Classic PID %d, independent emergency watcher PID %d", classic, emergency);
                monitor(task, classic, ui, &controller, &emergency);
                /* An interrupted guardian still needs its watcher while the
                 * common cleanup waits for normal guest shutdown. */
                if (CFTaskAlive(task, classic))
                    break;
                stopController(&controller, classic);
                stopEmergency(&emergency);
                mach_port_deallocate(mach_task_self(), task);
                task = MACH_PORT_NULL;
                CFWriteState('P');
                pid_t next = replacementClassic(classic, ui);
                if (!next)
                    break;
                CFSLog(@"Classic restart: replacing PID %d with PID %d", classic, next);
                classic = next;
            }
            /* Keep the guardian's FIFO descriptor open across task changes.
             * It does not read while watchers own the channel: an F12 queued
             * in the launch gap is delivered to the replacement watcher. */
        }
    } @catch (NSException *e) {
        error = [[e reason] copy];
        CFSLog(@"Session: %@", error);
    }
    /* Restoration is separate from the session catch so a failure cannot skip
     * later components. Never replace any executable while a guest is alive. */
    @
    try {
        stopController(&controller, classic);
        if (launched && [CFClassicPIDs() count]) {
            CFUserAction([NSArray arrayWithObject:@"stop"], 2);
            CFSLog(@"Waiting for Classic to exit; F12 remains available");
            while ([CFClassicPIDs() count])
                usleep(250000);
        }
        stopEmergency(&emergency);
        if (attempted) {
            CFUserAction([NSArray arrayWithObject:@"clear-exit"], 3);
            NSArray *names =
                [NSArray arrayWithObjects:@"Host", @"Finder", @"Guest", @"Resources", nil];
            unsigned i;
            for (i = 0; i < [names count]; i++) {
                @try {
                    if (recovery)
                        [patches recover:[names objectAtIndex:i]];
                    else
                        [patches install:[names objectAtIndex:i] enabled:NO];
                } @catch (NSException *e) {
                    restorationFailed = YES;
                    if (!error)
                        error = [[e reason] copy];
                    CFSLog(@"Restoration failed: %@", [e reason]);
                }
            }
        }
        if (prefs && CFUserAction([NSArray arrayWithObject:@"preferences-off"], 5) != 0) {
            restorationFailed = YES;
            if (!error)
                error = [@"Cannot remove fullscreen preferences" copy];
        }
        if (attempted) {
            if (recovery)
                [patches verifyRecovery];
            else
                [patches verifyBaseline];
            if (!restorationFailed &&
                (!prefs || CFUserAction([NSArray arrayWithObject:@"preferences-check"], 5) == 0)) {
                CFRequire(unlink([configurationPath() fileSystemRepresentation]) == 0 || errno == ENOENT,
                          @"Cannot remove restored session configuration");
                CFSLog(@"RESTORED: original host, Finder, guest/resource baselines; display settings "
                      @"unchanged");
            }
        }
    } @catch (NSException *e) {
        if (!error)
            error = [[e reason] copy];
        CFSLog(@"Cleanup: %@", [e reason]);
    }
    if (channels) {
        finishUI(request,
                 error ? [NSString stringWithFormat:@"1\n%@", error] : @"0\nSession restored");
        @try {
            cleanupChannels();
        } @catch (NSException *e) {
            CFSLog(@"Channel cleanup: %@", [e reason]);
        }
    }
    if (request >= 0)
        close(request);
    if (emergencyFD >= 0)
        close(emergencyFD);
    if (task)
        mach_port_deallocate(mach_task_self(), task);
    if (uiChild)
        CFWait(uiChild, 2, NO);
    [patches release];
    close(lock);
    int status = error ? 1 : 0;
    [error release];
    return status;
}
