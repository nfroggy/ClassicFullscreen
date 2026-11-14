#import "CFClassic.h"
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
static void guardianLog(void) {
    int fd =
        open("/var/log/ClassicFullscreen.log", O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0644);
    CFRequire(fd >= 0, @"Cannot open session log");
    struct stat s;
    CFRequire(fstat(fd, &s) == 0 && S_ISREG(s.st_mode) && s.st_uid == 0 && s.st_nlink == 1,
              @"Unsafe session log");
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    if (fd > 2)
        close(fd);
    CFSLog(@"\nNative ClassicFullscreen session %@", [NSDate date]);
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = 1;
    @try {
        char executable[4096], resolved[4096];
        uint32_t n = sizeof(executable);
        CFRequire(_NSGetExecutablePath(executable, &n) == 0 &&
                      realpath(executable, resolved) != NULL,
                  @"Cannot resolve application path");
        CFExecutable = [[NSString stringWithUTF8String:resolved] copy];
        CFResources = [[[[CFExecutable stringByDeletingLastPathComponent]
            stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Resources"] copy];
        if (geteuid() == 0)
            CFRequire(setuid(0) == 0, @"Cannot establish supervisor identity");
        NSMutableArray *args = [NSMutableArray array];
        int i;
        for (i = 1; i < argc; i++)
            if (strncmp(argv[i], "-psn_", 5))
                [args addObject:[NSString stringWithUTF8String:argv[i]]];
        uid_t user = (uid_t)-1;
        while ([args count] && ([[args objectAtIndex:0] isEqual:@"--session-user"] ||
                               [[args objectAtIndex:0] isEqual:@"--system-folder"])) {
            CFRequire([args count] >= 2, @"Missing session configuration value");
            if ([[args objectAtIndex:0] isEqual:@"--session-user"]) {
                const char *value = [[args objectAtIndex:1] UTF8String];
                char *end;
                unsigned long number = strtoul(value, &end, 10);
                CFRequire(value[0] && !*end && number > 0 && number < (uid_t)-1,
                          @"Invalid session user ID");
                user = (uid_t)number;
            } else
                CFSetSystemFolder([args objectAtIndex:1]);
            [args removeObjectsInRange:NSMakeRange(0, 2)];
        }
        CFConfigureUser(user);
        NSString *mode = [args count] ? [args objectAtIndex:0] : @"--start";
        if ([mode isEqual:@"--start"] || [mode isEqual:@"--recover"])
            result = CFUI(YES, [mode isEqual:@"--recover"]);
        else if ([mode isEqual:@"--ui-only"])
            result = CFUI(NO, NO);
        else if ([mode isEqual:@"--guardian"] || [mode isEqual:@"--guardian-recover"]) {
            guardianLog();
            result = CFGuardian([args count] > 1 ? [[args objectAtIndex:1] intValue] : 0,
                                [mode isEqual:@"--guardian-recover"]);
        } else if ([mode isEqual:@"--controller"] && [args count] == 2)
            result = CFController([[args objectAtIndex:1] intValue]);
        else if ([mode isEqual:@"--emergency"] && [args count] == 3) {
            char *emergencyArgs[] = {"--emergency", (char *)[[args objectAtIndex:1] UTF8String],
                                    (char *)[[args objectAtIndex:2] UTF8String], NULL};
            result = CFEmergency(3, emergencyArgs, CFUserID);
        }
        else if ([mode isEqual:@"--action"] && [args count] >= 2)
            result = CFActions([args subarrayWithRange:NSMakeRange(1, [args count] - 1)]);
        else if ([mode isEqual:@"--check-only"]) {
            CFPreflight();
            result = 0;
        } else if ([mode isEqual:@"--self-test"] && [args count] == 2)
            result = CFSelfTests([args objectAtIndex:1]);
        else if ([mode isEqual:@"--restore-indexed-fast2"]) {
            CFRequire(geteuid() == 0, @"Requires administrator access");
            int lock = open("/var/run/classic-fullscreen-session.lock",
                            O_WRONLY | O_CREAT | O_NOFOLLOW, 0600);
            CFRequire(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0,
                      @"Another fullscreen session is active");
            CFPatches *p = [[CFPatches alloc] initWithRoot:@""];
            @try {
                [p install:@"Indexed" enabled:NO];
            } @finally {
                [p release];
                close(lock);
            }
            result = 0;
        } else
            CFFail(@"Usage: ClassicFullscreen [--start | --recover | --check-only | --self-test "
                   @"FIXTURES]");
    } @catch (NSException *e) {
        CFSLog(@"ERROR: %@", [e reason]);
        result = 1;
    }
    [CFExecutable release];
    [CFResources release];
    [CFUserName release];
    [CFSystemFolder release];
    [pool release];
    return result;
}
