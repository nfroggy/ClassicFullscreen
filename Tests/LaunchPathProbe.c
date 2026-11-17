/* Read the same kernel path and effective UID used by the session guardian. */
#include <sys/types.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    int pid, pathMIB[3], processMIB[4];
    char path[65536];
    struct kinfo_proc info;
    size_t size;
    if (argc != 4) {
        fprintf(stderr, "Usage: LaunchPathProbe PID EXPECTED_PATH EXPECTED_UID\n");
        return 2;
    }
    pid = atoi(argv[1]);
    if (pid <= 1)
        return 2;
    pathMIB[0] = CTL_KERN; pathMIB[1] = KERN_PROCARGS; pathMIB[2] = pid;
    size = sizeof(path);
    if (sysctl(pathMIB, 3, path, &size, NULL, 0) || !size || !memchr(path, 0, size))
        return 1;
    processMIB[0] = CTL_KERN; processMIB[1] = KERN_PROC;
    processMIB[2] = KERN_PROC_PID; processMIB[3] = pid;
    size = sizeof(info);
    if (sysctl(processMIB, 4, &info, &size, NULL, 0) || size != sizeof(info))
        return 1;
    printf("PID %d UID %u path %s\n", pid, (unsigned)info.kp_eproc.e_ucred.cr_uid, path);
    return strcmp(path, argv[2]) || info.kp_eproc.e_ucred.cr_uid != (uid_t)atoi(argv[3]);
}
