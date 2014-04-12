/*
 * A10-watchdog
 * Activates the Allwinner SoC's watchdog to automatically
 * reboot the system in the case of a fatal deadlock.
 * For example, when stress testing an overclocked system.
 *
 * Author: Siarhei Siamashka
 * License: GPL
 *
 * Based on the code from the A10-meminfo tool originally
 * authored by Floris Bos.
 *
 * Compile with: gcc -static -o a10-watchdog-static a10-watchdog.c
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dirent.h>
#include <fcntl.h>
#include <assert.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdint.h>
#include <signal.h>

#define TIMER_BASE 0x01c20000

typedef uint32_t u32;

struct sunxi_timer_reg {
	u32 dummy1[0xc90 / 4];
	volatile u32 wdog_ctrl_reg;
	volatile u32 wdog_mode_reg;
};

int mem_fd = -1;

volatile unsigned *map_physical_memory(uint32_t addr, size_t len)
{
    volatile unsigned *mem;

    if (mem_fd == -1 && (mem_fd = open("/dev/mem", O_RDWR|O_SYNC) ) < 0)
    {
        perror("opening /dev/mem");
        exit(1);
    }

    mem = (volatile unsigned *) mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, (off_t) addr);
    
    if (mem == MAP_FAILED)
    {
        perror("mmap");
        exit (1);
    }

    return mem;
}

volatile struct sunxi_timer_reg *r;

void deactivate_watchdog(int signum)
{
    r->wdog_mode_reg = 0;
    exit(0);
}

static void simple_watchdog(void)
{
    signal(SIGINT, deactivate_watchdog);
    signal(SIGTERM, deactivate_watchdog);

    r->wdog_mode_reg = (5 << 3) | 3;

    while (1)
    {
        sleep(1);
        r->wdog_ctrl_reg = (0x0a57 << 1) | 1;
    }
}

static void deadloop()
{
    while (1) {}
}

int main(int argc, char **argv)
{
    int pid, status, w;
    r  = (volatile struct sunxi_timer_reg *) map_physical_memory(TIMER_BASE, 4096);

    if (argc < 2)
    {
        printf("Usage: a10-watchdog [program] <arg1> <arg2> ... <argN>\n");
        printf("\n");
        printf("This executes the specified program and keeps kicking\n");
        printf("the Allwinner A10 hardware watchdog while the program is\n");
        printf("still running. If the program fails for any reason (segfaults\n");
        printf("or returns nonzero exit code) or the processor deadlocks,\n");
        printf("then the hardware watchdog activates and reboots the system.\n");
        printf("\n");
        printf("Right now just waiting for a hardware related failure.\n");
        printf("Press Ctrl-C to exit.\n");
        simple_watchdog();
    }

    r->wdog_mode_reg = (5 << 3) | 3;

    if ((pid = fork()) == 0)
    {
        execv(argv[1], &argv[1]);
        exit(1);
    }
    else
    {
        while (1)
        {
            if ((w = waitpid(pid, &status, WNOHANG)) != 0)
            {
                if (w == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0)
                {
                    r->wdog_mode_reg = 0;
                    exit(0);
                }
                else
                {
                    deadloop();
                }
            }

            sleep(1);
            r->wdog_ctrl_reg = (0x0a57 << 1) | 1;
        }
    }

    return 0;
}
