#import "CFClassic.h"
#include <mach/vm_attributes.h>

extern const unsigned char CFDiskActivity[], CFDiskContinuation[];
enum { FileManagerCompletion = 0x3e6, DiskBridgeOffset = 0x200 };

/* The shared filesystem's exit path has restored A0 to the caller's PB
 * and normalized D0 before calling through the low-memory vector. */
static uint32_t fileManagerCompletion(task_t task) {
    uint32_t rom = CFWord(task, 0x2ae), call[2];
    vm_size_t bytes = 0;
    if (!rom || rom > UINT32_MAX - 0x1d03c ||
        vm_read_overwrite(task, rom + 0x1d034, sizeof(call), (vm_address_t)call, &bytes) ||
        bytes != sizeof(call) || call[0] != 0x4eb081e1 || call[1] != 0x03e64e75)
        return 0;
    uint32_t previous = CFWord(task, FileManagerCompletion);
    return (previous & 1) ? 0 : previous;
}

/* The low-memory vector is only word-aligned. Pause the guest while
 * exchanging it, and leave callbacks installed by other software in place. */
static BOOL exchangeDiskCompletion(task_t task, uint32_t expected, uint32_t replacement) {
    if (task_suspend(task) != KERN_SUCCESS) return NO;
    BOOL changed = NO;
    @try {
        changed = CFWord(task, FileManagerCompletion) == expected &&
            vm_write(task, FileManagerCompletion, (vm_offset_t)&replacement, 4) == KERN_SUCCESS;
    } @finally {
        CFRequire(task_resume(task) == KERN_SUCCESS, @"Cannot resume Classic after updating File Manager");
    }
    return changed;
}

/* NativePowerMgrLib is loaded from Mac OS ROM, at a relocatable address.
 * Resolve its CFM vector through the installed Sleep trap descriptor. Change
 * only the shared Sleep entry, leaving its TOC and SleepQInstall/Remove alone.
 * BALForceSleep is a separate host service table slot, not this guest API. */
@implementation CFPower (Bridge)
- (void)installBridge:(task_t)task {
    uint32_t pm = CFWord(task, 0xd18);
    uint32_t descriptor = CFWord(task, pm + 0x396);
    uint32_t vector = CFWord(task, descriptor + 20);
    uint32_t dispatch = CFWord(task, vector), toc = CFWord(task, vector + 4);
    unsigned char bytes[196];
    CFRequire(pm && descriptor && vector && dispatch && toc, @"Missing Classic Power Manager");
    CFReadMemory(task, dispatch, bytes, sizeof(bytes));
    CFRequire([CFDigest([NSData dataWithBytes:bytes length:sizeof(bytes)])
        isEqual:@"9269b005aca3585f95ca515afab41050"], @"Unsupported Sleep dispatcher");
    sleepVector = toc + 0x304;
    originalSleep = CFWord(task, sleepVector);
    CFRequire(originalSleep == dispatch + 0x2d04 && CFWord(task, sleepVector + 4) == toc,
              @"Unexpected Sleep transition vector");
    CFReadMemory(task, originalSleep, bytes, 0x70);
    CFRequire([CFDigest([NSData dataWithBytes:bytes length:0x70])
        isEqual:@"b1a1134a68dc9129469405c4813cdd02"], @"Unsupported Power Manager Sleep routine");
    CFRequire(CFWord(task, 0x5e0823fc) == 0x5e011fc0, @"Unexpected BALForceSleep service");
    NSString *directory = [CFResources stringByAppendingPathComponent:@"Patches"];
    NSDictionary *spec = [NSDictionary dictionaryWithContentsOfFile:
        [directory stringByAppendingPathComponent:@"Sleep.plist"]];
    NSData *code = CFReadFile([directory stringByAppendingPathComponent:@"Sleep.bin"]);
    CFRequire([code length] == 0x180 && [[spec objectForKey:@"payloadMD5"] isEqual:CFDigest(code)] &&
              [[spec objectForKey:@"requestEntry"] unsignedIntValue] == 0 &&
              [[spec objectForKey:@"notificationEntry"] unsignedIntValue] == 0x100,
              @"Invalid runtime sleep payload");
    bridgeTask = task;
    CFRequire(vm_allocate(task, &bridgeCode, 4096, VM_FLAGS_ANYWHERE) == KERN_SUCCESS,
              @"Cannot allocate sleep bridge");
    CFRequire(vm_write(task, bridgeCode, (vm_offset_t)[code bytes], [code length]) == KERN_SUCCESS,
              @"Cannot load sleep bridge");
    vm_address_t diskEntry = bridgeCode + DiskBridgeOffset;
    size_t diskSize = (uintptr_t)CFDiskContinuation - (uintptr_t)CFDiskActivity;
    originalDiskCompletion = fileManagerCompletion(task);
    if (originalDiskCompletion) {
        CFRequire(diskSize <= 4096 - DiskBridgeOffset - 4 &&
                  vm_write(task, diskEntry, (vm_offset_t)CFDiskActivity, diskSize) == KERN_SUCCESS &&
                  vm_write(task, diskEntry + diskSize, (vm_offset_t)&originalDiskCompletion, 4) == KERN_SUCCESS,
                  @"Cannot prepare File Manager disk activity callback");
    }
    vm_machine_attribute_val_t attribute = MATTR_VAL_CACHE_SYNC;
    CFRequire(vm_machine_attribute(task, bridgeCode, 4096, MATTR_CACHE, &attribute) == 0 &&
              vm_protect(task, bridgeCode, 4096, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == 0,
              @"Cannot prepare PowerPC sleep instructions");
    /* Both targets are complete before either aligned pointer is published.
     * The mailbox remains disabled until the controller finishes arming it. */
    uint32_t entry = bridgeCode + 0x100;
    CFRequire(vm_write(task, 0x5e0823fc, (vm_offset_t)&entry, 4) == 0,
              @"Cannot install host sleep notification guard");
    bridgePublished = YES;
    entry = bridgeCode;
    CFRequire(vm_write(task, sleepVector, (vm_offset_t)&entry, 4) == 0,
              @"Cannot install Power Manager sleep request bridge");
    if (originalDiskCompletion && exchangeDiskCompletion(task, originalDiskCompletion, diskEntry))
        CFSLog(@"File Manager transfers now report disk activity to the guest Power Manager");
    else {
        originalDiskCompletion = 0;
        CFSLog(@"File Manager completion hook unavailable; disk activity reporting skipped");
    }
    CFSLog(@"Power Manager bridge: Sleep vector %08x (%08x), runtime code %08x",
           sleepVector, originalSleep, (unsigned)bridgeCode);
}
- (void)removeBridge {
    if (!bridgeTask) return;
    uint32_t disabled = 0;
    vm_write(bridgeTask, CF_SLEEP_MAIL, (vm_offset_t)&disabled, 4);
    if (bridgePublished) {
        @try {
            if (originalDiskCompletion)
                exchangeDiskCompletion(bridgeTask, bridgeCode + DiskBridgeOffset, originalDiskCompletion);
            if (CFWord(bridgeTask, sleepVector) == bridgeCode)
                vm_write(bridgeTask, sleepVector, (vm_offset_t)&originalSleep, 4);
            uint32_t original = 0x5e011fc0;
            if (CFWord(bridgeTask, 0x5e0823fc) == bridgeCode + 0x100)
                vm_write(bridgeTask, 0x5e0823fc, (vm_offset_t)&original, 4);
        } @catch (id e) { (void)e; /* Guest may already have exited. */ }
        /* A guest thread may still be returning from a leaf. Its one RX page
         * belongs to this Classic process and is reclaimed when it exits. */
    } else if (bridgeCode) vm_deallocate(bridgeTask, bridgeCode, 4096);
    bridgeTask = 0;
}
@end
