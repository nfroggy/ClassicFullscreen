/* Read-only fullscreen window/Drag Manager inspection. Run as root with PID. */
#include <Carbon/Carbon.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
extern OSStatus CPSGetWindowOwner(unsigned int, ProcessSerialNumber *);
extern int CGSMainConnectionID(void);
extern int CGSGetOnScreenWindowList(int, int, int, unsigned int *, int *);
extern int CGSGetWindowLevel(int, unsigned int, int *);
extern int CGSGetWindowTags(int, unsigned int, unsigned int *, int);
extern int CGSGetWindowBounds(int, unsigned int, CGRect *);
static task_t task;
static unsigned word(unsigned address) {
    unsigned value = 0;
    vm_size_t got = 0;
    if (!address || vm_read_overwrite(task, address, 4, (vm_address_t)&value, &got) || got != 4)
        return 0;
    return value;
}
int main(int argc, char **argv) {
    ProcessSerialNumber self;
    unsigned ctx, drag, ids[1024], i;
    int ours, count = 0;
    if (argc != 2 || geteuid() || task_for_pid(mach_task_self(), atoi(argv[1]), &task)) return 1;
    GetCurrentProcess(&self);
    ours = CGSMainConnectionID();
    ctx = word(0x5e0a3530);
    printf("ctx=%08x connection=%x desktop=%x window=%x cover=%x menubar=%x fullscreen=%u away=%u\n",
           ctx,word(ctx),word(ctx+8),word(ctx+4),word(word(ctx+16)+124),
           word(ctx+388),word(ctx+460),word(ctx+464));
    drag = word(word(0x2b6)+0x118);
    printf("dragGlobals=%08x nativeBridge=%u receiveHandlers=%u trackingHandlers=%u\n",
           drag,word(drag+0x15e),word(drag+0x162),word(drag+0x166));
    if (CGSGetOnScreenWindowList(ours, 0, 1024, ids, &count) || count < 0 || count > 1024) return 2;
    for (i = 0; i < (unsigned)count; i++) {
        CGRect r;
        ProcessSerialNumber owner = {0,0};
        int level = 0, err;
        unsigned tags[4] = {0,0,0,0};
        if (CGSGetWindowBounds(ours, ids[i], &r)) continue;
        CGSGetWindowLevel(ours, ids[i], &level);
        CGSGetWindowTags(ours, ids[i], tags, 32);
        err = CPSGetWindowOwner(ids[i], &owner);
        printf("window=%08x owner=%08lx/%d level=%d tags=%08x/%08x bounds=%.0f,%.0f,%.0f,%.0f\n",
               ids[i], owner.lowLongOfPSN, err, level, tags[0], tags[1],
               r.origin.x, r.origin.y, r.size.width, r.size.height);
    }
    mach_port_deallocate(mach_task_self(),task);
    return 0;
}
