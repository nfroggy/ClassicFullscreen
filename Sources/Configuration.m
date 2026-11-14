#import "CFClassic.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>

uid_t CFUserID = (uid_t)-1;
gid_t CFGroupID = (gid_t)-1;
NSString *CFUserName = nil;
NSString *CFSystemFolder = nil;

static uid_t consoleUser(void) {
    uid_t uid = (uid_t)-1;
    CFStringRef name = SCDynamicStoreCopyConsoleUser(NULL, &uid, NULL);
    BOOL valid = name && uid != 0 && uid != (uid_t)-1 &&
                 !CFEqual(name, CFSTR("loginwindow"));
    if (name)
        CFRelease(name);
    CFRequire(valid, @"Log into the Mac's desktop before starting ClassicFullscreen.");
    return uid;
}
void CFConfigureUser(uid_t uid) {
    if (uid == (uid_t)-1)
        uid = geteuid() == 0 ? consoleUser() : getuid();
    CFRequire(uid != 0 && uid != (uid_t)-1 && (geteuid() == 0 || getuid() == uid),
              @"Invalid session user");
    struct passwd *pw = getpwuid(uid);
    CFRequire(pw && pw->pw_name && pw->pw_name[0], @"Cannot resolve the session account");
    CFUserID = uid;
    CFGroupID = pw->pw_gid;
    [CFUserName release];
    CFUserName = [[NSString alloc] initWithUTF8String:pw->pw_name];
}
void CFRequireConsoleUser(void) {
    CFRequire(consoleUser() == CFUserID,
              @"Start ClassicFullscreen from the currently logged-in desktop account.");
}
uid_t CFProcessUserID(pid_t pid) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    CFRequire(sysctl(mib, 4, &info, &size, NULL, 0) == 0 && size == sizeof(info),
              @"Cannot verify the UI process owner");
    return info.kp_eproc.e_ucred.cr_uid;
}
NSString *CFConfiguredSystemFolder(void) {
    FSRef ref;
    UInt8 path[PATH_MAX];
    /* The same Folder Manager request used by Tiger's TruBlueEnvironment. */
    OSStatus err = FSFindFolder(kClassicDomain, kSystemFolderType, false, &ref);
    if (!err)
        err = FSRefMakePath(&ref, path, sizeof(path));
    if (err)
        CFFail(@"Cannot locate the selected Classic System Folder (%ld). Select it in Classic "
               @"System Preferences first.", (long)err);
    char resolved[PATH_MAX];
    CFRequire(realpath((char *)path, resolved) != NULL, @"Classic System Folder is unavailable");
    return [NSString stringWithUTF8String:resolved];
}
void CFSetSystemFolder(NSString *folder) {
    CFRequire([folder isAbsolutePath] && [folder isEqual:[folder stringByStandardizingPath]],
              @"Invalid Classic System Folder path");
    NSString *copy = [folder copy];
    [CFSystemFolder release];
    CFSystemFolder = copy;
}
NSData *CFUserOutput(NSArray *arguments) {
    int pipeFD[2];
    CFRequire(pipe(pipeFD) == 0, @"Cannot create configuration channel");
    fcntl(pipeFD[0], F_SETFD, FD_CLOEXEC);
    fcntl(pipeFD[1], F_SETFD, FD_CLOEXEC);
    @try {
        NSMutableArray *args = [NSMutableArray arrayWithObject:@"--action"];
        [args addObjectsFromArray:arguments];
        pid_t child = CFSpawn(args, YES, pipeFD[1]);
        close(pipeFD[1]);
        pipeFD[1] = -1;
        CFRequire(CFWait(child, 5, YES) == 0, @"Cannot read the user's Classic configuration");
        /* These actions emit at most PATH_MAX bytes, below the pipe capacity. */
        char bytes[PATH_MAX];
        ssize_t n = read(pipeFD[0], bytes, sizeof(bytes));
        CFRequire(n > 0 && n < sizeof(bytes), @"Invalid configuration response");
        return [NSData dataWithBytes:bytes length:n];
    } @finally {
        close(pipeFD[0]);
        if (pipeFD[1] >= 0)
            close(pipeFD[1]);
    }
}
void CFEnsureSystemFolder(void) {
    if (CFSystemFolder)
        return;
    NSString *folder = geteuid() == 0
        ? [[[NSString alloc] initWithData:CFUserOutput([NSArray arrayWithObject:@"system-folder"])
                                encoding:NSUTF8StringEncoding] autorelease]
        : CFConfiguredSystemFolder();
    CFSetSystemFolder(folder);
}
NSString *CFFinderPath(void) {
    CFEnsureSystemFolder();
    return [CFSystemFolder stringByAppendingPathComponent:@"Finder"];
}
