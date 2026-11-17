/* Tiger idle-sleep diagnostic. status only reads host state; expire-idle
 * expires the deadline in an EMPTY test session. noop sends an Apple event
 * without activating its target. Run as the console user, with sudo for the
 * Mach read/deadline modes. Not part of the application build. */
#include <Carbon/Carbon.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static task_t task;
static unsigned word(unsigned address) {
    unsigned value = 0; vm_size_t got = 0;
    if (vm_read_overwrite(task, address, 4, (vm_address_t)&value, &got) || got != 4)
        exit(2);
    return value;
}
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    if (!strcmp(argv[1], "status") || !strcmp(argv[1], "expire-idle")) {
        unsigned ctx;
        if (task_for_pid(mach_task_self(), atoi(argv[2]), &task)) return 2;
        ctx = word(0x5e0a3530);
        if (!strcmp(argv[1], "expire-idle")) {
            /* Empty diagnostic session only. Expire the existing idle deadline;
             * let Tiger's scheduler perform its real sleep transition. */
            unsigned deadline[2] = {0, 0};
            if (word(0x5e0837bc) != 0x40 || word(ctx+464) != 1 ||
                word(ctx+468) || word(word(ctx+384))) return 2;
            if (vm_write(task, 0x5e0837c0, (vm_offset_t)deadline, sizeof(deadline))) return 2;
        }
        printf("sleep=%u mode=%x tick=%u away=%u pending=%u request=%u trace=%u mailbox=%u/%u\n",
               word(0x5e0837b4), word(0x5e0837bc), word(0x16a), word(ctx+464),
               word(ctx+468), word(word(ctx+384)), word(0x5e0a4400),
               word(0x5e0a4104), word(0x5e0a4108));
        return 0;
    } else {
        ProcessSerialNumber self, target = {0, strtoul(argv[2], NULL, 16)};
        AEAddressDesc address = {typeNull, NULL};
        AppleEvent event = {typeNull, NULL};
        OSStatus err;
        GetCurrentProcess(&self);
        if (!strcmp(argv[1], "wake")) err = WakeUpProcess(&target);
        else if (!strcmp(argv[1], "noop")) {
            err = AECreateDesc(typeProcessSerialNumber, &target, sizeof(target), &address);
            if (!err) err = AECreateAppleEvent('misc', 'noop', &address,
                                             kAutoGenerateReturnID, kAnyTransactionID, &event);
            if (!err) err = AESendMessage(&event, NULL,
                kAENoReply | kAENeverInteract, 60);
            AEDisposeDesc(&event); AEDisposeDesc(&address);
        } else return 2;
        printf("%s: %ld\n", argv[1], (long)err);
        return err != 0;
    }
}
