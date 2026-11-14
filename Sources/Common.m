#import "CFClassic.h"
#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <mach/mach_time.h>
#include <pwd.h>
#include <stdarg.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>
NSString *CFExecutable = nil;
NSString *CFResources = nil;
volatile sig_atomic_t CFInterrupted = 0;
void CFFail(NSString *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSString *s = [[[NSString alloc] initWithFormat:format arguments:ap] autorelease];
    va_end(ap);
    @throw [NSException exceptionWithName:@"ClassicFullscreen" reason:s userInfo:nil];
}
void CFSLog(NSString *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSString *s = [[[NSString alloc] initWithFormat:format arguments:ap] autorelease];
    va_end(ap);
    fprintf(stderr, "%s\n", [s UTF8String]);
    fflush(stderr);
}
void CFRequire(BOOL ok, NSString *message) {
    if (!ok)
        CFFail(@"%@", message);
}
BOOL CFSupportedDisplayDepth(unsigned depth) {
    /* Tiger framebuffer storage: indexed, 5:5:5 RGB, and 8:8:8 RGB. */
    return depth == 8 || depth == 16 || depth == 32;
}
double CFMonotonicTime(void) {
    static mach_timebase_info_data_t scale = {0, 0};
    if (!scale.denom)
        CFRequire(mach_timebase_info(&scale) == KERN_SUCCESS && scale.numer && scale.denom,
                  @"Cannot read the system elapsed-time clock");
    /* Convert in floating point: ticks * numer can overflow a 64-bit integer
     * on PowerPC. Calendar resets and network time updates must not alter the
     * controller's eligibility gates or helper/startup deadlines. */
    return (double)mach_absolute_time() * scale.numer / scale.denom / 1.0e9;
}
NSString *CFDigest(NSData *data) {
    unsigned char bytes[CC_MD5_DIGEST_LENGTH];
    char hex[33];
    unsigned i;
    CC_MD5_CTX ctx;
    CC_MD5_Init(&ctx);
    CC_MD5_Update(&ctx, [data bytes], (CC_LONG)[data length]);
    CC_MD5_Final(bytes, &ctx);
    for (i = 0; i < 16; i++)
        sprintf(hex + 2 * i, "%02x", bytes[i]);
    hex[32] = 0;
    return [NSString stringWithUTF8String:hex];
}
NSData *CFReadFile(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d)
        CFFail(@"Cannot read %@", path);
    return d;
}
void CFWriteAll(int fd, const void *p, size_t n) {
    const char *s = p;
    while (n) {
        ssize_t k = write(fd, s, n);
        if (k < 0 && errno == EINTR)
            continue;
        if (k <= 0)
            CFFail(@"Write failed: %s", strerror(errno));
        s += k;
        n -= k;
    }
}
void CFWriteState(char c) {
    NSString *tmp = [CF_RUN stringByAppendingPathComponent:@"session.state.new"];
    int fd = open([tmp fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
    CFRequire(fd >= 0, @"Cannot publish session state");
    @try {
        CFWriteAll(fd, &c, 1);
    } @finally {
        close(fd);
    }
    CFRequire(rename([tmp fileSystemRepresentation],
                     [[CF_RUN stringByAppendingPathComponent:@"session.state"]
                         fileSystemRepresentation]) == 0,
              @"Cannot commit session state");
}
char CFReadState(void) {
    char c = 0;
    int fd =
        open([[CF_RUN stringByAppendingPathComponent:@"session.state"] fileSystemRepresentation],
             O_RDONLY | O_NOFOLLOW);
    if (fd >= 0) {
        if (read(fd, &c, 1) != 1)
            c = 0;
        close(fd);
    }
    return c;
}
BOOL CFReadable(int fd, double seconds) {
    fd_set r;
    struct timeval t;
    FD_ZERO(&r);
    FD_SET(fd, &r);
    t.tv_sec = (int)seconds;
    t.tv_usec = (int)((seconds - t.tv_sec) * 1000000);
    int n = select(fd + 1, &r, NULL, NULL, &t);
    if (n < 0 && errno != EINTR)
        CFFail(@"Select failed: %s", strerror(errno));
    return n > 0;
}
NSString *CFProcessPath(pid_t pid) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS, pid};
    char args[65536];
    size_t n = sizeof(args);
    if (sysctl(mib, 3, args, &n, NULL, 0) || !n || !memchr(args, 0, n))
        return nil;
    return [NSString stringWithUTF8String:args];
}
NSArray *CFClassicPIDs(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    struct kinfo_proc *p = NULL;
    NSMutableArray *a = [NSMutableArray array];
    unsigned i;
    CFRequire(sysctl(mib, 4, NULL, &size, NULL, 0) == 0, @"Cannot size process list");
    size += 16 * sizeof(*p);
    p = malloc(size);
    CFRequire(p != NULL, @"Process list allocation failed");
    @try {
        CFRequire(sysctl(mib, 4, p, &size, NULL, 0) == 0, @"Cannot inspect process list");
        for (i = 0; i < size / sizeof(*p); i++) {
            pid_t pid = p[i].kp_proc.p_pid;
            if (pid > 1 && [CFProcessPath(pid) isEqual:CF_HOST])
                [a addObject:[NSNumber numberWithInt:pid]];
        }
    } @finally {
        free(p);
    }
    return a;
}
BOOL CFTaskAlive(task_t task, pid_t pid) {
    int current = 0;
    return task != MACH_PORT_NULL && pid_for_task(task, &current) == 0 && current == pid;
}
task_t CFClassicTask(pid_t pid) {
    task_t task = 0;
    CFRequire([CFProcessPath(pid) isEqual:CF_HOST], @"Classic process identity mismatch");
    CFRequire(task_for_pid(mach_task_self(), pid, &task) == 0, @"Cannot retain Classic task");
    if (!CFTaskAlive(task, pid) || ![CFProcessPath(pid) isEqual:CF_HOST]) {
        mach_port_deallocate(mach_task_self(), task);
        CFFail(@"Classic process changed");
    }
    return task;
}
void CFReadMemory(task_t task, uint32_t a, void *out, size_t n) {
    vm_size_t got = 0;
    CFRequire(a && n > 0 && n <= 65536, @"Invalid Classic memory read");
    kern_return_t k = vm_read_overwrite(task, a, n, (vm_address_t)out, &got);
    if (k || got != n)
        CFFail(@"Classic memory read failed (%d)", k);
}
uint32_t CFWord(task_t task, uint32_t a) {
    uint32_t v;
    CFReadMemory(task, a, &v, 4);
    return v;
}
pid_t CFSpawn(NSArray *args, BOOL asUser, int outputFD) {
    CFRequire(CFUserID != (uid_t)-1 && CFUserName != nil, @"Session user is not configured");
    NSMutableArray *childArgs = [NSMutableArray arrayWithObjects:@"--session-user",
        [NSString stringWithFormat:@"%u", (unsigned)CFUserID], nil];
    if (CFSystemFolder) {
        [childArgs addObject:@"--system-folder"];
        [childArgs addObject:CFSystemFolder];
    }
    [childArgs addObjectsFromArray:args];
    unsigned n = [childArgs count], i;
    char **av = calloc(n + 2, sizeof(char *));
    CFRequire(av != NULL, @"Argument allocation failed");
    av[0] = (char *)[CFExecutable fileSystemRepresentation];
    for (i = 0; i < n; i++)
        av[i + 1] = (char *)[[childArgs objectAtIndex:i] UTF8String];
    gid_t groups[32];
    int groupIDs[32], groupCount = 32;
    if (asUser && geteuid() == 0) {
        CFRequire(getgrouplist([CFUserName UTF8String], CFGroupID, groupIDs, &groupCount) >= 0,
                  @"Cannot resolve user groups");
        for (i = 0; i < (unsigned)groupCount; i++)
            groups[i] = (gid_t)groupIDs[i];
    }
    pid_t child = fork();
    if (child < 0) {
        free(av);
        CFFail(@"Cannot start helper: %s", strerror(errno));
    }
    if (child == 0) {
        if (outputFD >= 0 && dup2(outputFD, STDOUT_FILENO) < 0)
            _exit(126);
        /* All session locks/FIFOs are CLOEXEC. Avoid copying Cocoa state after fork. */
        if (asUser && geteuid() == 0) {
            if (setgroups(groupCount, groups) || setgid(CFGroupID) || setuid(CFUserID))
                _exit(126);
        }
        execv(av[0], av);
        _exit(127);
    }
    free(av);
    return child;
}
int CFWait(pid_t child, double seconds, BOOL terminate) {
    double end = CFMonotonicTime() + seconds;
    int status = 0;
    pid_t r;
    do {
        r = waitpid(child, &status, WNOHANG);
        if (r == child)
            return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
        if (r < 0 && errno != EINTR)
            return -1;
        usleep(20000);
    } while (seconds < 0 || CFMonotonicTime() < end);
    if (terminate) {
        kill(child, SIGTERM);
        usleep(100000);
        if (waitpid(child, &status, WNOHANG) == 0) {
            kill(child, SIGKILL);
            waitpid(child, &status, 0);
        }
    }
    return -2;
}
int CFUserAction(NSArray *args, double timeout) {
    NSMutableArray *a = [NSMutableArray arrayWithObject:@"--action"];
    [a addObjectsFromArray:args];
    return CFWait(CFSpawn(a, YES, -1), timeout, YES);
}
