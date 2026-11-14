/* Build-time regression tests. All mutations stay in the temporary directory. */
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/loader.h>
static void requireTest(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
}
static NSString *digest(NSData *data) {
    unsigned char hash[16]; char text[33]; unsigned i;
    CC_MD5_CTX context;
    CC_MD5_Init(&context);
    CC_MD5_Update(&context, [data bytes], [data length]);
    CC_MD5_Final(hash, &context);
    for (i = 0; i < 16; i++) sprintf(text + i * 2, "%02x", hash[i]);
    text[32] = 0;
    return [NSString stringWithUTF8String:text];
}
static NSData *readData(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    requireTest(data != nil, [@"Cannot read " stringByAppendingString:path]);
    return data;
}
static void writeData(NSData *data, NSString *path) {
    requireTest([data writeToFile:path atomically:YES], [@"Cannot write " stringByAppendingString:path]);
}
static NSDictionary *spec(NSArray *specs, NSString *name) {
    unsigned i;
    for (i = 0; i < [specs count]; i++)
        if ([[[specs objectAtIndex:i] objectForKey:@"name"] isEqual:name])
            return [specs objectAtIndex:i];
    requireTest(NO, @"Missing patch specification"); return nil;
}
static void run(NSString *tool, NSString *manifest, NSString *objects,
                NSString *output, NSString *baselines, BOOL success) {
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:tool];
    [task setArguments:[NSArray arrayWithObjects:manifest, objects, output, baselines, nil]];
    [task launch]; [task waitUntilExit];
    requireTest(([task terminationStatus] == 0) == success, @"Unexpected PatchPack exit status");
}
static void verifyGenerated(NSString *output, NSDictionary *expected) {
    NSArray *specs = [NSArray arrayWithContentsOfFile:
        [output stringByAppendingPathComponent:@"Manifest.plist"]];
    requireTest([specs count] == 5, @"Generated manifest missing");
    unsigned i;
    for (i = 0; i < [specs count]; i++) {
        NSDictionary *s = [specs objectAtIndex:i];
        NSData *payload = readData([output stringByAppendingPathComponent:[s objectForKey:@"payload"]]);
        requireTest(![s objectForKey:@"assembledMD5"], @"Assembled-section checksum retained");
        requireTest([digest(payload) isEqual:[s objectForKey:@"payloadMD5"]], @"Payload checksum differs");
        NSData *want = [expected objectForKey:[s objectForKey:@"name"]];
        requireTest([digest(want) isEqual:[s objectForKey:@"patchedMD5"]], @"Complete-file checksum differs");
        if ([[s objectForKey:@"resource"] boolValue]) {
            NSMutableData *normalized = [[want mutableCopy] autorelease];
            memset((char *)[normalized mutableBytes] +
                   [[s objectForKey:@"resourceMapOffset"] unsignedIntValue] + 16, 0, 6);
            requireTest([digest(normalized) isEqual:[s objectForKey:@"normalizedPatchedMD5"]],
                  @"Normalized resource checksum differs");
        }
    }
}
static void changeObject(NSString *path, unsigned address) {
    NSMutableData *data = [[readData(path) mutableCopy] autorelease];
    unsigned char *b = [data mutableBytes];
    struct mach_header *h = (void *)b;
    unsigned off = sizeof(*h), i;
    for (i = 0; i < h->ncmds; i++) {
        struct load_command *c = (void *)(b + off);
        if (c->cmd == LC_SEGMENT) {
            struct segment_command *g = (void *)c;
            struct section *sections = (void *)(g + 1);
            unsigned k;
            for (k = 0; k < g->nsects; k++) {
                if (!strcmp(sections[k].sectname, "__text")) {
                    requireTest(address < sections[k].size, @"Mutation outside patch section");
                    b[sections[k].offset + address] ^= 1;
                    writeData(data, path); return;
                }
            }
        }
        off += c->cmdsize;
    }
    requireTest(NO, @"Missing object text section");
}
static void changeExpected(NSMutableDictionary *expected, NSString *name, unsigned offset) {
    NSMutableData *data = [[[expected objectForKey:name] mutableCopy] autorelease];
    ((unsigned char *)[data mutableBytes])[offset] ^= 1;
    [expected setObject:data forKey:name];
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    requireTest(argc == 6, @"PatchPackTests manifest objects output fixtures temporary-directory");
    NSString *manifest = [NSString stringWithUTF8String:argv[1]],
             *objects = [NSString stringWithUTF8String:argv[2]],
             *output = [NSString stringWithUTF8String:argv[3]],
             *fixtures = [NSString stringWithUTF8String:argv[4]],
             *temporary = [NSString stringWithUTF8String:argv[5]],
             *tool = [objects stringByAppendingPathComponent:@"PatchPack"],
             *baselines = [temporary stringByAppendingPathComponent:@"baselines"];
    requireTest([[NSFileManager defaultManager] createDirectoryAtPath:baselines attributes:nil],
          @"Cannot create private baseline directory");
    NSArray *source = [NSArray arrayWithContentsOfFile:manifest];
    NSMutableDictionary *expected = [NSMutableDictionary dictionary];
    unsigned i;
    for (i = 0; i < [source count]; i++) {
        NSString *name = [[source objectAtIndex:i] objectForKey:@"name"];
        NSString *base = [name stringByAppendingString:@".baseline"];
        if (![name isEqual:@"Guest"])
            writeData(readData([fixtures stringByAppendingPathComponent:base]),
                  [baselines stringByAppendingPathComponent:base]);
        [expected setObject:readData([fixtures stringByAppendingPathComponent:
            [name stringByAppendingString:@".patched"]]) forKey:name];
    }
    run(tool, manifest, objects, output, baselines, YES);
    verifyGenerated(output, expected);
    puts("PASS: generated payload/full-image hashes match independent reviewed fixtures");

    /* Changed instructions must need no manually updated hash. Changing Indexed
     * must also change Guest's composite fingerprint, although Guest.bin is intact. */
    NSArray *before = [NSArray arrayWithContentsOfFile:
        [output stringByAppendingPathComponent:@"Manifest.plist"]];
    NSString *hostObject = [objects stringByAppendingPathComponent:@"Host.o"],
             *indexedObject = [objects stringByAppendingPathComponent:@"Indexed.o"];
    NSData *host = readData(hostObject), *indexed = readData(indexedObject);
    changeObject(hostObject, 4355); changeExpected(expected, @"Host", 4355);
    changeObject(indexedObject, 712523);
    changeExpected(expected, @"Indexed", 712523); changeExpected(expected, @"Guest", 712523);
    run(tool, manifest, objects, output, baselines, YES);
    verifyGenerated(output, expected);
    NSArray *after = [NSArray arrayWithContentsOfFile:
        [output stringByAppendingPathComponent:@"Manifest.plist"]];
    requireTest([[spec(before, @"Guest") objectForKey:@"payloadMD5"]
           isEqual:[spec(after, @"Guest") objectForKey:@"payloadMD5"]] &&
          ![[spec(before, @"Guest") objectForKey:@"patchedMD5"]
            isEqual:[spec(after, @"Guest") objectForKey:@"patchedMD5"]],
          @"Guest composition fingerprint did not follow Indexed change");
    puts("PASS: assembly edits regenerate hashes, including composite Guest output");
    writeData(host, hostObject); writeData(indexed, indexedObject);
    changeExpected(expected, @"Host", 4355); changeExpected(expected, @"Indexed", 712523);
    changeExpected(expected, @"Guest", 712523);

    NSString *resourcePath = [baselines stringByAppendingPathComponent:@"Resources.baseline"];
    NSData *alternate = readData([fixtures stringByAppendingPathComponent:@"Resources.alternate"]);
    writeData(alternate, resourcePath);
    unsigned runtime = [[spec(source, @"Resources") objectForKey:@"resourceMapOffset"] unsignedIntValue] + 16;
    NSMutableData *alternateExpected = [[[expected objectForKey:@"Resources"] mutableCopy] autorelease];
    memcpy((char *)[alternateExpected mutableBytes] + runtime, (const char *)[alternate bytes] + runtime, 6);
    [expected setObject:alternateExpected forKey:@"Resources"];
    run(tool, manifest, objects, output, baselines, YES); verifyGenerated(output, expected);
    puts("PASS: alternate resource bookkeeping preserves normalized identity");

    NSString *hostPath = [baselines stringByAppendingPathComponent:@"Host.baseline"];
    NSData *original = readData(hostPath);
    NSMutableData *bad = [[original mutableCopy] autorelease];
    ((unsigned char *)[bad mutableBytes])[0] ^= 1; writeData(bad, hostPath);
    run(tool, manifest, objects, output, baselines, NO);
    [[NSFileManager defaultManager] removeFileAtPath:hostPath handler:nil];
    run(tool, manifest, objects, output, baselines, NO); writeData(original, hostPath);
    puts("PASS: unknown and missing originals are refused");

    NSMutableArray *invalid = [[source mutableCopy] autorelease];
    NSMutableDictionary *s = [[spec(source, @"Indexed") mutableCopy] autorelease],
                        *range = [[[[s objectForKey:@"segments"] objectAtIndex:0] mutableCopy] autorelease];
    /* Valid within each section but overlaps Guest when composed. */
    [range setObject:[NSNumber numberWithUnsignedInt:239640] forKey:@"offset"];
    [s setObject:[NSArray arrayWithObject:range] forKey:@"segments"];
    [invalid replaceObjectAtIndex:[source indexOfObject:spec(source, @"Indexed")] withObject:s];
    NSString *badManifest = [temporary stringByAppendingPathComponent:@"invalid.plist"];
    requireTest([invalid writeToFile:badManifest atomically:YES], @"Cannot write test manifest");
    run(tool, badManifest, objects, output, baselines, NO);
    [range setObject:[NSNumber numberWithUnsignedInt:0xffffffffU] forKey:@"length"];
    requireTest([invalid writeToFile:badManifest atomically:YES], @"Cannot write test manifest");
    run(tool, badManifest, objects, output, baselines, NO);
    puts("PASS: overlapping composition and overflowing ranges are refused");
    [pool release]; return 0;
}
