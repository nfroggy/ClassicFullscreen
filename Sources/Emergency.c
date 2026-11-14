/* Tiger emergency exit. Separate from both the guest and graphics controller.
 * Retain the verified Classic task and recheck its identity before SIGKILL.
 * Only an explicit 'K' request terminates it. Stopping this watcher does not.
 */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach/mach.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef CLASSIC_EXECUTABLE
#define CLASSIC_EXECUTABLE                                                                         \
    "/System/Library/CoreServices/Classic Startup.app/Contents/Resources/TruBlueEnvironment"
#endif

static int expected_process(pid_t pid) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS, pid};
    char args[65536];
    size_t size = sizeof(args);
    if (sysctl(mib, 3, args, &size, NULL, 0) != 0 || size == 0)
        return 0;
    return memchr(args, 0, size) != NULL && strcmp(args, CLASSIC_EXECUTABLE) == 0;
}
static int alive(task_t task, pid_t expected) {
    int pid = 0;
    return pid_for_task(task, &pid) == KERN_SUCCESS && pid == expected;
}
int CFEmergency(int argc, char **argv, uid_t owner) {
    task_t task = MACH_PORT_NULL;
    struct stat before, after;
    char *end;
    long number;
    int fd, result = 0, requested = 0;
    if (getuid() != 0 || argc != 3) {
        fprintf(stderr, "Usage (root): classic_emergency_stop PID FIFO\n");
        return 2;
    }
    errno = 0;
    number = strtol(argv[1], &end, 10);
    if (errno || *end || number <= 1 || number > INT_MAX || !expected_process((pid_t)number)) {
        fprintf(stderr, "Emergency exit refused: unexpected Classic process.\n");
        return 1;
    }
    if (lstat(argv[2], &before) != 0 || !S_ISFIFO(before.st_mode) ||
        (before.st_mode & 0777) != 0600 || before.st_uid != owner) {
        fprintf(stderr, "Emergency exit refused: invalid request FIFO.\n");
        return 1;
    }
    fd = open(argv[2], O_RDWR | O_NONBLOCK | O_NOFOLLOW);
    if (fd < 0)
        return 1;
    if (fstat(fd, &after) != 0 || before.st_dev != after.st_dev || before.st_ino != after.st_ino) {
        close(fd);
        return 1;
    }
    if (task_for_pid(mach_task_self(), (pid_t)number, &task) != KERN_SUCCESS ||
        !alive(task, (pid_t)number) || !expected_process((pid_t)number)) {
        fprintf(stderr, "Emergency exit refused: cannot retain verified Classic task.\n");
        if (task != MACH_PORT_NULL)
            mach_port_deallocate(mach_task_self(), task);
        close(fd);
        return 1;
    }
    /* The guardian waits for this acknowledgement before accepting startup. */
    if (write(STDOUT_FILENO, "R", 1) != 1)
        result = 1;
    close(STDOUT_FILENO);
    while (!result && alive(task, (pid_t)number)) {
        fd_set reads;
        struct timeval timeout;
        int ready;
        char command;
        FD_ZERO(&reads);
        FD_SET(fd, &reads);
        timeout.tv_sec = 0;
        timeout.tv_usec = 100000;
        ready = select(fd + 1, &reads, NULL, NULL, &timeout);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            result = 1;
            break;
        }
        if (ready && read(fd, &command, 1) == 1 && command == 'K' && !requested) {
            /* Tiger's task_terminate rejects every task with BSD process
             * state (XNU 792.24.17 task.c). Use SIGKILL, like Classic's own
             * preference pane, with the retained task checked last. Never
             * retry against the PID after the original task disappears. */
            if (!expected_process((pid_t)number) || !alive(task, (pid_t)number))
                break;
            if (kill((pid_t)number, SIGKILL) != 0 && errno != ESRCH) {
                fprintf(stderr, "Classic force quit failed: %s\n", strerror(errno));
                result = 1;
            } else
                fprintf(stderr,
                        "Emergency shortcut: sent SIGKILL to the verified Classic process.\n");
            requested = 1;
        }
    }
    mach_port_deallocate(mach_task_self(), task);
    close(fd);
    return result;
}
