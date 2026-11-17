#import "CFClassic.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
extern int CFPatchFaultAfterWrites;

static void put(NSString *path, NSData *data) {
    int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0664);
    CFRequire(fd >= 0, @"Cannot prepare recovery fixture");
    CFWriteAll(fd, [data bytes], [data length]);
    close(fd);
}
static void refused(CFPatches *p, NSString *name, NSString *fork, NSData *before) {
    BOOL failed = NO;
    @try { [p recover:name]; }
    @catch (NSException *e) { (void)e; failed = YES; }
    CFRequire(failed && [CFReadFile(fork) isEqual:before],
              @"Rejected recovery wrote the destination or unexpectedly succeeded");
}
static FSCatalogInfo catalog(NSString *path) {
    FSRef ref;
    FSCatalogInfo info;
    CFRequire(FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], &ref, NULL) == 0 &&
                  FSGetCatalogInfo(&ref, kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo,
                                   &info, NULL, NULL, NULL) == 0,
              @"Cannot inspect recovery fixture's Finder metadata");
    return info;
}
static NSString *targetFork(CFPatches *p, NSDictionary *s) {
    NSString *path = [p pathFor:s];
    return [[s objectForKey:@"resource"] boolValue]
        ? [path stringByAppendingString:@"/..namedfork/rsrc"] : path;
}
static void automaticRecoveryTests(CFPatches *p, NSString *fixtures) {
    NSArray *names = [NSArray arrayWithObjects:@"Host", @"Finder", @"Guest", @"Resources", nil];
    NSMutableArray *originals = [NSMutableArray array], *previous = [NSMutableArray array];
    unsigned i;
    CFRequire([[p recoveryPlan] count] == 0, @"Stock files requested automatic recovery");
    /* A first installation has no backups yet and must still be accepted. */
    for (i = 0; i < [names count]; i++) {
        NSDictionary *s = [p spec:[names objectAtIndex:i]];
        NSString *backup = [[p pathFor:s] stringByAppendingString:[s objectForKey:@"backup"]];
        [originals addObject:CFReadFile(backup)];
        CFRequire(rename([backup fileSystemRepresentation],
                         [[backup stringByAppendingString:@".held"] fileSystemRepresentation]) == 0,
                  @"Cannot hold first-launch backup");
    }
    CFRequire([[p recoveryPlan] count] == 0, @"First launch required pre-existing backups");
    for (i = 0; i < [names count]; i++) {
        NSDictionary *s = [p spec:[names objectAtIndex:i]];
        NSString *backup = [[p pathFor:s] stringByAppendingString:[s objectForKey:@"backup"]];
        CFRequire(rename([[backup stringByAppendingString:@".held"] fileSystemRepresentation],
                         [backup fileSystemRepresentation]) == 0, @"Cannot restore held backup");
        NSData *data = CFReadFile([fixtures stringByAppendingPathComponent:
            [[names objectAtIndex:i] stringByAppendingString:@".previous"]]);
        if (i == 3) data = [data subdataWithRange:NSMakeRange(0, 17)];
        [previous addObject:data];
        put(targetFork(p, s), data);
    }
    NSArray *plan = [p recoveryPlan];
    CFRequire([[NSSet setWithArray:plan] isEqual:[NSSet setWithArray:names]],
              @"Older and truncated files were missed by automatic recovery");
    /* Even a bad LAST backup must abort the entire plan before any write. */
    NSDictionary *last = [p spec:@"Resources"];
    NSString *backup = [[p pathFor:last] stringByAppendingString:[last objectForKey:@"backup"]];
    put(backup, [NSData dataWithBytes:"bad" length:3]);
    BOOL failed = NO;
    @try { [p recoveryPlan]; }
    @catch (NSException *e) { (void)e; failed = YES; }
    CFRequire(failed, @"Automatic recovery accepted an invalid backup");
    unlink([backup fileSystemRepresentation]);
    failed = NO;
    @try { [p recoveryPlan]; }
    @catch (NSException *e) { (void)e; failed = YES; }
    CFRequire(failed, @"Automatic recovery accepted a missing required backup");
    for (i = 0; i < [names count]; i++)
        CFRequire([CFReadFile(targetFork(p, [p spec:[names objectAtIndex:i]]))
                      isEqual:[previous objectAtIndex:i]], @"Recovery planning modified a target");
    put(backup, [originals objectAtIndex:3]);
    plan = [p recoveryPlan];
    for (i = 0; i < [plan count]; i++) [p recover:[plan objectAtIndex:i]];
    [p verifyBaseline];
    /* After recovery the real current installer can run, and an interrupted
     * current release is recoverable through the same startup path. */
    for (i = 0; i < [names count]; i++) [p install:[names objectAtIndex:i] enabled:YES];
    CFRequire([[NSSet setWithArray:[p recoveryPlan]] isEqual:[NSSet setWithArray:names]],
              @"Current patches were not scheduled for recovery");
    for (i = 0; i < [names count]; i++) [p recover:[names objectAtIndex:i]];
    [p verifyBaseline];
    /* Mixed stock/unknown state restores only the component that needs it. */
    NSString *guest = targetFork(p, [p spec:@"Guest"]);
    put(guest, [NSData data]);
    plan = [p recoveryPlan];
    CFRequire([plan isEqual:[NSArray arrayWithObject:@"Guest"]],
              @"Mixed files scheduled unnecessary recovery writes");
    [p recover:[plan objectAtIndex:0]];
    [p verifyBaseline];
    /* Bad existing backups still fail on stock files, without triggering a
     * blind attempt to recover in response to any preflight exception. */
    put(backup, [NSData data]);
    failed = NO;
    @try { [p recoveryPlan]; }
    @catch (NSException *e) { (void)e; failed = YES; }
    CFRequire(failed, @"Stock target hid an invalid existing backup");
    put(backup, [originals objectAtIndex:3]);
    NSString *resources = CFResources;
    @try {
        CFResources = @"/no-current-patch-payloads-for-automatic-recovery-test";
        CFRequire([[p recoveryPlan] count] == 0,
                  @"A missing payload triggered automatic file recovery");
        failed = NO;
        @try { [p verifyBaseline]; }
        @catch (NSException *e) { (void)e; failed = YES; }
        CFRequire(failed, @"Startup no longer verifies patch payloads after recovery");
    } @finally { CFResources = resources; }
    [p verifyBaseline];
    CFSLog(@"PASS: automatic recovery: first launch, stock/mixed/old/current patches, "
           "all-backup validation before writes, continued installation and independent payload checks");
}
void CFRecoveryTests(CFPatches *p, NSString *fixtures) {
    NSArray *names = [NSArray arrayWithObjects:@"Host", @"Finder", @"Guest", @"Resources", nil];
    unsigned i, j;
    for (i = 0; i < [names count]; i++) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *name = [names objectAtIndex:i];
        NSDictionary *s = [p spec:name];
        NSString *path = [p pathFor:s],
                 *backup = [path stringByAppendingString:[s objectForKey:@"backup"]];
        BOOL resource = [[s objectForKey:@"resource"] boolValue],
             atomic = [[s objectForKey:@"atomic"] boolValue];
        NSString *fork = resource ? [path stringByAppendingString:@"/..namedfork/rsrc"] : path,
                 *other = resource ? path : [path stringByAppendingString:@"/..namedfork/rsrc"];
        NSData *original = CFReadFile(backup);
        NSData *historical = CFReadFile([fixtures stringByAppendingPathComponent:
            [name stringByAppendingString:@".previous"]]);
        NSMutableData *partial = [[original mutableCopy] autorelease];
        NSData *patched = [p transform:original spec:s];
        [partial replaceBytesInRange:NSMakeRange(0, [partial length] / 2)
                           withBytes:[patched bytes]];
        /* A change outside every current patch range must also be removed.
         * For resources this corrupts the header: no current map can be parsed. */
        NSMutableData *unrecognized = [[original mutableCopy] autorelease];
        ((unsigned char *)[unrecognized mutableBytes])[4] ^= 0x80;
        ((unsigned char *)[unrecognized mutableBytes])[[unrecognized length] - 1] ^= 1;
        NSMutableData *extended = [[unrecognized mutableCopy] autorelease];
        [extended appendBytes:"old trailer" length:11];
        NSArray *cases = [NSArray arrayWithObjects:historical, partial, unrecognized,
            [unrecognized subdataWithRange:NSMakeRange(0, 17)], [NSData data], extended, nil];
        if (!atomic) {
            FSRef ref;
            FSCatalogInfo info = catalog(path);
            memcpy(info.finderInfo, "TESTClSw", 8);
            CFRequire(FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], &ref, NULL) == 0 &&
                          FSSetCatalogInfo(&ref, kFSCatInfoFinderInfo, &info) == 0,
                      @"Cannot set recovery fixture's Finder metadata");
        }
        for (j = 0; j < [cases count]; j++) {
            put(fork, [cases objectAtIndex:j]);
            struct stat before, after;
            CFRequire(stat([path fileSystemRepresentation], &before) == 0, @"Missing test target");
            FSCatalogInfo saved = catalog(path);
            NSData *otherBytes = atomic ? nil : CFReadFile(other);
            [p recover:name];
            [p recover:name];
            CFRequire([CFReadFile(fork) isEqual:original] && [CFReadFile(backup) isEqual:original],
                      @"Recovery did not restore the complete backup byte-for-byte");
            CFRequire(stat([path fileSystemRepresentation], &after) == 0 &&
                          before.st_uid == after.st_uid && before.st_gid == after.st_gid &&
                          before.st_mode == after.st_mode, @"Recovery changed ownership or mode");
            if (!atomic) {
                FSCatalogInfo restored = catalog(path);
                CFRequire(before.st_ino == after.st_ino && before.st_dev == after.st_dev &&
                              [CFReadFile(other) isEqual:otherBytes] &&
                              !memcmp(saved.finderInfo, restored.finderInfo, 16) &&
                              !memcmp(saved.extFinderInfo, restored.extFinderInfo, 16),
                          @"Recovery changed HFS identity, Finder metadata or the other fork");
            }
        }
        /* Installation and ordinary cleanup retain their strict image checks. */
        put(fork, unrecognized);
        BOOL rejected = NO;
        @try { [p install:name enabled:YES]; }
        @catch (NSException *e) { (void)e; rejected = YES; }
        CFRequire(rejected && [CFReadFile(fork) isEqual:unrecognized],
                  @"Recovery weakened installation checks");
        NSString *held = [backup stringByAppendingString:@".held"];
        CFRequire(rename([backup fileSystemRepresentation], [held fileSystemRepresentation]) == 0,
                  @"Cannot hold test backup");
        refused(p, name, fork, unrecognized); /* Missing backup. */
        CFRequire(symlink([held fileSystemRepresentation], [backup fileSystemRepresentation]) == 0,
                  @"Cannot create linked backup fixture");
        refused(p, name, fork, unrecognized);
        unlink([backup fileSystemRepresentation]);
        CFRequire(rename([held fileSystemRepresentation], [backup fileSystemRepresentation]) == 0,
                  @"Cannot restore test backup");
        CFRequire(link([backup fileSystemRepresentation], [held fileSystemRepresentation]) == 0,
                  @"Cannot create hard-linked backup fixture");
        refused(p, name, fork, unrecognized);
        unlink([held fileSystemRepresentation]);
        NSMutableData *bad = [[original mutableCopy] autorelease];
        ((unsigned char *)[bad mutableBytes])[0] ^= 1;
        put(backup, bad);
        refused(p, name, fork, unrecognized);
        CFRequire([CFReadFile(backup) isEqual:bad], @"Recovery overwrote an invalid backup");
        put(backup, [original subdataWithRange:NSMakeRange(0, 7)]);
        refused(p, name, fork, unrecognized);
        put(backup, original);
        /* Reject unsafe destinations even when their original backups are valid. */
        held = [path stringByAppendingString:@".held"];
        CFRequire(rename([path fileSystemRepresentation], [held fileSystemRepresentation]) == 0 &&
                      symlink([held fileSystemRepresentation], [path fileSystemRepresentation]) == 0,
                  @"Cannot create linked destination fixture");
        refused(p, name, fork, unrecognized);
        unlink([path fileSystemRepresentation]);
        CFRequire(rename([held fileSystemRepresentation], [path fileSystemRepresentation]) == 0 &&
                      link([path fileSystemRepresentation], [held fileSystemRepresentation]) == 0,
                  @"Cannot create hard-linked destination fixture");
        refused(p, name, fork, unrecognized);
        unlink([held fileSystemRepresentation]);
        /* Interrupt the first 64K write. Atomic host replacement must leave its
         * old destination intact; an in-place fork can be retried from backup. */
        put(fork, extended);
        rejected = NO;
        CFPatchFaultAfterWrites = 0;
        @try { [p recover:name]; }
        @catch (NSException *e) { (void)e; rejected = YES; }
        CFPatchFaultAfterWrites = -1;
        CFRequire(rejected && [CFReadFile(backup) isEqual:original] &&
                      (!atomic || [CFReadFile(fork) isEqual:extended]),
                  @"Failed recovery damaged its backup or committed an incomplete host");
        [p recover:name];
        CFRequire([CFReadFile(fork) isEqual:original], @"Interrupted recovery could not be retried");
        CFSLog(@"PASS: %@ recovery: historical/partial/unknown/truncated/empty/extended images; "
               @"metadata, backup/link refusals and interrupted-write retry", name);
        [pool release];
    }
    /* Recovery and its final verification need no current .bin payloads. */
    NSString *resources = CFResources;
    @try {
        CFResources = @"/no-current-patch-payloads-for-recovery-test";
        for (i = 0; i < [names count]; i++)
            [p recover:[names objectAtIndex:i]];
        [p verifyRecovery];
    } @finally {
        CFResources = resources;
    }
    CFSLog(@"PASS: recovery and stock verification are independent of current patch payloads");
    automaticRecoveryTests(p, fixtures);
}
