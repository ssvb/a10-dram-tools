/*
 * A10-set-tpr3
 * A program to tweak the DDR3 PHY settings at runtime.
 * The RK30XX manual says that these settings can be applied
 * without resetting PHY, but recommends to avoid doing
 * dram reads/writes for a while immediately after this change.
 * Maybe this is not totally reliable, but works fine most
 * of the time.
 *
 * Author: Siarhei Siamashka
 * License: GPL
 *
 * Based on the code from the A10-meminfo tool originally
 * authored by Floris Bos.
 *
 * Compile with: gcc -static -o a10-set-tpr3-static a10-set-tpr3.c
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

#define SUNXI_DRAMC_BASE    0x01c01000
#define SUNXI_CCM_BASE      0x01C20000

#define CCM_PLL5_FACTOR_M    0
#define CCM_PLL5_FACTOR_K    4
#define CCM_PLL5_FACTOR_N    8
#define CCM_PLL5_FACTOR_P   16

#define CCM_PLL5_FACTOR_M_SIZE 0x03
#define CCM_PLL5_FACTOR_K_SIZE 0x03
#define CCM_PLL5_FACTOR_N_SIZE 0x1f
#define CCM_PLL5_FACTOR_P_SIZE 0x03

typedef uint32_t u32;
typedef uint8_t u8;

/*
 * Memory header definition copied from u-boot arch/arm/include/asm/arch-sunxi/dram.h
 * (C) Copyright 2007-2012 Allwinner Technology Co., Ltd. <www.allwinnertech.com>)
 */
struct sunxi_dram_reg {
	u32 ccr;		/* 0x00 controller configuration register */
	u32 dcr;		/* 0x04 dram configuration register */
	u32 iocr;		/* 0x08 i/o configuration register */
	u32 csr;		/* 0x0c controller status register */
	u32 drr;		/* 0x10 dram refresh register */
	u32 tpr0;		/* 0x14 dram timing parameters register 0 */
	u32 tpr1;		/* 0x18 dram timing parameters register 1 */
	u32 tpr2;		/* 0x1c dram timing parameters register 2 */
	u32 gdllcr;		/* 0x20 global dll control register */
	u8 res0[0x28];
	u32 rslr0;		/* 0x4c rank system latency register */
	u32 rslr1;		/* 0x50 rank system latency register */
	u8 res1[0x8];
	u32 rdgr0;		/* 0x5c rank dqs gating register */
	u32 rdgr1;		/* 0x60 rank dqs gating register */
	u8 res2[0x34];
	u32 odtcr;		/* 0x98 odt configuration register */
	u32 dtr0;		/* 0x9c data training register 0 */
	u32 dtr1;		/* 0xa0 data training register 1 */
	u32 dtar;		/* 0xa4 data training address register */
	u32 zqcr0;		/* 0xa8 zq control register 0 */
	u32 zqcr1;		/* 0xac zq control register 1 */
	u32 zqsr;		/* 0xb0 zq status register */
	u32 idcr;		/* 0xb4 initializaton delay configure reg */
	u8 res3[0x138];
	u32 mr;			/* 0x1f0 mode register */
	u32 emr;		/* 0x1f4 extended mode register */
	u32 emr2;		/* 0x1f8 extended mode register */
	u32 emr3;		/* 0x1fc extended mode register */
	u32 dllctr;		/* 0x200 dll control register */
	volatile u32 dllcr[5];	/* 0x204 dll control register 0(byte 0) */
	/* 0x208 dll control register 1(byte 1) */
	/* 0x20c dll control register 2(byte 2) */
	/* 0x210 dll control register 3(byte 3) */
	/* 0x214 dll control register 4(byte 4) */
	u32 dqtr0;		/* 0x218 dq timing register */
	u32 dqtr1;		/* 0x21c dq timing register */
	u32 dqtr2;		/* 0x220 dq timing register */
	u32 dqtr3;		/* 0x224 dq timing register */
	u32 dqstr;		/* 0x228 dqs timing register */
	u32 dqsbtr;		/* 0x22c dqsb timing register */
	u32 mcr;		/* 0x230 mode configure register */
	u8 res[0x8];
	u32 reg_23c;	/* 0x23c register description unknown!!! */
	u32 apr;		/* 0x240 arbiter period register */
	u32 pldtr;		/* 0x244 priority level data threshold reg */
	u8 res5[0x8];
	u32 hpcr[32];	/* 0x250 host port configure register */
	u8 res6[0x10];
	u32 csel;		/* 0x2e0 controller select register */
};

struct dram_para {
	u32 baseaddr;
	u32 clock;
	u32 type;
	u32 rank_num;
	u32 density;
	u32 io_width;
	u32 bus_width;
	u32 cas;
	u32 zq;
	u32 odt_en;
	u32 size;
	u32 tpr0;
	u32 tpr1;
	u32 tpr2;
	u32 tpr3;
	u32 tpr4;
	u32 tpr5;
	u32 emr1;
	u32 emr2;
	u32 emr3;
};

/* Clock control header copied from include/asm/arch-sunxi/clock.h */
struct sunxi_ccm_reg {
	u32 pll1_cfg;		/* 0x00 pll1 control */
	u32 pll1_tun;		/* 0x04 pll1 tuning */
	u32 pll2_cfg;		/* 0x08 pll2 control */
	u32 pll2_tun;		/* 0x0c pll2 tuning */
	u32 pll3_cfg;		/* 0x10 pll3 control */
	u8 res0[0x4];
	u32 pll4_cfg;		/* 0x18 pll4 control */
	u8 res1[0x4];
	u32 pll5_cfg;		/* 0x20 pll5 control */
	u32 pll5_tun;		/* 0x24 pll5 tuning */
	u32 pll6_cfg;		/* 0x28 pll6 control */
	u32 pll6_tun;		/* 0x2c pll6 tuning */
	u32 pll7_cfg;		/* 0x30 pll7 control */
	u8 res2[0x4];
	u32 pll1_tun2;		/* 0x38 pll5 tuning2 */
	u32 pll5_tun2;		/* 0x3c pll5 tuning2 */
	u8 res3[0xc];
	u32 pll_lock_dbg;	/* 0x4c pll lock time debug */
	u32 osc24m_cfg;		/* 0x50 osc24m control */
	u32 cpu_ahb_apb0_cfg;	/* 0x54 cpu,ahb and apb0 divide ratio */
	u32 apb1_clk_div_cfg;	/* 0x58 apb1 clock dividor */
	u32 axi_gate;		/* 0x5c axi module clock gating */
	u32 ahb_gate0;		/* 0x60 ahb module clock gating 0 */
	u32 ahb_gate1;		/* 0x64 ahb module clock gating 1 */
	u32 apb0_gate;		/* 0x68 apb0 module clock gating */
	u32 apb1_gate;		/* 0x6c apb1 module clock gating */
	u8 res4[0x10];
	u32 nand_sclk_cfg;	/* 0x80 nand sub clock control */
	u32 ms_sclk_cfg;	/* 0x84 memory stick sub clock control */
	u32 sd0_clk_cfg;	/* 0x88 sd0 clock control */
	u32 sd1_clk_cfg;	/* 0x8c sd1 clock control */
	u32 sd2_clk_cfg;	/* 0x90 sd2 clock control */
	u32 sd3_clk_cfg;	/* 0x94 sd3 clock control */
	u32 ts_clk_cfg;		/* 0x98 transport stream clock control */
	u32 ss_clk_cfg;		/* 0x9c */
	u32 spi0_clk_cfg;	/* 0xa0 */
	u32 spi1_clk_cfg;	/* 0xa4 */
	u32 spi2_clk_cfg;	/* 0xa8 */
	u32 pata_clk_cfg;	/* 0xac */
	u32 ir0_clk_cfg;	/* 0xb0 */
	u32 ir1_clk_cfg;	/* 0xb4 */
	u32 iis_clk_cfg;	/* 0xb8 */
	u32 ac97_clk_cfg;	/* 0xbc */
	u32 spdif_clk_cfg;	/* 0xc0 */
	u32 keypad_clk_cfg;	/* 0xc4 */
	u32 sata_clk_cfg;	/* 0xc8 */
	u32 usb_clk_cfg;	/* 0xcc */
	u32 gps_clk_cfg;	/* 0xd0 */
	u32 spi3_clk_cfg;	/* 0xd4 */
	u8 res5[0x28];
	u32 dram_clk_cfg;	/* 0x100 */
	u32 be0_clk_cfg;	/* 0x104 */
	u32 be1_clk_cfg;	/* 0x108 */
	u32 fe0_clk_cfg;	/* 0x10c */
	u32 fe1_clk_cfg;	/* 0x110 */
	u32 mp_clk_cfg;		/* 0x114 */
	u32 lcd0_ch0_clk_cfg;	/* 0x118 */
	u32 lcd1_ch0_clk_cfg;	/* 0x11c */
	u32 csi_isp_clk_cfg;	/* 0x120 */
	u8 res6[0x4];
	u32 tvd_clk_reg;	/* 0x128 */
	u32 lcd0_ch1_clk_cfg;	/* 0x12c */
	u32 lcd1_ch1_clk_cfg;	/* 0x130 */
	u32 csi0_clk_cfg;	/* 0x134 */
	u32 csi1_clk_cfg;	/* 0x138 */
	u32 ve_clk_cfg;		/* 0x13c */
	u32 audio_codec_clk_cfg;	/* 0x140 */
	u32 avs_clk_cfg;	/* 0x144 */
	u32 ace_clk_cfg;	/* 0x148 */
	u32 lvds_clk_cfg;	/* 0x14c */
	u32 hdmi_clk_cfg;	/* 0x150 */
	u32 mali_clk_cfg;	/* 0x154 */
	u8 res7[0x4];
	u32 mbus_clk_cfg;	/* 0x15c */
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

volatile struct sunxi_dram_reg *r;

static void set_tpr3(int tpr3)
{
    int i;
    u32 dllval = r->dllcr[0];
    dllval &= ~(0x3f << 6);
    dllval |= ((tpr3 >> 16) & 0x3f) << 6;
    r->dllcr[0] = dllval;
    for (i = 1; i < 5; i++) {
        u32 dllval = r->dllcr[i];
        dllval &= ~(0xf << 14);
        dllval |= (tpr3 & 0xf) << 14;
        r->dllcr[i] = dllval;
        tpr3 >>= 4;
    }
}

static void show_help(void)
{
    printf("Usage: a10-set-tpr3 new_tpr3\n");
    printf("Where tpr3 is a hexadecimal number in the following format:\n");
    printf("  bits [22:20] - MFWDLY of the command lane\n");
    printf("  bits [18:16] - MFBDLY of the command lane\n");
    printf("  bits [15:12] - SDPHASE of the byte lane 3\n");
    printf("  bits  [11:8] - SDPHASE of the byte lane 2\n");
    printf("  bits   [7:4] - SDPHASE of the byte lane 1\n");
    printf("  bits   [3:0] - SDPHASE of the byte lane 0\n");
    printf("\nSee the RK30XX manual for more details. They are using\n");
    printf("the same dram controller as Allwinner A10/A13/A20.\n");
    printf("Though maybe a different revision of it.\n");
}

static int get_tpr3(void)
{
    return ((((r->dllcr[0]) >> 6) & 0x3f) << 16) |
               ((((r->dllcr[1]) >> 14) & 0xf) << 0) |
               ((((r->dllcr[2]) >> 14) & 0xf) << 4) |
               ((((r->dllcr[3]) >> 14) & 0xf) << 8) |
               ((((r->dllcr[4]) >> 14) & 0xf) << 12);
}

int main(int argc, char **argv)
{
    int i;
    volatile struct sunxi_ccm_reg *ccm = (volatile struct sunxi_ccm_reg *) map_physical_memory(SUNXI_CCM_BASE, 4096);
    struct dram_para p = {0};
    r  = (volatile struct sunxi_dram_reg *) map_physical_memory(SUNXI_DRAMC_BASE, 4096);
    int MFWDLY, MFBDLY, SDPHASE, tpr3, old_tpr3, new_tpr3;

    if (argc < 2 || sscanf(argv[1], "%x", &tpr3) != 1)
    {
        show_help();
        exit(1);
    }

    old_tpr3 = get_tpr3();

    printf("Trying to change dram_tpr3 from 0x%X to 0x%X\n", old_tpr3, tpr3);

    set_tpr3(tpr3);

    new_tpr3 = ((((r->dllcr[0]) >> 6) & 0x3f) << 16) |
               ((((r->dllcr[1]) >> 14) & 0xf) << 0) |
               ((((r->dllcr[2]) >> 14) & 0xf) << 4) |
               ((((r->dllcr[3]) >> 14) & 0xf) << 8) |
               ((((r->dllcr[4]) >> 14) & 0xf) << 12);

    if (new_tpr3 == tpr3)
        printf("Done\n");
    else
        printf("WTF, dram_tpr3 ended up being set to 0x%X\n", new_tpr3);

    /* Clean up */
    munmap((void *)r, 4096);
    munmap((void *)ccm, 4096);
    close(mem_fd);
    return 0;
}
