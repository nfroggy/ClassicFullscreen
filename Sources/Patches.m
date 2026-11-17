#import "CFClassic.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
static struct stat metadata(NSString *path) {
    struct stat s;
    CFRequire(lstat([path fileSystemRepresentation], &s) == 0 && S_ISREG(s.st_mode) &&
                  s.st_nlink == 1,
              [NSString stringWithFormat:@"Expected a regular, single-link file: %@", path]);
    return s;
}
static BOOL sameIdentity(struct stat a, struct stat b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode &&
           a.st_uid == b.st_uid && a.st_gid == b.st_gid && a.st_nlink == b.st_nlink;
}
static BOOL same(struct stat a, struct stat b) {
    return sameIdentity(a, b) && a.st_size == b.st_size;
}
static BOOL entry(NSString *p) {
    struct stat s;
    return lstat([p fileSystemRepresentation], &s) == 0;
}
static unsigned resourceMapOffset(NSData *data, NSDictionary *s) {
    unsigned map = [[s objectForKey:@"resourceMapOffset"] unsignedIntValue];
    CFRequire([[s objectForKey:@"name"] isEqual:@"Resources"] &&
                  [data length] == [[s objectForKey:@"length"] unsignedIntValue] &&
                  map >= 16 && map <= [data length] && [data length] - map >= 28,
              @"Unsupported Classic resource-map layout");
    const unsigned char *b = [data bytes];
    unsigned actual = ((unsigned)b[4] << 24) | ((unsigned)b[5] << 16) |
                      ((unsigned)b[6] << 8) | b[7];
    CFRequire(actual == map, @"Unsupported Classic resource-map offset");
    return map;
}
static NSData *identityBytes(NSData *data, NSDictionary *s) {
    if (![[s objectForKey:@"resource"] boolValue])
        return data;
    unsigned map = resourceMapOffset(data, s);
    /* Resource Manager's next-map handle and open-file reference number are
     * runtime bookkeeping, sometimes persisted by Tiger's support-file update.
     * Normalize ONLY these six bytes for identity; never write them to disk.
     * All resource data, attributes, names, offsets and other map bytes retain
     * the exact reviewed fingerprint. */
    NSMutableData *result = [[data mutableCopy] autorelease];
    memset((char *)[result mutableBytes] + map + 16, 0, 6);
    return result;
}
static NSString *imageDigest(NSData *data, NSDictionary *s) {
    return CFDigest(identityBytes(data, s));
}
static NSString *expectedDigest(NSDictionary *s, BOOL patched) {
    NSString *key = [[s objectForKey:@"resource"] boolValue]
        ? (patched ? @"normalizedPatchedMD5" : @"normalizedBaseMD5")
        : (patched ? @"patchedMD5" : @"baseMD5");
    NSString *value = [s objectForKey:key];
    CFRequire([value length] == 32, @"Missing image fingerprint");
    return value;
}
static BOOL sameImage(NSData *a, NSData *b, NSDictionary *s) {
    return [identityBytes(a, s) isEqual:identityBytes(b, s)];
}
static NSData *preserveRuntimeMap(NSData *replacement, NSData *current, NSDictionary *s) {
    if (![[s objectForKey:@"resource"] boolValue])
        return replacement;
    unsigned map = resourceMapOffset(current, s);
    CFRequire(resourceMapOffset(replacement, s) == map, @"Resource-map layout changed");
    NSMutableData *result = [[replacement mutableCopy] autorelease];
    [result replaceBytesInRange:NSMakeRange(map + 16, 6)
                     withBytes:(const char *)[current bytes] + map + 16];
    return result;
}
static void newBackup(NSString *path, NSData *data, struct stat s) {
    int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    CFRequire(fd >= 0, @"Cannot create verified backup");
    @try {
        CFWriteAll(fd, [data bytes], [data length]);
        CFRequire(fchown(fd, s.st_uid, s.st_gid) == 0 && fchmod(fd, s.st_mode & 07777) == 0 &&
                      fsync(fd) == 0,
                  @"Cannot finish backup");
    } @catch (id e) {
        close(fd);
        unlink([path fileSystemRepresentation]);
        @throw;
    }
    close(fd);
    CFRequire([CFReadFile(path) isEqual:data], @"Backup verification failed");
}
int CFPatchFaultAfterWrites = -1; /* Used only by --self-test on disposable files. */
static void writeFault(void) {
    if (CFPatchFaultAfterWrites == 0) {
        CFPatchFaultAfterWrites = -1;
        CFFail(@"Injected write failure");
    }
    if (CFPatchFaultAfterWrites > 0)
        CFPatchFaultAfterWrites--;
}
static void writeRanges(int fd, NSData *data, NSArray *ranges) {
    unsigned i;
    for (i = 0; i < [ranges count]; i++) {
        NSDictionary *r = [ranges objectAtIndex:i];
        unsigned a = [[r objectForKey:@"offset"] unsignedIntValue],
                 n = [[r objectForKey:@"length"] unsignedIntValue];
        CFRequire(lseek(fd, a, SEEK_SET) == a, @"Patch seek failed");
        CFWriteAll(fd, (const char *)[data bytes] + a, n);
        writeFault();
    }
    CFRequire(fsync(fd) == 0, @"Patch sync failed");
}
static NSData *recoveryBackup(NSString *path, NSDictionary *s) {
    struct stat before = metadata(path), opened;
    CFRequire(before.st_size == [[s objectForKey:@"length"] unsignedIntValue],
              @"Invalid original backup length");
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW);
    CFRequire(fd >= 0, @"Cannot open original backup");
    NSMutableData *data = [NSMutableData dataWithLength:(unsigned)before.st_size];
    @try {
        CFRequire(fstat(fd, &opened) == 0 && same(before, opened), @"Original backup changed");
        size_t offset = 0;
        while (offset < [data length]) {
            ssize_t n = read(fd, (char *)[data mutableBytes] + offset, [data length] - offset);
            if (n < 0 && errno == EINTR) continue;
            CFRequire(n > 0, @"Cannot read original backup");
            offset += n;
        }
        CFRequire(fstat(fd, &opened) == 0 && same(before, opened) &&
                      [imageDigest(data, s) isEqual:expectedDigest(s, NO)],
                  @"Invalid original backup");
    } @finally {
        close(fd);
    }
    return data;
}
static void writeRecovery(int fd, NSData *data) {
    CFRequire(lseek(fd, 0, SEEK_SET) == 0, @"Recovery seek failed");
    unsigned offset = 0;
    while (offset < [data length]) {
        unsigned n = MIN(65536U, [data length] - offset);
        CFWriteAll(fd, (const char *)[data bytes] + offset, n);
        writeFault();
        offset += n;
    }
    CFRequire(ftruncate(fd, [data length]) == 0 && fsync(fd) == 0, @"Recovery sync failed");
}
@implementation CFPatches
- (id)initWithRoot:(NSString *)prefix {
    CFEnsureSystemFolder();
    return [self initWithRoot:prefix systemFolder:CFSystemFolder];
}
- (id)initWithRoot:(NSString *)prefix systemFolder:(NSString *)folder {
    if ((self = [super init])) {
        root = [prefix copy];
        CFRequire([folder isAbsolutePath], @"Classic System Folder must be an absolute path");
        systemFolder = [folder copy];
        specs = [[NSArray
            arrayWithContentsOfFile:[CFResources
                                        stringByAppendingPathComponent:@"Patches/Manifest.plist"]]
            retain];
        CFRequire([specs count] == 5, @"Missing patch manifest");
    }
    return self;
}
- (void)dealloc {
    [root release];
    [systemFolder release];
    [specs release];
    [super dealloc];
}
- (NSArray *)specifications {
    return specs;
}
- (NSDictionary *)spec:(NSString *)name {
    unsigned i;
    for (i = 0; i < [specs count]; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        if ([[s objectForKey:@"name"] isEqual:name])
            return s;
    }
    CFFail(@"Unknown patch %@", name);
}
- (NSString *)pathFor:(NSDictionary *)s {
    NSString *path = [s objectForKey:@"path"];
    if ([[s objectForKey:@"name"] isEqual:@"Host"])
        CFRequire([path isEqual:CF_HOST], @"Unexpected host path in patch manifest");
    else {
        CFRequire([path isEqual:@"Classic"] || [path isEqual:@"Finder"],
                  @"Unexpected guest filename in patch manifest");
        path = [systemFolder stringByAppendingPathComponent:path];
    }
    return [root stringByAppendingString:path];
}
- (NSDictionary *)preparationForSpec:(NSDictionary *)s {
    NSString *name = [s objectForKey:@"prepare"];
    if (!name)
        return nil;
    CFRequire([[s objectForKey:@"name"] isEqual:@"Guest"] && [name isEqual:@"Indexed"],
              @"Unsupported patch composition");
    NSDictionary *p = [self spec:name];
    CFRequire(![p objectForKey:@"prepare"] &&
                  [[s objectForKey:@"path"] isEqual:[p objectForKey:@"path"]] &&
                  [[s objectForKey:@"length"] isEqual:[p objectForKey:@"length"]] &&
                  [[s objectForKey:@"baseMD5"] isEqual:[p objectForKey:@"baseMD5"]] &&
                  ![[s objectForKey:@"resource"] boolValue] &&
                  ![[p objectForKey:@"resource"] boolValue],
              @"Incompatible patch composition");
    return p;
}
- (NSArray *)writeSegmentsForSpec:(NSDictionary *)s {
    NSMutableArray *ranges = [NSMutableArray arrayWithArray:[s objectForKey:@"segments"]];
    NSDictionary *preparation = [self preparationForSpec:s];
    if (preparation)
        [ranges addObjectsFromArray:[preparation objectForKey:@"segments"]];
    NSSortDescriptor *order =
        [[[NSSortDescriptor alloc] initWithKey:@"offset" ascending:YES] autorelease];
    [ranges sortUsingDescriptors:[NSArray arrayWithObject:order]];
    unsigned i, end = 0, length = [[s objectForKey:@"length"] unsignedIntValue];
    for (i = 0; i < [ranges count]; i++) {
        NSDictionary *r = [ranges objectAtIndex:i];
        unsigned a = [[r objectForKey:@"offset"] unsignedIntValue],
                 n = [[r objectForKey:@"length"] unsignedIntValue];
        CFRequire(n && a >= end && a <= length && n <= length - a,
                  @"Overlapping or invalid combined patch ranges");
        if ([[s objectForKey:@"resource"] boolValue]) {
            unsigned runtime = [[s objectForKey:@"resourceMapOffset"] unsignedIntValue] + 16;
            CFRequire(a + n <= runtime || a >= runtime + 6,
                      @"Patch overlaps resource-map runtime fields");
        }
        end = a + n;
    }
    return ranges;
}
- (NSData *)transform:(NSData *)base spec:(NSDictionary *)s {
    if ([base length] != [[s objectForKey:@"length"] unsignedIntValue] ||
        ![imageDigest(base, s) isEqual:expectedDigest(s, NO)])
        CFFail(@"Unsupported %@ file: %@ (MD5 %@). This build requires MD5 %@.",
               [s objectForKey:@"name"], [self pathFor:s], CFDigest(base), [s objectForKey:@"baseMD5"]);
    [self writeSegmentsForSpec:s];
    NSDictionary *preparation = [self preparationForSpec:s];
    NSData *prepared = preparation ? [self transform:base spec:preparation] : base;
    NSData *payload = CFReadFile(
        [CFResources stringByAppendingPathComponent:
                         [@"Patches" stringByAppendingPathComponent:[s objectForKey:@"payload"]]]);
    CFRequire([CFDigest(payload) isEqual:[s objectForKey:@"payloadMD5"]],
              @"Patch payload is corrupt");
    NSMutableData *result = [[prepared mutableCopy] autorelease];
    NSArray *ranges = [s objectForKey:@"segments"];
    unsigned i, end = 0;
    for (i = 0; i < [ranges count]; i++) {
        NSDictionary *r = [ranges objectAtIndex:i];
        unsigned a = [[r objectForKey:@"offset"] unsignedIntValue],
                 n = [[r objectForKey:@"length"] unsignedIntValue],
                 p = [[r objectForKey:@"payloadOffset"] unsignedIntValue];
        CFRequire(n > 0 && a >= end && a <= [base length] && n <= [base length] - a &&
                      p <= [payload length] && n <= [payload length] - p,
                  @"Invalid patch bounds");
        [result replaceBytesInRange:NSMakeRange(a, n) withBytes:(const char *)[payload bytes] + p];
        end = a + n;
    }
    CFRequire([imageDigest(result, s) isEqual:expectedDigest(s, YES)],
              @"Patched image verification failed");
    return result;
}
- (void)verifyRecovery {
    unsigned i;
    for (i = 0; i < 4; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        NSString *path = [self pathFor:s];
        metadata(path);
        NSString *fork = [[s objectForKey:@"resource"] boolValue]
                             ? [path stringByAppendingString:@"/..namedfork/rsrc"]
                             : path;
        NSData *d = CFReadFile(fork);
        CFRequire([d length] == [[s objectForKey:@"length"] unsignedIntValue] &&
                      [imageDigest(d, s) isEqual:expectedDigest(s, NO)],
                  [@"File is not stock: " stringByAppendingString:path]);
        NSString *backup = [path stringByAppendingString:[s objectForKey:@"backup"]];
        if (entry(backup)) {
            metadata(backup);
            CFRequire(sameImage(CFReadFile(backup), d, s), @"Existing backup does not match baseline");
        }
    }
}
- (void)verifyBaseline {
    [self verifyRecovery];
    unsigned i;
    for (i = 0; i < 4; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        NSString *path = [self pathFor:s];
        if ([[s objectForKey:@"resource"] boolValue])
            path = [path stringByAppendingString:@"/..namedfork/rsrc"];
        [self transform:CFReadFile(path) spec:s];
    }
}
- (NSArray *)recoveryPlan {
    /* Read-only: validate every required backup before restoring any component.
     * Stock files need no backup on a first launch. Existing backups must still
     * be valid, even when their destination happens to be stock. */
    NSMutableArray *names = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < 4; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        NSString *path = [self pathFor:s];
        metadata(path);
        NSString *fork = [[s objectForKey:@"resource"] boolValue]
            ? [path stringByAppendingString:@"/..namedfork/rsrc"] : path;
        NSData *current = CFReadFile(fork);
        BOOL stock = NO;
        if ([current length] == [[s objectForKey:@"length"] unsignedIntValue]) {
            @try { stock = [imageDigest(current, s) isEqual:expectedDigest(s, NO)]; }
            @catch (NSException *e) {
                /* A damaged resource-map header is recoverable too. This
                 * catches only content inspection, never filesystem checks. */
                (void)e;
            }
        }
        NSString *backup = [path stringByAppendingString:[s objectForKey:@"backup"]];
        if (!stock || entry(backup))
            recoveryBackup(backup, s);
        if (!stock)
            [names addObject:[s objectForKey:@"name"]];
    }
    return names;
}
- (void)recover:(NSString *)name {
    if (![root length])
        CFRequire([CFClassicPIDs() count] == 0, @"Classic must be stopped before recovery");
    NSDictionary *s = [self spec:name];
    NSString *path = [self pathFor:s],
             *backup = [path stringByAppendingString:[s objectForKey:@"backup"]];
    /* Only the backup's stock identity authorizes recovery. Do not inspect the
     * destination's contents, patched hash, resource header or patch ranges.
     * Old releases and interrupted writes can differ at any byte or length. */
    NSData *original = recoveryBackup(backup, s);
    struct stat before = metadata(path);
    BOOL resource = [[s objectForKey:@"resource"] boolValue];
    NSString *fork = resource ? [path stringByAppendingString:@"/..namedfork/rsrc"] : path;
    if ([[s objectForKey:@"atomic"] boolValue]) {
        NSString *pattern = [[path stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@".classic-recover-XXXXXX"];
        char *tmp = strdup([pattern fileSystemRepresentation]);
        CFRequire(tmp != NULL, @"Cannot allocate recovery path");
        int fd = mkstemp(tmp);
        @try {
            CFRequire(fd >= 0, @"Cannot create recovered host image");
            writeRecovery(fd, original);
            CFRequire(fchown(fd, before.st_uid, before.st_gid) == 0 &&
                          fchmod(fd, before.st_mode & 07777) == 0 && fsync(fd) == 0,
                      @"Cannot preserve recovered host permissions");
            close(fd);
            fd = -1;
            CFRequire([CFReadFile([NSString stringWithUTF8String:tmp]) isEqual:original] &&
                          same(before, metadata(path)), @"Recovery target changed");
            if (![root length])
                CFRequire([CFClassicPIDs() count] == 0, @"Classic started during recovery");
            CFRequire(rename(tmp, [path fileSystemRepresentation]) == 0,
                      @"Cannot commit recovered host image");
        } @finally {
            if (fd >= 0) close(fd);
            unlink(tmp);
            free(tmp);
        }
    } else {
        /* Preserve the HFS file ID, Finder metadata and the other fork. A
         * failed write leaves the verified backup intact for a full retry. */
        int fd = open([fork fileSystemRepresentation], O_WRONLY | O_NOFOLLOW);
        CFRequire(fd >= 0, @"Cannot open recovery target fork");
        @try {
            struct stat opened;
            CFRequire(fstat(fd, &opened) == 0 && sameIdentity(before, opened) &&
                          same(before, metadata(path)), @"Recovery target changed");
            if (![root length])
                CFRequire([CFClassicPIDs() count] == 0, @"Classic started during recovery");
            writeRecovery(fd, original);
            CFRequire(sameIdentity(before, metadata(path)), @"Recovery changed file identity");
        } @finally {
            close(fd);
        }
    }
    CFRequire([CFReadFile(fork) isEqual:original], @"Recovery verification failed");
    CFSLog(@"%@: recovered from verified original backup (%@)", name, CFDigest(original));
}
- (void)install:(NSString *)name enabled:(BOOL)enabled {
    if (![root length])
        CFRequire([CFClassicPIDs() count] == 0, @"Classic must be stopped before file replacement");
    NSDictionary *s = [self spec:name];
    NSString *path = [self pathFor:s];
    struct stat before = metadata(path);
    BOOL resource = [[s objectForKey:@"resource"] boolValue],
         atomic = [[s objectForKey:@"atomic"] boolValue];
    NSString *fork = resource ? [path stringByAppendingString:@"/..namedfork/rsrc"] : path;
    NSString *backup = [path stringByAppendingString:[s objectForKey:@"backup"]];
    NSData *current = CFReadFile(fork);
    NSString *hash = imageDigest(current, s);
    BOOL baseline = [hash isEqual:expectedDigest(s, NO)],
         patched = [hash isEqual:expectedDigest(s, YES)];
    CFRequire(baseline || patched, [@"Unrecognized image: " stringByAppendingString:path]);
    NSData *original = baseline ? current : CFReadFile(backup);
    CFRequire([imageDigest(original, s) isEqual:expectedDigest(s, NO)], @"Invalid original backup");
    NSData *replacement = preserveRuntimeMap(enabled ? [self transform:original spec:s] : original,
                                            current, s);
    NSArray *ranges = [self writeSegmentsForSpec:s];
    if (entry(backup)) {
        metadata(backup);
        CFRequire(sameImage(CFReadFile(backup), original, s), @"Backup mismatch; refusing modification");
    } else {
        CFRequire(baseline, @"Patched image has no verified backup");
        newBackup(backup, original, before);
    }
    if ([current isEqual:replacement]) {
        CFSLog(@"%@: already %@", name, enabled ? @"patched" : @"baseline");
        return;
    }
    NSData *other = nil;
    if (!atomic)
        other = CFReadFile(resource ? path : [path stringByAppendingString:@"/..namedfork/rsrc"]);
    CFRequire(same(before, metadata(path)) && [CFReadFile(fork) isEqual:current],
              @"File changed before patching");
    if (![root length])
        CFRequire([CFClassicPIDs() count] == 0, @"Classic started before patching");
    if (atomic) {
        NSString *pattern = [[path stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@".classic-native-XXXXXX"];
        char *tmp = strdup([pattern fileSystemRepresentation]);
        int fd = mkstemp(tmp);
        CFRequire(fd >= 0, @"Cannot create temporary host image");
        @try {
            CFWriteAll(fd, [replacement bytes], [replacement length]);
            CFRequire(fchown(fd, before.st_uid, before.st_gid) == 0 &&
                          fchmod(fd, before.st_mode & 07777) == 0 && fsync(fd) == 0,
                      @"Cannot preserve host permissions");
            close(fd);
            fd = -1;
            CFRequire([CFReadFile([NSString stringWithUTF8String:tmp]) isEqual:replacement] &&
                          same(before, metadata(path)) && [CFReadFile(path) isEqual:current],
                      @"Host changed during patching");
            if (![root length])
                CFRequire([CFClassicPIDs() count] == 0, @"Classic started during patching");
            CFRequire(rename(tmp, [path fileSystemRepresentation]) == 0,
                      @"Cannot commit host image");
        } @finally {
            if (fd >= 0)
                close(fd);
            unlink(tmp);
            free(tmp);
        }
    } else {
        int fd = open([fork fileSystemRepresentation], O_RDWR | O_NOFOLLOW);
        CFRequire(fd >= 0, @"Cannot open target fork");
        @try {
            struct stat opened;
            CFRequire(fstat(fd, &opened) == 0 && (resource || same(before, opened)),
                      @"Target identity changed");
            CFRequire(same(before, metadata(path)) && [CFReadFile(fork) isEqual:current],
                      @"Target changed before write");
            @try {
                writeRanges(fd, replacement, ranges);
                CFRequire(
                    [CFReadFile(fork) isEqual:replacement] &&
                        [CFReadFile(resource ? path
                                             : [path stringByAppendingString:@"/..namedfork/rsrc"])
                            isEqual:other] &&
                        same(before, metadata(path)),
                    @"Fork or metadata verification failed");
            } @catch (id failure) {
                writeRanges(fd, current, ranges);
                CFRequire([CFReadFile(fork) isEqual:current],
                          @"Patch rollback failed; keep Classic stopped");
                @throw failure;
            }
        } @finally {
            close(fd);
        }
    }
    CFRequire([CFReadFile(fork) isEqual:replacement], @"Final patch verification failed");
    CFSLog(@"%@: %@ (%@)", name, enabled ? @"patched" : @"restored", CFDigest(replacement));
}
@end
