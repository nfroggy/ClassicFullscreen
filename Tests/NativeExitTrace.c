/* Read-only foreground, host graphics and WindowServer window snapshot.
 * gcc Tests/NativeExitTrace.c -framework Carbon -o /tmp/native-exit-trace
 * sudo /tmp/native-exit-trace HOST_PID
 */
#include <Carbon/Carbon.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/time.h>
extern OSStatus CPSGetFrontProcess(ProcessSerialNumber *);
extern OSStatus CPSGetWindowOwner(unsigned, ProcessSerialNumber *);
extern int CGSMainConnectionID(void);
extern int CGSGetOnScreenWindowList(int, int, int, unsigned *, int *);
extern int CGSGetWindowList(int, int, int, unsigned *, int *);
extern int CGSGetWindowLevel(int, unsigned, int *);
extern int CGSGetWindowBounds(int, unsigned, CGRect *);
extern int CGSGetWindowOwner(int, unsigned, int *);
static unsigned word(task_t task, unsigned address) {
    unsigned result = 0; vm_size_t got = 0;
    if (address) vm_read_overwrite(task, address, 4, (vm_address_t)&result, &got);
    return result;
}
int main(int argc, char **argv) {
    ProcessSerialNumber self, front;
    unsigned ids[1024], visible[1024], ctx, i, j;
    task_t task;
    int ours, n = 0, v = 0;
    if ((argc != 2 && argc != 3) || task_for_pid(mach_task_self(), atoi(argv[1]), &task)) return 1;
    GetCurrentProcess(&self);
    ours = CGSMainConnectionID();
    CPSGetFrontProcess(&front);
    ctx = word(task, 0x5e0a3530);
    if (argc == 3) {
        unsigned last = 0, lastPixel = 0, ticks = 0;
        int seconds = atoi(argv[2]);
        double start, now;
        struct timeval t;
        volatile unsigned *pixel = NULL;
        CGDirectDisplayID d = CGMainDisplayID();
        if (CGDisplayBitsPerPixel(d) == 32)
            pixel = (volatile unsigned *)((char *)CGDisplayBaseAddress(d) +
                    CGDisplayBytesPerRow(d)*34 + 40);
        if (seconds < 1 || seconds > 10) return 2;
        gettimeofday(&t, NULL); start = t.tv_sec + t.tv_usec/1e6;
        do {
            unsigned value = pixel ? *pixel : 0;
            CPSGetFrontProcess(&front);
            gettimeofday(&t, NULL); now = t.tv_sec + t.tv_usec/1e6;
            if (front.lowLongOfPSN != last || value != lastPixel) {
                pid_t pid = -1;
                GetProcessPID(&front, &pid);
                printf("%.6f front=%08lx pid=%d pixel=%08x away=%u\n", now-start,
                    front.lowLongOfPSN, (int)pid, value, word(task, ctx+464));
                fflush(stdout); last = front.lowLongOfPSN; lastPixel = value;
            }
            usleep(1000); ticks++;
        } while (now - start < seconds);
        printf("samples=%u\n", ticks);
        return 0;
    }
    printf("front=%08lx:%08lx ctx=%08x connection=%08x away=%u pending=%u base=%08x/%08x\n",
           front.highLongOfPSN, front.lowLongOfPSN, ctx, word(task, ctx),
           word(task, ctx+464), word(task, ctx+468),
           word(task, word(task, ctx+16)+8), word(task, 0x824));
    CGSGetOnScreenWindowList(ours, 0, 1024, visible, &v);
    if (CGSGetWindowList(ours, 0, 1024, ids, &n) || n < 0 || n > 1024 || v < 0 || v > 1024) return 2;
    for (i = 0; i < (unsigned)n; i++) {
        ProcessSerialNumber owner = {0, 0};
        CGRect bounds;
        int connection = 0, level = 0, on = 0;
        CPSGetWindowOwner(ids[i], &owner);
        CGSGetWindowOwner(ours, ids[i], &connection);
        CGSGetWindowLevel(ours, ids[i], &level);
        if (CGSGetWindowBounds(ours, ids[i], &bounds)) continue;
        for (j = 0; j < (unsigned)v; j++) if (visible[j] == ids[i]) on = 1;
        printf("window=%u on=%d conn=%08x owner=%08lx:%08lx level=%d rect=%.0f,%.0f,%.0f,%.0f\n",
               ids[i], on, connection, owner.highLongOfPSN, owner.lowLongOfPSN, level,
               bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
    }
    return 0;
}
