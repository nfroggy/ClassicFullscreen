/* Tiger display-format inventory; "check DEPTH" verifies the current format.
 * Explicit "set DEPTH" changes only depth for the login session, using the
 * configuration API so it is not reverted when this helper exits. Run set
 * only with Classic stopped. No permanent preferences or automatic restore. */
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int value(CFDictionaryRef mode, CFStringRef key) {
    int n = 0;
    CFNumberRef number = CFDictionaryGetValue(mode, key);
    if (number) CFNumberGetValue(number, kCFNumberIntType, &n);
    return n;
}
int main(int argc, char **argv) {
    CGDirectDisplayID display = CGMainDisplayID();
    CFArrayRef modes = CGDisplayAvailableModes(display);
    int seen[65] = {0}; CFIndex i;
    if (argc != 1) {
        int depth = argc == 3 ? atoi(argv[2]) : 0;
        boolean_t exact = false;
        CFDictionaryRef mode;
        if (argc != 3 || (strcmp(argv[1], "set") && strcmp(argv[1], "check")) ||
            (depth != 8 && depth != 16 && depth != 32) ||
            CGDisplayIsCaptured(display)) return 2;
        if (!strcmp(argv[1], "set")) {
            CGDisplayConfigRef config = NULL;
            mode = CGDisplayBestModeForParameters(display, depth,
                    CGDisplayPixelsWide(display), CGDisplayPixelsHigh(display), &exact);
            if (!mode || !exact) return 3;
            if (CGBeginDisplayConfiguration(&config)) return 4;
            if (CGConfigureDisplayMode(config, display, mode)) {
                CGCancelDisplayConfiguration(config); return 4;
            }
            if (CGCompleteDisplayConfiguration(config, kCGConfigureForSession)) return 4;
        }
        if (CGDisplayBitsPerPixel(display) != (unsigned)depth) return 5;
    }
    printf("Current: %lux%lu depth=%lu stride=%lu\n",
           (unsigned long)CGDisplayPixelsWide(display),
           (unsigned long)CGDisplayPixelsHigh(display),
           (unsigned long)CGDisplayBitsPerPixel(display),
           (unsigned long)CGDisplayBytesPerRow(display));
    if (argc != 1) return 0;
    if (!modes) return 1;
    for (i = 0; i < CFArrayGetCount(modes); i++) {
        CFDictionaryRef mode = CFArrayGetValueAtIndex(modes, i);
        int depth = value(mode, kCGDisplayBitsPerPixel);
        if (depth > 0 && depth <= 64 && !seen[depth]) {
            printf("Available depth: %d\n", depth); seen[depth] = 1;
        }
    }
    return 0;
}
