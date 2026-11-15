/* Run the exact injected instructions in a private native process, first with
 * service mocks, then on explicitly supplied disposable HFS+ files/folders.
 * Run as nathan, never root. No installed Classic executable is used here. */
#include <Carbon/Carbon.h>
#include <mach/mach.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned int U;
typedef OSErr (*Save)(CInfoPBPtr);
static int checks, scenario, legacy_calls, writes, reads, is_file;
static CInfoPBRec request;
static void test_check(int yes, const char *name) {
    ++checks;
    if (!yes) { fprintf(stderr, "FAIL: %s (scenario %d)\n", name, scenario); exit(1); }
}
static OSErr set_mock(CInfoPBPtr pb) {
    test_check(pb == &request && legacy_calls++ == 0, "original call exactly once");
    pb->dirInfo.ioResult = scenario == 1 ? 0 : scenario == 2 ? fnfErr : afpAccessDenied;
    return pb->dirInfo.ioResult;
}
static OSErr ref_mock(FSRefParam *p) {
    test_check(legacy_calls == 1 && p->ioVRefNum == -7 && p->ioDirID == 123 &&
          p->ioNamePtr == request.dirInfo.ioNamePtr && !p->ioCompletion,
          "original pathname, volume and directory preserved");
    memset(p->newRef, 0x42, sizeof(FSRef));
    return scenario == 3 ? fnfErr : 0;
}
static OSErr info_mock(const FSRef *ref, FSCatalogInfoBitmap bits,
        FSCatalogInfo *info, HFSUniStr255 *name, FSSpec *spec, FSRef *parent) {
    test_check(((const unsigned char *)ref)[0] == 0x42 && bits ==
          (kFSCatInfoNodeFlags | kFSCatInfoNodeID | kFSCatInfoVolume) &&
          !name && spec && !parent, "resolve stable node identity");
    memset(info, 0, sizeof(*info));
    info->nodeFlags = is_file ? 0 : kFSNodeIsDirectoryMask;
    memset(spec, 0, sizeof(*spec));
    spec->vRefNum = -8; spec->parID = 789; memcpy(spec->name, "\010Resolved", 9);
    info->volume = -8; info->nodeID = 456;
    return scenario == 4 ? fnfErr : 0;
}
static OSErr get_mock(CInfoPBPtr pb) {
    reads++;
    test_check(pb->dirInfo.ioVRefNum == -8 && pb->dirInfo.ioDrDirID == 789 &&
          pb->dirInfo.ioFDirIndex == 0 && pb->dirInfo.ioNamePtr &&
          !memcmp(pb->dirInfo.ioNamePtr, "\010Resolved", 9) &&
          !pb->dirInfo.ioCompletion, "reread by resolved FSSpec, not original pathname");
    pb->dirInfo.ioFlAttrib = is_file ? 0 : 0x10;
    pb->dirInfo.ioDrDirID = scenario == 7 ? 999 : 456;
    pb->dirInfo.ioDrCrDat = 100 + (scenario == 8);
    pb->dirInfo.ioDrMdDat = 200 + (scenario == 9);
    pb->dirInfo.ioDrBkDat = 300 + (scenario == 10);
    return scenario == 6 ? fnfErr : 0;
}
static OSErr write_mock(const FSRef *ref, FSCatalogInfoBitmap bits,
        const FSCatalogInfo *info) {
    writes++;
    test_check(reads == 1 && ((const unsigned char *)ref)[0] == 0x42 &&
          bits == (kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo),
          "write only Finder metadata to the same resolved object");
    test_check(!memcmp(info->finderInfo, &request.dirInfo.ioDrUsrWds, 16) &&
          !memcmp(info->extFinderInfo, &request.dirInfo.ioDrFndrInfo, 16),
          "both complete FinderInfo blocks preserved");
    return scenario == 11 ? afpAccessDenied : 0;
}
extern void sys_icache_invalidate(void *, unsigned long);
static void map_at(U address, U length) {
    vm_address_t a = address;
    test_check(vm_allocate(mach_task_self(), &a, length, 0) == 0 && a == address,
          "allocate unused private address");
}
static void stub(U where, void *target) {
    U *p = (U *)where, v = (U)target;
    p[0] = 0x3d800000 | (v >> 16); p[1] = 0x618c0000 | (v & 65535);
    p[2] = 0x7d8903a6; p[3] = 0x4e800420;
}
static void services(int mocks) {
    stub(0x5e07ce3c, mocks ? set_mock : PBSetCatInfoSync);
    stub(0x5e07ce8c, mocks ? get_mock : PBGetCatInfoSync);
    stub(0x5e07d71c, mocks ? ref_mock : PBMakeFSRefSync);
    stub(0x5e07ce2c, mocks ? info_mock : FSGetCatalogInfo);
    stub(0x5e07cdcc, mocks ? write_mock : FSSetCatalogInfo);
    stub(0x5e07c56c, memset); stub(0x5e07c49c, memcpy);
    sys_icache_invalidate((void *)0x5e07c000, 8192);
}
static void mocks(Save save) {
    int expected, i; CInfoPBRec before; Str31 name = "\004Test";
    for (is_file = 0; is_file < 2; is_file++) for (scenario = 0; scenario < 12; ++scenario) {
        memset(&request, 0, sizeof(request));
        request.dirInfo.ioVRefNum = -7; request.dirInfo.ioDrDirID = 123;
        request.dirInfo.ioNamePtr = scenario == 5 ? NULL : name;
        request.dirInfo.ioDrCrDat = 100; request.dirInfo.ioDrMdDat = 200;
        request.dirInfo.ioDrBkDat = 300;
        for (i = 0; i < 16; i++) {
            ((unsigned char *)&request.dirInfo.ioDrUsrWds)[i] = i * 11;
            ((unsigned char *)&request.dirInfo.ioDrFndrInfo)[i] = 255 - i * 7;
        }
        before = request; legacy_calls = writes = reads = 0;
        expected = (scenario < 2 || scenario == 5) ? 0 : scenario == 2 ? fnfErr : afpAccessDenied;
        test_check(save(&request) == expected && request.dirInfo.ioResult == expected,
              "return value and parameter-block result");
        before.dirInfo.ioResult = expected;
        test_check(!memcmp(&request, &before, sizeof(request)), "no other caller PB changes");
        test_check(legacy_calls == 1 && writes == (scenario == 0 || scenario == 5 || scenario == 11),
              "no fallback on success, other errors, identity mismatch, failed reads or changed dates");
    }
}
static void read_object(const char *path, FSRef *ref, FSCatalogInfo *info, CInfoPBPtr pb) {
    Boolean dir; FSSpec spec;
    test_check(FSPathMakeRef((const UInt8 *)path, ref, &dir) == 0, "scratch object");
    test_check(FSGetCatalogInfo(ref, kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo |
        kFSCatInfoNodeID | kFSCatInfoParentDirID | kFSCatInfoVolume |
        kFSCatInfoCreateDate | kFSCatInfoContentMod | kFSCatInfoBackupDate,
        info, 0, &spec, 0) == 0, "read scratch metadata");
    memset(pb, 0, sizeof(*pb));
    pb->dirInfo.ioVRefNum = info->volume;
    /* PB name storage belongs to the caller: separate static buffer is enough
     * for these sequential disposable tests, never asynchronous calls. */
    { static Str255 name; memcpy(name, spec.name, sizeof(spec.name));
      pb->dirInfo.ioNamePtr = name; }
    pb->dirInfo.ioDrDirID = spec.parID;
    test_check(PBGetCatInfoSync(pb) == 0, "read legacy scratch metadata");
    pb->dirInfo.ioDrDirID = spec.parID;
}
static void real_object(Save save, const char *path, int owned, int writable, int named) {
    FSRef ref; FSCatalogInfo before, after; CInfoPBRec pb, afterpb;
    struct stat st, st2; Str255 name; const char *base = strrchr(path, '/') + 1;
    int directory;
    int original, expected = writable ? 0 : afpAccessDenied;
    scenario = 20 + owned * 4 + writable * 2 + named;
    test_check(stat(path, &st) == 0 && (owned ? st.st_uid == getuid() : st.st_uid == 0),
          "fixture ownership");
    directory = S_ISDIR(st.st_mode);
    read_object(path, &ref, &before, &pb);
    original = PBSetCatInfoSync(&pb);
    test_check(original == (owned ? 0 : afpAccessDenied), "actual legacy permissions failure");
    if (!named && directory) {
        pb.dirInfo.ioNamePtr = NULL; pb.dirInfo.ioDrDirID = before.nodeID;
        pb.dirInfo.ioFDirIndex = -1;
    } else if (!named) {
        CFURLRef url = CFURLCreateFromFSRef(NULL, &ref);
        CFStringRef hfs = CFURLCopyFileSystemPath(url, kCFURLHFSPathStyle);
        test_check(CFStringGetPascalString(hfs, name, sizeof(name),
                   kCFStringEncodingMacRoman), "full HFS pathname");
        CFRelease(hfs); CFRelease(url);
        pb.dirInfo.ioNamePtr = name; pb.dirInfo.ioVRefNum = 0;
        pb.dirInfo.ioDrDirID = 0; pb.dirInfo.ioFDirIndex = 0;
    }
    if (named) {
        size_t n = strlen(base); test_check(n < 256, "fixture basename length");
        name[0] = n; memcpy(name + 1, base, n);
        pb.dirInfo.ioNamePtr = name; pb.dirInfo.ioDrDirID = before.parentDirID;
        pb.dirInfo.ioFDirIndex = 0;
    }
    if (directory) {
        pb.dirInfo.ioDrUsrWds.frRect.top = 121; pb.dirInfo.ioDrUsrWds.frRect.left = 234;
        pb.dirInfo.ioDrUsrWds.frRect.bottom = 456; pb.dirInfo.ioDrUsrWds.frRect.right = 789;
    }
    pb.hFileInfo.ioFlFndrInfo.fdLocation.h = 193;
    pb.hFileInfo.ioFlFndrInfo.fdLocation.v = 217;
    pb.hFileInfo.ioFlFndrInfo.fdFlags ^= 0x000e; /* label */
    pb.dirInfo.ioDrFndrInfo.frScroll.h = 31;
    pb.dirInfo.ioDrFndrInfo.frScroll.v = 47;
    pb.dirInfo.ioDrFndrInfo.frComment = 13; /* comment reference, not content */
    test_check(save(&pb) == expected && pb.dirInfo.ioResult == expected, "actual FinderInfo save");
    read_object(path, &ref, &after, &afterpb);
    test_check(!memcmp(&before.createDate, &after.createDate, sizeof(UTCDateTime)) &&
          !memcmp(&before.contentModDate, &after.contentModDate, sizeof(UTCDateTime)) &&
          !memcmp(&before.backupDate, &after.backupDate, sizeof(UTCDateTime)),
          "all three dates unchanged");
    test_check(!memcmp(after.finderInfo, writable ? (void *)&pb.dirInfo.ioDrUsrWds : before.finderInfo, 16) &&
          !memcmp(after.extFinderInfo, writable ? (void *)&pb.dirInfo.ioDrFndrInfo : before.extFinderInfo, 16), "exact persisted metadata");
    if (!owned) {
        int i;
        for (i = 0; i < 3; i++) {
            pb = afterpb;
            if (i == 0) pb.dirInfo.ioDrCrDat++;
            if (i == 1) pb.dirInfo.ioDrMdDat++;
            if (i == 2) pb.dirInfo.ioDrBkDat++;
            pb.dirInfo.ioDrUsrWds.frRect.top++;
            test_check(save(&pb) == afpAccessDenied, "genuine date-change request still denied");
        }
        read_object(path, &ref, &after, &pb);
        test_check(!memcmp(&pb.dirInfo.ioDrUsrWds, &afterpb.dirInfo.ioDrUsrWds, 16) &&
              pb.dirInfo.ioDrCrDat == afterpb.dirInfo.ioDrCrDat &&
              pb.dirInfo.ioDrMdDat == afterpb.dirInfo.ioDrMdDat &&
              pb.dirInfo.ioDrBkDat == afterpb.dirInfo.ioDrBkDat, "denied requests write nothing");
    }
    test_check(stat(path, &st2) == 0 && st.st_uid == st2.st_uid && st.st_gid == st2.st_gid &&
          st.st_mode == st2.st_mode, "ownership and permissions unchanged");
    if (writable) test_check(FSSetCatalogInfo(&ref, kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo,
                                        &before) == 0, "restore scratch metadata");
    printf("PASS: %s %s lookup; owned=%d writable=%d\n", path,
           named ? "parent/name" : directory ? "ID" : "full path", owned, writable);
}
int main(int argc, char **argv) {
    FILE *f; Save save = (Save)0x5e001500; int i;
    test_check(geteuid() != 0 && argc == 8, "non-root process, host, three scratch folders and three scratch files");
    f = fopen(argv[1], "rb"); test_check(f != 0, "payload file");
    map_at(0x5e000000, 0x94000);
    test_check(fread((void *)0x5e000000, 1, 604400, f) == 604400, "complete host image"); fclose(f);
    sys_icache_invalidate((void *)0x5e000000, 0x94000);
    services(1); mocks(save); services(0);
    for (i = 2; i <= 5; i += 3) {
        real_object(save, argv[i], 0, 1, 0); real_object(save, argv[i], 0, 1, 1);
        real_object(save, argv[i+1], 0, 0, 0); real_object(save, argv[i+1], 0, 0, 1);
        real_object(save, argv[i+2], 1, 1, 0); real_object(save, argv[i+2], 1, 1, 1);
    }
    printf("PASS: %d checks; exact PowerPC payload, failure guards and real HFS+ permissions.\n", checks);
    return 0;
}
