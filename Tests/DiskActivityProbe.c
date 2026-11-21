/* Build as a Classic CFM application with Universal Interfaces (e.g. Retro68
 * add_application). Run from Finder in an idle, writable test folder. Writes
 * its report beside itself. Only the temporary data file it creates is deleted. */
#include <Devices.h>
#include <Events.h>
#include <Files.h>
#include <Processes.h>
#include <stdio.h>
#include <string.h>

static char report[2048];
static int used, failures;
static char buffer[64];

static UInt32 diskTicks(void) {
    /* Read the same field Control Strip reads, without generating any I/O. */
    return *(volatile UInt32 *)(*(volatile UInt32 *)0xd18 + 0x1e);
}

static UInt32 beforeIO(void) {
    UInt32 start = TickCount();
    while (TickCount() - start < 3) {}
    return diskTicks();
}

static void check(const char *name, OSErr result, OSErr expected,
                  long bytes, long expectedBytes, UInt32 before) {
    UInt32 after = diskTicks();
    int ok = result == expected && (expectedBytes < 0 || bytes == expectedBytes) &&
        ((after != before) == (expectedBytes > 0));
    if (!ok) ++failures;
    used += sprintf(report + used, "%s %s: result %d, bytes %ld, ticks %lu -> %lu\r",
                    ok ? "PASS" : "FAIL", name, result, bytes,
                    (unsigned long)before, (unsigned long)after);
}

static OSErr newFile(const FSSpec *app, const char *label, FSSpec *spec, short *ref) {
    Str63 name;
    OSErr err;
    name[0] = sprintf((char *)name + 1, "%s %lu", label, (unsigned long)TickCount());
    err = FSMakeFSSpec(app->vRefNum, app->parID, name, spec);
    if (err != fnfErr) return err ? err : dupFNErr;
    err = FSpCreate(spec, 'ttxt', 'TEXT', smSystemScript);
    if (!err) err = FSpOpenDF(spec, fsRdWrPerm, ref);
    return err;
}

static void classicIO(short ref) {
    ParamBlockRec pb;
    OSErr err;
    long bytes;
    UInt32 before;
    memset(&pb, 0, sizeof(pb));
    pb.ioParam.ioRefNum = ref;
    pb.ioParam.ioBuffer = buffer;
    pb.ioParam.ioReqCount = 16;
    pb.ioParam.ioPosMode = fsFromStart;

    before = beforeIO(); bytes = 32;
    err = FSRead(ref, &bytes, buffer);
    check("read", err, noErr, bytes, 32, before);
    before = beforeIO(); bytes = 16;
    err = FSWrite(ref, &bytes, buffer);
    check("write", err, noErr, bytes, 16, before);
    before = beforeIO(); bytes = 0;
    err = FSRead(ref, &bytes, buffer);
    check("empty read", err, noErr, bytes, 0, before);
    before = beforeIO(); bytes = 32;
    err = FSRead(ref, &bytes, buffer);
    check("partial EOF", err, eofErr, bytes, 16, before);
    before = beforeIO(); bytes = 1;
    err = FSRead(ref, &bytes, buffer);
    check("EOF", err, eofErr, bytes, 0, before);
    before = beforeIO(); bytes = 1;
    err = FSRead(32766, &bytes, buffer);
    /* The File Manager leaves ioActCount unspecified for an invalid refnum. */
    check("invalid file", err, rfNumErr, bytes, -1, before);

    before = beforeIO(); PBReadAsync(&pb);
    while (pb.ioParam.ioResult > 0) {}
    check("async read", pb.ioParam.ioResult, noErr, pb.ioParam.ioActCount, 16, before);
    before = beforeIO(); PBWriteAsync(&pb);
    while (pb.ioParam.ioResult > 0) {}
    check("async write", pb.ioParam.ioResult, noErr, pb.ioParam.ioActCount, 16, before);
}

static OSErr forkIO(const FSSpec *data) {
    FSForkIOParam pb;
    FSRef file;
    short ref;
    UInt32 before;
    OSErr err = FSpMakeFSRef(data, &file);
    if (!err) err = FSOpenFork(&file, 0, NULL, fsRdWrPerm, &ref);
    if (err) return err;
    memset(&pb, 0, sizeof(pb));
    pb.forkRefNum = ref;
    pb.buffer = buffer;
    pb.requestCount = 12;
    pb.positionMode = fsFromStart;
    before = beforeIO(); err = PBReadForkSync(&pb);
    check("fork read", err, noErr, pb.actualCount, 12, before);
    before = beforeIO(); err = PBWriteForkSync(&pb);
    check("fork write", err, noErr, pb.actualCount, 12, before);
    before = beforeIO(); PBReadForkAsync(&pb);
    while (pb.ioResult > 0) {}
    check("async fork read", pb.ioResult, noErr, pb.actualCount, 12, before);
    before = beforeIO(); PBWriteForkAsync(&pb);
    while (pb.ioResult > 0) {}
    check("async fork write", pb.ioResult, noErr, pb.actualCount, 12, before);
    return FSCloseFork(ref);
}

int main(void) {
    FSSpec app, data, output;
    ProcessSerialNumber self = {0, kCurrentProcess};
    ProcessInfoRec info;
    long bytes = sizeof(buffer);
    short ref, resultRef;
    OSErr err;
    memset(&info, 0, sizeof(info));
    info.processInfoLength = sizeof(info);
    info.processAppSpec = &app;
    if (GetProcessInformation(&self, &info) ||
        newFile(&app, "Disk Activity Results", &output, &resultRef)) return 1;
    err = newFile(&app, "Disk Activity Data", &data, &ref);
    if (!err) {
        err = FSWrite(ref, &bytes, buffer);
        if (!err) err = SetFPos(ref, fsFromStart, 0);
        if (!err) classicIO(ref);
        FSClose(ref);
        if (!err) err = forkIO(&data);
        FSpDelete(&data);
    }
    used += sprintf(report + used, "Setup/cleanup result %d, %d failed checks\r", err, failures);
    bytes = used;
    if (FSWrite(resultRef, &bytes, report)) ++failures;
    FSClose(resultRef);
    return err || failures;
}
