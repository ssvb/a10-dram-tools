/*
 * a10-stdin-watchdog
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
 * Compile with: gcc -o a10-stdin-watchdog a10-stdin-watchdog.c -pthread
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
#include <pthread.h>

#define MAGIC_NUMBER -1

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

pthread_mutex_t watchdog_mutex = PTHREAD_MUTEX_INITIALIZER;
volatile int watchdog_timeout_upper_limit;
volatile int watchdog_timeout_counter;

static void *watchdog_thread_function(void *ctx)
{
    r  = (volatile struct sunxi_timer_reg *) map_physical_memory(TIMER_BASE, 4096);

    /* Enable the hardware watchdog */
    r->wdog_mode_reg = (5 << 3) | 3;

    while (1)
    {
        pthread_mutex_lock(&watchdog_mutex);
        if (watchdog_timeout_counter == MAGIC_NUMBER)
        {
            /* Disable the hardware watchdog and exit */
            r->wdog_mode_reg = 0;
            exit(0);
        }
        if (watchdog_timeout_counter == 0)
        {
            /* The timer has elapsed, we are dead */
            printf("Boom!\n");
            while (1) {}
        }
        watchdog_timeout_counter--;
        pthread_mutex_unlock(&watchdog_mutex);

        sleep(1);
        r->wdog_ctrl_reg = (0x0a57 << 1) | 1;
    }
}

int main(int argc, char **argv)
{
    pthread_t watchdog_thread;

    if (argc < 2 || sscanf(argv[1], "%d", &watchdog_timeout_counter) != 1)
    {
        printf("Usage: a10-stdin-watchdog [initial_timeout_in_seconds]\n");
        printf("\n");
        printf("This program activates the Allwinner A10 hardware watchdog\n");
        printf("and sets it to trigger after a timeout has elapsed. The initial\n");
        printf("timeout value is provided in the command line. This value\n");
        printf("also sets the upper timeout limit, which can't be overrided!\n");
        printf("\n");
        printf("Also it tries to read numbers from the standard input.\n");
        printf("Whenever a new number is read, it is interpreted as a new\n");
        printf("watchdog timeout value (in seconds). If the magic value\n");
        printf("%d is read, then the watchdog is deactivated.\n", MAGIC_NUMBER);
        exit(1);
    }
    watchdog_timeout_upper_limit = watchdog_timeout_counter;

    pthread_create(&watchdog_thread, NULL, watchdog_thread_function, NULL);

    while (1)
    {
        int new_counter;
        if (scanf("%i", &new_counter) == 1)
        {
            if (new_counter != MAGIC_NUMBER)
            {
                if (new_counter < 0)
                    new_counter = 0;
                if (new_counter > watchdog_timeout_upper_limit)
                    new_counter = watchdog_timeout_upper_limit;
            }
            pthread_mutex_lock(&watchdog_mutex);
            watchdog_timeout_counter = new_counter;
            pthread_mutex_unlock(&watchdog_mutex);
        }
    }

    return 0;
}
