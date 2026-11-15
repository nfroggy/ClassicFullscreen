/* ClassicFullscreen: Tiger / GCC 4.0 / manual Objective-C memory management. */
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
#include <mach/mach.h>
#include <signal.h>
#include <sys/types.h>

#define CF_HOST                                                                                    \
    @"/System/Library/CoreServices/Classic Startup.app/Contents/Resources/TruBlueEnvironment"
#define CF_RUN @"/var/run/classic-fullscreen-switch"
#define CF_MAIL 0x5e0a4100U
extern uid_t CFUserID;
extern gid_t CFGroupID;
extern NSString *CFUserName;
extern NSString *CFSystemFolder;
void CFConfigureUser(uid_t user);
void CFRequireConsoleUser(void);
uid_t CFProcessUserID(pid_t pid);
NSString *CFConfiguredSystemFolder(void);
void CFSetSystemFolder(NSString *folder);
void CFEnsureSystemFolder(void);
NSString *CFFinderPath(void);
NSData *CFUserOutput(NSArray *arguments);
extern NSString *CFExecutable;
extern NSString *CFResources;
extern volatile sig_atomic_t CFInterrupted;
void CFFail(NSString *format, ...) __attribute__((noreturn));
void CFSLog(NSString *format, ...);
void CFRequire(BOOL ok, NSString *message);
BOOL CFSupportedDisplayDepth(unsigned depth);
double CFMonotonicTime(void);
NSString *CFDigest(NSData *data);
NSData *CFReadFile(NSString *path);
void CFWriteAll(int fd, const void *bytes, size_t length);
void CFWriteState(char value);
char CFReadState(void);
BOOL CFReadable(int fd, double timeout);
NSString *CFProcessPath(pid_t pid);
NSArray *CFClassicPIDs(void);
NSArray *CFProcessesAtPath(NSString *path);
BOOL CFTaskAlive(task_t task, pid_t pid);
task_t CFClassicTask(pid_t pid);
void CFReadMemory(task_t task, uint32_t address, void *out, size_t size);
uint32_t CFWord(task_t task, uint32_t address);
pid_t CFSpawn(NSArray *arguments, BOOL asUser, int outputFD);
int CFWait(pid_t child, double seconds, BOOL terminateOnTimeout);
int CFUserAction(NSArray *arguments, double timeout);
int CFActions(NSArray *arguments);
int CFUI(BOOL authorize, BOOL recovery);
int CFGuardian(pid_t ui, BOOL recovery);
int CFController(pid_t pid);
int CFEmergency(int argc, char **argv, uid_t owner);
int CFSelfTests(NSString *fixtures);
void CFPreflight(void);
void CFVerifyCoreGraphics(NSData *data);

@interface CFPatches : NSObject {
    NSArray *specs;
    NSString *root;
    NSString *systemFolder;
}
- (id)initWithRoot:(NSString *)prefix;
- (id)initWithRoot:(NSString *)prefix systemFolder:(NSString *)folder;
- (NSArray *)specifications;
- (NSDictionary *)spec:(NSString *)name;
- (NSString *)pathFor:(NSDictionary *)spec;
- (NSArray *)writeSegmentsForSpec:(NSDictionary *)spec;
- (NSData *)transform:(NSData *)base spec:(NSDictionary *)spec;
- (void)verifyBaseline;
- (void)install:(NSString *)name enabled:(BOOL)enabled;
@end

typedef enum { CFNoFront, CFGuestFront, CFNativeFront, CFProxyFront } CFFrontKind;
typedef struct {
    CFFrontKind kind;
    UInt32 psn;
    pid_t pid;
    BOOL foreground;
} CFFront;
CFFront CFFrontProcess(pid_t host);
BOOL CFFullscreenRect(CGRect r, CGRect d);
BOOL CFDrawableRect(CGRect r, CGRect d);

/* Exact Tiger 32-bit private APIs verified against the tested CoreGraphics. */
extern int CGSMainConnectionID(void);
extern int CGSGetConnectionIDForPSN(int, const ProcessSerialNumber *, int *);
extern int CGSGetConnectionProperty(int, int, CFStringRef, CFTypeRef *);
extern int CGSGetOnScreenWindowList(int, int, int, unsigned int *, int *);
extern int CGSGetWindowList(int, int, int, unsigned int *, int *);
extern int CGSGetWindowBounds(int, unsigned int, CGRect *);
extern int CGSGetWindowLevel(int, unsigned int, int *);
extern int CGSGetSurfaceCount(int, unsigned int, unsigned int *);
extern int CGSGetSurfaceList(int, unsigned int, int, unsigned int *, int *);
extern int CGSGetSurfaceBounds(int, unsigned int, unsigned int, CGRect *);
extern int CGSGetWindowShape(int, unsigned int, void **);
extern int CGSNewRegionWithRect(const CGRect *, void **);
extern int CGSNewEmptyRegion(void **);
extern int CGSUnionRegion(void *, void *, void **);
extern int CGSIntersectRegion(void *, void *, void **);
extern int CGSDiffRegion(void *, void *, void **);
extern int CGSReleaseRegion(void *);
extern int CGSGetRegionData(void *, const void **, unsigned int *);
extern OSStatus CPSGetWindowOwner(unsigned int, ProcessSerialNumber *);
extern OSStatus CPSGetFrontProcess(ProcessSerialNumber *);
extern OSStatus CPSGetProcessInfo(const ProcessSerialNumber *, void *, char *, int, void *, char *,
                                  int);
extern OSStatus CPSSetProcessName(const ProcessSerialNumber *, const char *);
extern OSStatus CPSSetProcessToBringForwardAtNextApplicationExit(UInt32, UInt32);
