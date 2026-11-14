#import "CFClassic.h"
#include <fcntl.h>
#include <errno.h>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
extern void CFControllerPolicyTests(void);
extern void CFSessionConfigurationTests(NSString *root);
extern int CFPatchFaultAfterWrites;
static void parents(NSString *path) {
    NSArray *parts = [[path stringByDeletingLastPathComponent] pathComponents];
    NSString *current = @"";
    unsigned i;
    for (i = 0; i < [parts count]; i++) {
        current = [current stringByAppendingPathComponent:[parts objectAtIndex:i]];
        mkdir([current fileSystemRepresentation], 0755);
    }
}
static void put(NSString *path, NSData *data) {
    int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0664);
    CFRequire(fd >= 0, @"Cannot prepare test fixture");
    CFWriteAll(fd, [data bytes], [data length]);
    close(fd);
}
static NSString *forkPath(CFPatches *p, NSDictionary *s) {
    NSString *path = [p pathFor:s];
    return [[s objectForKey:@"resource"] boolValue]
               ? [path stringByAppendingString:@"/..namedfork/rsrc"]
               : path;
}
static NSString *baseName(NSDictionary *s) {
    return [s objectForKey:@"prepare"] ? [s objectForKey:@"prepare"] : [s objectForKey:@"name"];
}
static void elapsedTimeTests(void) {
    double before = CFMonotonicTime();
    usleep(50000);
    double elapsed = CFMonotonicTime() - before;
    CFRequire(before >= 0 && elapsed >= 0.025 && elapsed < 5,
              @"Elapsed-time conversion does not track real seconds");
    pid_t child = fork();
    CFRequire(child >= 0, @"Cannot start helper deadline test");
    if (!child) {
        usleep(100000);
        _exit(0);
    }
    CFRequire(CFWait(child, 2, YES) == 0, @"Completed helper was timed out");
    child = fork();
    CFRequire(child >= 0, @"Cannot start stalled helper test");
    if (!child) {
        for (;;)
            pause();
    }
    before = CFMonotonicTime();
    int result = CFWait(child, 0.05, YES), status;
    elapsed = CFMonotonicTime() - before;
    CFRequire(result == -2 && elapsed >= 0.04 && elapsed < 5 &&
                  waitpid(child, &status, WNOHANG) == -1 && errno == ECHILD,
              @"Stalled helper deadline or cleanup failed");
    CFSLog(@"PASS: elapsed-time scale, completed helper and bounded stalled-helper cleanup "
           @"with calendar date %@", [NSDate date]);
}
static void graphicsIdentityTests(NSString *fixtures) {
    NSData *mini = CFReadFile([fixtures stringByAppendingPathComponent:@"CoreGraphics.mini"]),
           *ibook = CFReadFile([fixtures stringByAppendingPathComponent:@"CoreGraphics.ibook"]),
           *combo = CFReadFile([fixtures stringByAppendingPathComponent:@"CoreGraphics.combo"]);
    CFRequire([CFDigest(mini) isEqual:@"a90e0149d5afbe843cbb97dce3b10b0b"] &&
                  [CFDigest(ibook) isEqual:@"acc9d6861f7dbb3de83ec7d0c4f68067"] &&
                  [CFDigest(combo) isEqual:@"89ff11a3cd759f30e0c3b467729693d1"],
              @"Unexpected CoreGraphics test fixtures");
    CFVerifyCoreGraphics(mini);
    CFVerifyCoreGraphics(ibook);
    /* Independently identified from both supplied files, not from the parser
     * under test. Only these 28 bytes may differ. */
    const unsigned stamps[] = {0x444, 0x4dc, 0x50c, 0x53c, 0x590, 0x5f4, 0x65c};
    unsigned i;
    NSMutableData *all = [ibook mutableCopy];
    for (i = 0; i < sizeof(stamps) / sizeof(stamps[0]); i++) {
        NSMutableData *changed = [ibook mutableCopy];
        memset((char *)[changed mutableBytes] + stamps[i], 0xff, 4);
        CFVerifyCoreGraphics(changed);
        [changed release];
        memset((char *)[all mutableBytes] + stamps[i], 0, 4);
    }
    CFVerifyCoreGraphics(all);
    [all release];
    /* CPU/header, command lengths/names, versions, text, data and symbols stay
     * checked. Include the byte immediately before/after a timestamp. */
    const unsigned offsets[] = {0, 4, 12, 16, 20, 0x43c, 0x443, 0x448, 0x450,
                                0x4e0, 4108, 3915776, 4607755};
    for (i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
        NSMutableData *bad = [ibook mutableCopy];
        ((unsigned char *)[bad mutableBytes])[offsets[i]] ^= 1;
        BOOL refused = NO;
        @try { CFVerifyCoreGraphics(bad); }
        @catch (NSException *e) { (void)e; refused = YES; }
        [bad release];
        CFRequire(refused, @"Non-timestamp CoreGraphics change was accepted");
    }
    NSMutableData *zeroCommand = [ibook mutableCopy];
    memset((char *)[zeroCommand mutableBytes] + 32, 0, 4);
    NSArray *badImages = [NSArray arrayWithObjects:combo, zeroCommand,
        [ibook subdataWithRange:NSMakeRange(0, 27)], nil];
    for (i = 0; i < [badImages count]; i++) {
        BOOL refused = NO;
        @try { CFVerifyCoreGraphics([badImages objectAtIndex:i]); }
        @catch (NSException *e) { (void)e; refused = YES; }
        CFRequire(refused, @"Different or malformed CoreGraphics image was accepted");
    }
    [zeroCommand release];
    CFRequire([CFDigest(ibook) isEqual:@"acc9d6861f7dbb3de83ec7d0c4f68067"],
              @"CoreGraphics verification modified its input");
    CFSLog(@"PASS: mini/iBook CoreGraphics, seven timestamp fields, non-timestamp "
           @"changes and different/malformed builds refused; input unchanged");
}
static void resourceIdentityTests(CFPatches *p, NSString *fixtures) {
    NSDictionary *s = [p spec:@"Resources"];
    NSData *base = CFReadFile([fixtures stringByAppendingPathComponent:@"Resources.baseline"]),
           *alternate = CFReadFile([fixtures stringByAppendingPathComponent:@"Resources.alternate"]),
           *patched = CFReadFile([fixtures stringByAppendingPathComponent:@"Resources.patched"]);
    /* Actual file supplied from the second Mac, independently compared against
     * the mini's resource fork. Differences are confined to map+16..21. */
    CFRequire([CFDigest(alternate) isEqual:@"5b76825908b04392677a091741e5a9d5"],
              @"Missing second-Mac resource fixture");
    const unsigned runtime = 850429;
    NSMutableData *expected = [[patched mutableCopy] autorelease];
    [expected replaceBytesInRange:NSMakeRange(runtime, 6)
                       withBytes:(const char *)[alternate bytes] + runtime];
    CFRequire([[p transform:alternate spec:s] isEqual:expected],
              @"Second-Mac resources failed or bookkeeping bytes were changed");
    unsigned i;
    for (i = 0; i < 6; i++) {
        NSMutableData *variant = [[base mutableCopy] autorelease],
                      *want = [[patched mutableCopy] autorelease];
        ((unsigned char *)[variant mutableBytes])[runtime + i] ^= 0xff;
        ((unsigned char *)[want mutableBytes])[runtime + i] ^= 0xff;
        CFRequire([[p transform:variant spec:s] isEqual:want],
                  @"Resource-map runtime field was rejected or overwritten");
    }
    /* Headers, code/data, attributes, table offsets and names remain exact. */
    const unsigned checked[] = {0, 4, 256, 198413, 337716, 850428, 850435, 850437, 857536};
    for (i = 0; i < sizeof(checked) / sizeof(checked[0]); i++) {
        NSMutableData *bad = [[alternate mutableCopy] autorelease];
        ((unsigned char *)[bad mutableBytes])[checked[i]] ^= 1;
        BOOL refused = NO;
        @try { [p transform:bad spec:s]; }
        @catch (NSException *e) { (void)e; refused = YES; }
        CFRequire(refused, @"Change outside runtime bookkeeping was accepted");
    }
    NSString *path = forkPath(p, s),
             *backup = [[p pathFor:s] stringByAppendingString:[s objectForKey:@"backup"]];
    put(path, alternate);
    [p verifyBaseline]; /* Existing mini-form backup differs only in bookkeeping. */
    [p install:@"Resources" enabled:YES];
    [p install:@"Resources" enabled:YES];
    CFRequire([CFReadFile(path) isEqual:expected], @"Alternate resource install changed extra bytes");
    /* Simulate the Resource Manager persisting new runtime values while Classic
     * is running. Restoration must keep the current values, not the backup's. */
    NSMutableData *running = [[expected mutableCopy] autorelease],
                  *restored = [[alternate mutableCopy] autorelease];
    for (i = 0; i < 6; i++) {
        ((unsigned char *)[running mutableBytes])[runtime + i] ^= 0x5a;
        ((unsigned char *)[restored mutableBytes])[runtime + i] ^= 0x5a;
    }
    put(path, running);
    [p install:@"Resources" enabled:NO];
    [p install:@"Resources" enabled:NO];
    CFRequire([CFReadFile(path) isEqual:restored], @"Restore lost current runtime fields");
    [p verifyBaseline];
    CFRequire(unlink([backup fileSystemRepresentation]) == 0, @"Cannot reset scratch backup");
    put(path, alternate);
    [p install:@"Resources" enabled:YES];
    CFRequire([CFReadFile(backup) isEqual:alternate], @"Backup did not preserve the supplied file");
    [p install:@"Resources" enabled:NO];
    CFRequire([CFReadFile(path) isEqual:alternate], @"Second-Mac restore is not byte-exact");
    BOOL refused = NO;
    CFPatchFaultAfterWrites = 0;
    @try { [p install:@"Resources" enabled:YES]; }
    @catch (NSException *e) { (void)e; refused = YES; }
    CFPatchFaultAfterWrites = -1;
    CFRequire(refused && [CFReadFile(path) isEqual:alternate], @"Alternate resource rollback failed");
    NSMutableData *badBackup = [[alternate mutableCopy] autorelease];
    ((unsigned char *)[badBackup mutableBytes])[runtime + 6] ^= 1;
    put(backup, badBackup);
    refused = NO;
    @try { [p install:@"Resources" enabled:YES]; }
    @catch (NSException *e) { (void)e; refused = YES; }
    CFRequire(refused && [CFReadFile(path) isEqual:alternate],
              @"Corrupt resource backup was accepted or modified the target");
    put(backup, alternate);
    [p verifyBaseline];
    CFSLog(@"PASS: second-Mac resource identity, six-byte scope, exact backup/restore, "
           @"runtime-field changes, rollback and corrupt-resource/backup refusal");
}
int CFSelfTests(NSString *fixtures) {
    CFRequire(geteuid() == 0,
              @"Native fork/owner tests require root; only disposable /tmp files are written");
    elapsedTimeTests();
    char pattern[] = "/tmp/classic-native-tests-XXXXXX";
    CFRequire(mkdtemp(pattern) != NULL, @"Cannot create scratch directory");
    NSString *root = [NSString stringWithUTF8String:pattern];
    NSString *alternate = @"/Volumes/Classic Tests/OS 9's System Folder";
    CFPatches *p = [[CFPatches alloc] initWithRoot:root systemFolder:alternate];
    @try {
        CFRequire([[p pathFor:[p spec:@"Guest"]]
                      isEqual:[root stringByAppendingString:[alternate stringByAppendingPathComponent:@"Classic"]]] &&
                  [[p pathFor:[p spec:@"Host"]] isEqual:[root stringByAppendingString:CF_HOST]],
                  @"Relocated System Folder affected the host path or failed to relocate the guest");
        /* Exercise real setgroups/setgid/setuid + exec without creating an
         * account or connecting the service account to WindowServer. */
        uid_t originalUser = CFUserID;
        struct passwd *other = getpwnam("daemon");
        CFRequire(other && other->pw_uid != 0 && other->pw_uid != originalUser,
                  @"A distinct daemon account is required for the credential test");
        @try {
            CFConfigureUser(other->pw_uid);
            NSString *identity = [[[NSString alloc]
                initWithData:CFUserOutput([NSArray arrayWithObject:@"identity"])
                encoding:NSUTF8StringEncoding] autorelease];
            CFRequire([identity isEqual:[NSString stringWithFormat:@"%u %u %@",
                          (unsigned)CFUserID, (unsigned)CFGroupID, CFUserName]],
                      @"Helper did not execute as the configured account");
        } @finally {
            CFConfigureUser(originalUser);
        }
        CFSLog(@"PASS: dynamic non-console helper credentials and alternate System Folder paths");
        CFSessionConfigurationTests(root);
        NSArray *specs = [p specifications];
        unsigned i;
        for (i = 0; i < [specs count]; i++) {
            NSDictionary *s = [specs objectAtIndex:i];
            NSString *name = [s objectForKey:@"name"];
            NSData *base = CFReadFile([fixtures
                stringByAppendingPathComponent:[baseName(s) stringByAppendingString:@".baseline"]]);
            NSData *patched = CFReadFile([fixtures
                stringByAppendingPathComponent:[name stringByAppendingString:@".patched"]]);
            CFRequire([[p transform:base spec:s] isEqual:patched],
                      [@"Native transform differs from reviewed fixture: " stringByAppendingString:name]);
        }
        CFSLog(@"PASS: all five complete images match reviewed fixtures exactly");
        for (i = 0; i < 4; i++) {
            NSDictionary *s = [specs objectAtIndex:i];
            NSString *path = [p pathFor:s];
            parents(path);
            if (![[s objectForKey:@"resource"] boolValue]) {
                put(path,
                    CFReadFile([fixtures
                        stringByAppendingPathComponent:[baseName(s)
                                                           stringByAppendingString:@".baseline"]]));
                chown([path fileSystemRepresentation], CFUserID, CFGroupID);
                chmod([path fileSystemRepresentation], 0664);
                if (i != 1)
                    put([path stringByAppendingString:@"/..namedfork/rsrc"],
                        [NSData dataWithBytes:"resource-test" length:13]);
            } else
                put(forkPath(p, s),
                    CFReadFile([fixtures stringByAppendingPathComponent:@"Resources.baseline"]));
        }
        NSDictionary *guest = [p spec:@"Guest"], *indexed = [p spec:@"Indexed"];
        NSString *guestPath = [p pathFor:guest],
                 *backup = [guestPath stringByAppendingString:[guest objectForKey:@"backup"]];
        NSData *stock = CFReadFile([fixtures stringByAppendingPathComponent:@"Indexed.baseline"]),
               *optimized = CFReadFile([fixtures stringByAppendingPathComponent:@"Indexed.patched"]);
        /* Migrate the previous persistent optimization. Preserve the historical
         * optimized backup, but never use it as the new session baseline. */
        NSString *legacy = [guestPath stringByAppendingString:@".classic-isolation-original-data"];
        put(legacy, optimized);
        put([guestPath stringByAppendingString:[indexed objectForKey:@"backup"]], stock);
        put(guestPath, optimized);
        [p install:@"Indexed" enabled:NO];
        [p install:@"Indexed" enabled:NO];
        CFRequire([CFReadFile(guestPath) isEqual:stock] && [CFReadFile(legacy) isEqual:optimized],
                  @"Migration did not restore stock or changed the historical backup");
        [p verifyBaseline];
        NSArray *names = [NSArray arrayWithObjects:@"Resources", @"Guest", @"Finder", @"Host", nil];
        for (i = 0; i < [names count]; i++) {
            NSString *name = [names objectAtIndex:i];
            NSDictionary *s = [p spec:name];
            [p install:name enabled:YES];
            [p install:name enabled:YES];
            CFRequire(
                [CFReadFile(forkPath(p, s))
                    isEqual:CFReadFile([fixtures stringByAppendingPathComponent:
                                                     [name stringByAppendingString:@".patched"]])],
                @"Installer produced different image");
        }
        CFRequire([CFReadFile(backup) isEqual:stock], @"Session backup includes persistent patches");
        for (i = 0; i < [names count]; i++) {
            [p install:[names objectAtIndex:i] enabled:NO];
            [p install:[names objectAtIndex:i] enabled:NO];
        }
        [p verifyBaseline];
        CFRequire([CFReadFile(guestPath) isEqual:stock], @"Session left the indexed patch installed");
        /* An I/O failure after writing a real region must roll that fork back. */
        for (i = 0; i < 3; i++) {
            NSString *name = [names objectAtIndex:i];
            NSDictionary *s = [p spec:name];
            NSData *before = CFReadFile(forkPath(p, s));
            BOOL refused = NO;
            CFPatchFaultAfterWrites = 0;
            @try {
                [p install:name enabled:YES];
            } @catch (NSException *e) {
                (void)e;
                refused = YES;
            }
            CFPatchFaultAfterWrites = -1;
            CFRequire(refused && [CFReadFile(forkPath(p, s)) isEqual:before],
                      @"Injected failure did not roll back");
        }
        /* Fail immediately after writing the indexed copy loop, after earlier
         * fullscreen edits are already on disk. Both must roll back to stock. */
        NSArray *combined = [p writeSegmentsForSpec:guest];
        unsigned indexedOffset = [[[[indexed objectForKey:@"segments"] objectAtIndex:0]
                                      objectForKey:@"offset"] unsignedIntValue];
        BOOL crossed = NO;
        for (i = 0; i < [combined count]; i++) {
            if ([[[combined objectAtIndex:i] objectForKey:@"offset"] unsignedIntValue] != indexedOffset)
                continue;
            CFPatchFaultAfterWrites = i;
            BOOL refused = NO;
            @try {
                [p install:@"Guest" enabled:YES];
            } @catch (NSException *e) {
                (void)e;
                refused = YES;
            }
            CFPatchFaultAfterWrites = -1;
            CFRequire(refused && [CFReadFile(guestPath) isEqual:stock],
                      @"Combined indexed/fullscreen write did not roll back to stock");
            crossed = YES;
        }
        CFRequire(crossed, @"Indexed range missing from session transaction");
        CFSLog(@"PASS: persistent-indexed migration, stock session backup/restore, combined-write rollback");
        NSData *good = CFReadFile(backup);
        NSMutableData *bad = [[good mutableCopy] autorelease];
        ((char *)[bad mutableBytes])[0] ^= 1;
        put(backup, bad);
        BOOL rejected = NO;
        @try {
            [p install:@"Guest" enabled:YES];
        } @catch (NSException *e) {
            (void)e;
            rejected = YES;
        }
        CFRequire(rejected && [CFReadFile(guestPath) isEqual:good], @"Corrupt backup was accepted");
        put(backup, good);
        put(guestPath, bad);
        rejected = NO;
        @try {
            [p install:@"Guest" enabled:YES];
        } @catch (NSException *e) {
            (void)e;
            rejected = YES;
        }
        CFRequire(rejected && [CFReadFile(guestPath) isEqual:bad], @"Unknown target was modified");
        put(guestPath, good);
        CFSLog(@"PASS: native fork install/restore/idempotence, ownership preservation, rollback, "
              @"corrupt-backup and unknown-image refusal");
        resourceIdentityTests(p, fixtures);
        graphicsIdentityTests(fixtures);
        CFControllerPolicyTests();
    } @finally {
        CFPatchFaultAfterWrites = -1;
        [p release];
        [[NSFileManager defaultManager] removeFileAtPath:root handler:nil];
    }
    return 0;
}
