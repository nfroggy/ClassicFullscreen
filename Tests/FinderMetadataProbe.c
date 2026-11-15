/* Tiger catalog diagnostic. Default is read-only; --same additionally submits
 * unchanged metadata through both APIs. Run as the session user, not root. */
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int i, j, same = argc > 1 && !strcmp(argv[1], "--same");
    if (geteuid() == 0) return 2;
    for (i = 1 + same; i < argc; i++) {
        FSRef ref; FSCatalogInfo info, after; FSSpec spec; CInfoPBRec pb;
        OSStatus err = FSPathMakeRef((const UInt8 *)argv[i], &ref, NULL);
        if (!err) err = FSGetCatalogInfo(&ref, kFSCatInfoNodeFlags |
            kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo | kFSCatInfoNodeID |
            kFSCatInfoVolume, &info, NULL, &spec, NULL);
        if (err) { printf("%s: read %ld\n", argv[i], (long)err); return 1; }
        memset(&pb, 0, sizeof(pb));
        pb.hFileInfo.ioNamePtr = spec.name; pb.hFileInfo.ioVRefNum = spec.vRefNum;
        pb.hFileInfo.ioDirID = spec.parID;
        err = PBGetCatInfoSync(&pb);
        if (err) { printf("%s: legacy read %ld\n", argv[i], (long)err); return 1; }
        printf("%s: flags=%x access=%x node=%lu legacyID=%ld parent=%ld metadata=",
            argv[i], info.nodeFlags, (unsigned char)pb.hFileInfo.ioACUser,
            info.nodeID, pb.hFileInfo.ioDirID, pb.hFileInfo.ioFlParID);
        for (j = 0; j < 16; j++) printf("%02x", ((UInt8 *)info.finderInfo)[j]);
        for (j = 0; j < 16; j++) printf("%02x", ((UInt8 *)info.extFinderInfo)[j]);
        puts("");
        if (same) {
            pb.hFileInfo.ioDirID = spec.parID;
            printf("  unchanged PBSetCatInfoSync=%d", PBSetCatInfoSync(&pb));
            printf(" FSSetCatalogInfo=%ld\n", (long)FSSetCatalogInfo(&ref,
                kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo, &info));
            err = FSGetCatalogInfo(&ref, kFSCatInfoFinderInfo | kFSCatInfoFinderXInfo,
                                  &after, NULL, NULL, NULL);
            if (err || memcmp(info.finderInfo, after.finderInfo, 16) ||
                       memcmp(info.extFinderInfo, after.extFinderInfo, 16)) return 1;
        }
    }
    return 0;
}
