# Copyright © 2014 Siarhei Siamashka <siarhei.siamashka@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

def deep_copy(a) Marshal.load(Marshal.dump(a)) end

###############################################################################

# This is using a bit wrong datasheet, but we are optimistically assuming
# that GT8UB512M8_BG has the same timings as GT8UB256M8_BG

GT8UB512M8_BG = {
             #   tCK  CL  CWL
    :tCK =>  [[  2.5,  6,  5],  # 300MHz - 400MHz
              [1.875,  7,  6],  # 400MHz - 533MHz
              [  1.5,  9,  7],  # 533MHz - 667MHz
              [ 1.25, 11,  8]], # 667MHz - 800MHz

    # tRFC for 4Gb density with a little bit of extra safety margin is taken from
    # https://github.com/linux-sunxi/u-boot-sunxi/blob/87ca6dc0262d/arch/arm/cpu/armv7/sunxi/dram.c#L415
    :tXS      => {:ns => 320.0}, # tRFC(min) + 10ns

    :tRCD     => {:ns => 13.125},
    :tRP      => {:ns => 13.125},
    :tRC      => {:ns => 49.5},
    :tRAS     => {:ns => 36.0},
    :tFAW     => {:ns => 30.0},                  # Page size 1K (M8/X8 variant)
    :tRRD     => {:ck => 4, :ns => 6.0},         # Page size 1K (M8/X8 variant)
    :tCKE     => {:ck => 3, :ns => 5.625},
    :tWTR     => {:ck => 4, :ns => 7.5},
    :tXP      => {:ck => 3, :ns => 6.0},
    :tMRD     => {:ck => 4},
    :tRTP     => {:ck => 4, :ns => 7.5},
    :tWR      => {:ns => 15},
    :tDLLK    => {:ck => 512},
    :tRTW     => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tMOD     => {:ck => 12, :ns => 15.0},
    :tRTODT   => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRFC     => {:ns => 308.0}, # FIXME after we get the right datasheet
    :tCCD     => {:ck => 4},

    :density  => 4096,
    :io_width => 8,
    :label    => "GT GT8UB512M 8EN-BG",
    :url      => "http://dl.linux-sunxi.org/chips/GT-DDR3-2Gbit-B-DIE-(X8,X16).pdf"
}

GT8UB256M16_BG = deep_copy(GT8UB512M8_BG)
GT8UB256M16_BG[:tFAW] = {:ns => 45.0}           # Page size 2K (M16/X16 variant)
GT8UB256M16_BG[:tRRD] = {:ck => 4, :ns => 10.0} # Page size 2K (M16/X16 variant)
GT8UB256M16_BG[:io_width] = 16
GT8UB256M16_BG[:label] = "GT GT8UB256M16BP-BG"

###############################################################################

MEM4G16D3EABG_125 = {
             #   tCK  CL  CWL
    :tCK =>  [[  3.0,  5,  5],
              [  2.5,  6,  5],  # 300MHz - 400MHz
              [1.875,  7,  6],  # 400MHz - 533MHz
              [  1.5,  9,  7],  # 533MHz - 667MHz
              [ 1.25, 11,  8]], # 667MHz - 800MHz

    # tRFC for 4Gb density with a little bit of extra safety margin is taken from
    # https://github.com/linux-sunxi/u-boot-sunxi/blob/87ca6dc0262d/arch/arm/cpu/armv7/sunxi/dram.c#L415
    :tXS      => {:ns => 320.0}, # tRFC(min) + 10ns

    :tRCD     => {:ns => 13.125},
    :tRP      => {:ns => 13.125},
    :tRC      => {:ns => 48.125},
    :tRAS     => {:ns => 35.0},
    :tFAW     => {:ns => 30.0},
    :tRRD     => {:ck => 4, :ns => 6.0},
    :tCKE     => {:ck => 3, :ns => 5.0},
    :tWTR     => {:ck => 4, :ns => 7.5},
    :tXP      => {:ck => 3, :ns => 6.0},
    :tMRD     => {:ck => 4},
    :tRTP     => {:ck => 4, :ns => 7.5},
    :tWR      => {:ns => 15},
    :tDLLK    => {:ck => 512},
    :tRTW     => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tMOD     => {:ck => 12, :ns => 15.0},
    :tRTODT   => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRFC     => {:ns => 260.0},
    :tCCD     => {:ck => 4},

    :density  => 4096,
    :io_width => 16,
    :label    => "MEMPHIS MEM4G16D3E ABG-125",
    :url      => "http://www.memphis.ag/fileadmin/datasheets/MEM4G16D3EABG_10.pdf",
}

###############################################################################

def get_the_list_of_boards()
    return {
        "Cubieboard" => {
            url:       "http://linux-sunxi.org/Cubietech_Cubieboard",
            dram_size: 1024,
            dram_chip: GT8UB256M16_BG,
            dram_para: {
                zq:     123,
                odt_en: 0,
                tpr3:   0,
                tpr4:   0,
                emr1:   0,
            }
        },
        "Cubieboard2" => {
            url:       "http://linux-sunxi.org/Cubietech_Cubieboard2",
            dram_size: 1024,
            dram_chip: GT8UB256M16_BG,
            dram_para: {
                zq:     0x7f,
                odt_en: 0,
                tpr3:   0,
                tpr4:   0x1,
                emr1:   0x4,
            }
        },
        "Cubietruck" => {
            url:       "http://linux-sunxi.org/Cubietruck",
            dram_size: 2048,
            dram_chip: GT8UB512M8_BG,
            dram_para: {
                zq:     0x7f,
                odt_en: 0,
                tpr3:   0x72222,
                tpr4:   0x1,
                emr1:   0x4,
            }
        },
        "A10-OLinuXino-Lime" => {
            url:       "http://linux-sunxi.org/Olimex_A10-OLinuXino-Lime",
            dram_size: 512,
            dram_chip: MEM4G16D3EABG_125,
            dram_para: {
                zq:     123,
                odt_en: 0,
                tpr3:   0,
                tpr4:   0,
                emr1:   0x4,
            }
        }
    }
end
