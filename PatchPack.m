/* Build-time only: extract relocation-free PPC patches and generate fingerprints.
 * This tool and the assembler are not needed to run ClassicFullscreen.app. */
#include <Carbon/Carbon.h>
#include <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
static void need(BOOL ok, NSString *message) {
    if (!ok) {
        fprintf(stderr, "%s\n", [message UTF8String]);
        exit(1);
    }
}
static NSString *md5(NSData *data) {
    unsigned char d[16];
    char s[33];
    int i;
    CC_MD5_CTX ctx;
    CC_MD5_Init(&ctx);
    CC_MD5_Update(&ctx, [data bytes], [data length]);
    CC_MD5_Final(d, &ctx);
    for (i = 0; i < 16; i++)
        sprintf(s + 2 * i, "%02x", d[i]);
    s[32] = 0;
    return [NSString stringWithUTF8String:s];
}
/* Match the runtime identity rule: only the six resource-map bookkeeping bytes
 * are excluded. Neither the original file nor the packaged payload is changed. */
static NSString *identityDigest(NSData *data, NSDictionary *s) {
    if (![[s objectForKey:@"resource"] boolValue])
        return md5(data);
    unsigned map = [[s objectForKey:@"resourceMapOffset"] unsignedIntValue];
    need([[s objectForKey:@"name"] isEqual:@"Resources"] &&
             [data length] == [[s objectForKey:@"length"] unsignedIntValue] &&
             map >= 16 && map <= [data length] && [data length] - map >= 28,
         @"Unsupported Classic resource-map layout");
    const unsigned char *b = [data bytes];
    unsigned actual = ((unsigned)b[4] << 24) | ((unsigned)b[5] << 16) |
                      ((unsigned)b[6] << 8) | b[7];
    need(actual == map, @"Unsupported Classic resource-map offset");
    NSMutableData *normalized = [[data mutableCopy] autorelease];
    memset((char *)[normalized mutableBytes] + map + 16, 0, 6);
    return md5(normalized);
}
static BOOL isBaseline(NSData *data, NSDictionary *s) {
    return data && [data length] == [[s objectForKey:@"length"] unsignedIntValue] &&
        [identityDigest(data, s) isEqual:[s objectForKey:
            [[s objectForKey:@"resource"] boolValue] ? @"normalizedBaseMD5" : @"baseMD5"]];
}
static NSData *readBaseline(NSDictionary *s, NSString *directory, NSString *systemFolder) {
    NSString *name = [s objectForKey:@"name"], *path;
    NSData *data;
    if ([directory length]) {
        /* Guest and Indexed compose two nonoverlapping edits of the SAME stock
         * Classic data fork. The old Guest.baseline fixture was already optimized. */
        NSString *file = [([name isEqual:@"Guest"] ? @"Indexed" : name)
            stringByAppendingString:@".baseline"];
        path = [directory stringByAppendingPathComponent:file];
        data = [NSData dataWithContentsOfFile:path];
    } else {
        path = [s objectForKey:@"path"];
        if (![name isEqual:@"Host"])
            path = [systemFolder stringByAppendingPathComponent:path];
        NSString *fork = [[s objectForKey:@"resource"] boolValue]
            ? [path stringByAppendingString:@"/..namedfork/rsrc"] : path;
        data = [NSData dataWithContentsOfFile:fork];
        if (!isBaseline(data, s)) {
            /* An active session may have patched the live files. Its backup is
             * usable only if it independently matches the fixed stock identity. */
            NSString *suffix = [name isEqual:@"Indexed"]
                ? @".classic-fullscreen-original-data" : [s objectForKey:@"backup"];
            path = [path stringByAppendingString:suffix];
            data = [NSData dataWithContentsOfFile:path];
        }
    }
    need(isBaseline(data, s), [NSString stringWithFormat:
        @"Missing or unsupported %@ baseline: %@. Supply verified originals with "
         "PATCH_BASELINES (Host/Indexed/Finder/Resources.baseline).", name, path]);
    return data;
}
static NSData *pack(NSDictionary *s, NSString *objects) {
    NSString *name = [s objectForKey:@"name"];
    NSData *object = [NSData
        dataWithContentsOfFile:
            [objects stringByAppendingPathComponent:[name stringByAppendingString:@".o"]]];
    need([object length] >= sizeof(struct mach_header), @"Missing patch object");
    const unsigned char *b = [object bytes];
    const struct mach_header *h = (const void *)b;
    need(h->magic == MH_MAGIC && h->cputype == CPU_TYPE_POWERPC && h->filetype == MH_OBJECT,
         @"Expected native 32-bit PowerPC Mach-O object");
    unsigned off = sizeof(*h), j;
    NSData *image = nil;
    for (j = 0; j < h->ncmds; j++) {
        need(off + sizeof(struct load_command) <= [object length], @"Truncated object");
        const struct load_command *c = (const void *)(b + off);
        need(c->cmdsize >= sizeof(*c) && off + c->cmdsize <= [object length],
             @"Invalid load command");
        if (c->cmd == LC_SEGMENT) {
            const struct segment_command *g = (const void *)c;
            unsigned k;
            need(c->cmdsize >= sizeof(*g) + g->nsects * sizeof(struct section),
                 @"Invalid sections");
            const struct section *sec = (const void *)(g + 1);
            for (k = 0; k < g->nsects; k++) {
                need(sec[k].nreloc == 0, @"Unresolved relocation in patch object");
                if (!strcmp(sec[k].sectname, "__text") && !strcmp(sec[k].segname, "__TEXT")) {
                    need(sec[k].addr == 0 && sec[k].offset + sec[k].size <= [object length],
                         @"Invalid patch section bounds");
                    image = [object subdataWithRange:NSMakeRange(sec[k].offset, sec[k].size)];
                }
            }
        }
        off += c->cmdsize;
    }
    need(image != nil, @"Missing patch text section");
    NSMutableData *packed = [NSMutableData data];
    NSArray *segments = [s objectForKey:@"segments"];
    unsigned k, end = 0, length = [[s objectForKey:@"length"] unsignedIntValue];
    need([segments count] > 0, @"Missing patch ranges");
    for (k = 0; k < [segments count]; k++) {
        NSDictionary *r = [segments objectAtIndex:k];
        unsigned a = [[r objectForKey:@"offset"] unsignedIntValue],
                 n = [[r objectForKey:@"length"] unsignedIntValue];
        need(n && a >= end && a <= length && n <= length - a &&
                 a <= [image length] && n <= [image length] - a &&
                 [packed length] == [[r objectForKey:@"payloadOffset"] unsignedIntValue],
             @"Invalid patch range");
        if ([[s objectForKey:@"resource"] boolValue]) {
            unsigned runtime = [[s objectForKey:@"resourceMapOffset"] unsignedIntValue] + 16;
            need(a + n <= runtime || a >= runtime + 6,
                 @"Patch overlaps resource-map runtime fields");
        }
        [packed appendData:[image subdataWithRange:NSMakeRange(a, n)]];
        end = a + n;
    }
    return packed;
}
static void apply(NSMutableData *image, NSDictionary *s, NSData *payload) {
    unsigned i;
    NSArray *ranges = [s objectForKey:@"segments"];
    for (i = 0; i < [ranges count]; i++) {
        NSDictionary *r = [ranges objectAtIndex:i];
        unsigned a = [[r objectForKey:@"offset"] unsignedIntValue],
                 n = [[r objectForKey:@"length"] unsignedIntValue],
                 p = [[r objectForKey:@"payloadOffset"] unsignedIntValue];
        [image replaceBytesInRange:NSMakeRange(a, n) withBytes:(const char *)[payload bytes] + p];
    }
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    need(argc == 4 || argc == 5,
         @"PatchPack manifest object-directory output-directory [baseline-directory]");
    NSString *manifest = [NSString stringWithUTF8String:argv[1]],
             *objects = [NSString stringWithUTF8String:argv[2]],
             *output = [NSString stringWithUTF8String:argv[3]],
             *directory = argc == 5 ? [NSString stringWithUTF8String:argv[4]] : nil,
             *systemFolder = nil;
    NSArray *specs = [NSArray arrayWithContentsOfFile:manifest];
    need([specs count] == 5, @"Invalid manifest");
    if (![directory length]) {
        FSRef ref;
        UInt8 path[PATH_MAX];
        OSStatus err = FSFindFolder(kClassicDomain, kSystemFolderType, false, &ref);
        if (!err)
            err = FSRefMakePath(&ref, path, sizeof(path));
        need(!err, @"Select a Classic System Folder, or set PATCH_BASELINES to verified originals");
        systemFolder = [NSString stringWithUTF8String:(char *)path];
    }
    NSMutableArray *generated = [NSMutableArray array];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary],
                        *payloads = [NSMutableDictionary dictionary],
                        *baselines = [NSMutableDictionary dictionary];
    unsigned i;
    /* Validate every source before publishing any resources. */
    for (i = 0; i < [specs count]; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        NSString *name = [s objectForKey:@"name"];
        need([name length] && ![byName objectForKey:name], @"Duplicate or missing patch name");
        [byName setObject:s forKey:name];
        [payloads setObject:pack(s, objects) forKey:name];
        [baselines setObject:readBaseline(s, directory, systemFolder) forKey:name];
    }
    for (i = 0; i < [specs count]; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        NSString *name = [s objectForKey:@"name"], *prepare = [s objectForKey:@"prepare"];
        NSMutableData *result = [[[baselines objectForKey:name] mutableCopy] autorelease];
        if (prepare) {
            NSDictionary *p = [byName objectForKey:prepare];
            need([name isEqual:@"Guest"] && [prepare isEqual:@"Indexed"] && p &&
                     ![p objectForKey:@"prepare"] &&
                     [[s objectForKey:@"path"] isEqual:[p objectForKey:@"path"]] &&
                     [[baselines objectForKey:name] isEqual:[baselines objectForKey:prepare]],
                 @"Incompatible patch composition");
            NSMutableArray *ranges = [NSMutableArray arrayWithArray:[s objectForKey:@"segments"]];
            [ranges addObjectsFromArray:[p objectForKey:@"segments"]];
            NSSortDescriptor *order = [[[NSSortDescriptor alloc] initWithKey:@"offset"
                                                                 ascending:YES] autorelease];
            [ranges sortUsingDescriptors:[NSArray arrayWithObject:order]];
            unsigned k, end = 0;
            for (k = 0; k < [ranges count]; k++) {
                NSDictionary *r = [ranges objectAtIndex:k];
                unsigned a = [[r objectForKey:@"offset"] unsignedIntValue];
                need(a >= end, @"Overlapping combined patch ranges");
                end = a + [[r objectForKey:@"length"] unsignedIntValue];
            }
            apply(result, p, [payloads objectForKey:prepare]);
        }
        NSData *packed = [payloads objectForKey:name];
        apply(result, s, packed);
        NSMutableDictionary *g = [[s mutableCopy] autorelease];
        [g removeObjectForKey:@"assembledMD5"];
        [g setObject:md5(packed) forKey:@"payloadMD5"];
        [g setObject:md5(result) forKey:@"patchedMD5"];
        if ([[s objectForKey:@"resource"] boolValue])
            [g setObject:identityDigest(result, s) forKey:@"normalizedPatchedMD5"];
        [generated addObject:g];
    }
    for (i = 0; i < [generated count]; i++) {
        NSDictionary *s = [generated objectAtIndex:i];
        NSString *name = [s objectForKey:@"name"];
        NSData *packed = [payloads objectForKey:name];
        need([packed writeToFile:[output stringByAppendingPathComponent:[s objectForKey:@"payload"]]
                      atomically:YES], @"Cannot write patch resource");
        printf("Generated %s: %lu payload bytes, no relocations, patched MD5 %s\n",
               [name UTF8String], (unsigned long)[packed length],
               [[s objectForKey:@"patchedMD5"] UTF8String]);
    }
    need([generated writeToFile:[output stringByAppendingPathComponent:@"Manifest.plist"]
                     atomically:YES], @"Cannot write generated patch manifest");
    [pool release];
    return 0;
}
