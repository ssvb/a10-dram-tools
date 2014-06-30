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

###############################################################################

def derive_from_JEDEC_DDR3_1333_9_9_9(extra_info)
    density   = extra_info[:density]
    page_size = extra_info[:page_size]

    def tRFC_ns(density)
        return 350.0 if not density
        return { 512 =>  90.0, 1024 => 110.0, 2048 => 160.0,
                4096 => 300.0, 8192 => 350.0}[density]
    end
    def tFAW_ns(page_size) return {1024 => 30.0, 2048 => 45.0}[page_size] end
    def tRRD_ns(page_size) return {1024 =>  6.0, 2048 =>  7.5}[page_size] end

    # Fill in the JEDEC timings for the Speed Bin 1333H (DDR3 1333 9-9-9)
    # Except that use CL=7 (instead of CL=8) for the 400MHz - 533MHz range
    # because this seems to be what real DRAM chips support
    timings_info = {
                 #   tCK  CL  CWL
        :tCK =>  [[  2.5,  6,  5],  # 300MHz - 400MHz
                  [1.875,  7,  6],  # 400MHz - 533MHz
                  [  1.5,  9,  7]], # 533MHz - 667MHz

        :tXS      => {:ns => tRFC_ns(density) + 10.0},
        :tRCD     => {:ns => 13.5},
        :tRP      => {:ns => 13.5},
        :tRC      => {:ns => 49.5},
        :tRAS     => {:ns => 36.0},
        :tFAW     => {:ns => tFAW_ns(page_size)},
        :tRRD     => {:ck => 4, :ns => tRRD_ns(page_size)},
        :tCKE     => {:ck => 3, :ns => 5.625},
        :tWTR     => {:ck => 4, :ns => 7.5},
        :tXP      => {:ck => 3, :ns => 6.0},
        :tXPDLL   => {:ck => 10, :ns => 24.0},
        :tMRD     => {:ck => 4},
        :tRTP     => {:ck => 4, :ns => 7.5},
        :tWR      => {:ns => 15.0},
        :tDLLK    => {:ck => 512},
        :tMOD     => {:ck => 12, :ns => 15.0},
        :tRFC     => {:ns => tRFC_ns(density)},
        :tCCD     => {:ck => 4},
        :density  => density,
    }
    # And override some of the timings by the externally provided data
    extra_info.each {|k, v| timings_info[k] = v }
    return timings_info
end

###############################################################################

# This is using a bit wrong datasheet, but we are optimistically assuming
# that GT8UB512M8_BG has the same timings as GT8UB256M8_BG

GT8UB512M8_BG = derive_from_JEDEC_DDR3_1333_9_9_9({
    :density   => 4096,
    :page_size => 1024,
    :io_width  => 8,
    :label     => "GT GT8UB512M 8EN-BG",
    :url       => "http://dl.linux-sunxi.org/chips/GT-DDR3-2Gbit-B-DIE-(X8,X16).pdf",

    :tRCD      => {:ns => 13.125},
    :tRP       => {:ns => 13.125},
    :tRTW      => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRTODT    => {:ck => 0}, # 0 - default, 1 - extra cycle
})

GT8UB256M16_BG = derive_from_JEDEC_DDR3_1333_9_9_9({
    :density   => 4096,
    :page_size => 2048,
    :io_width  => 16,
    :label     => "GT GT8UB256M16BP-BG",
    :url       => "http://dl.linux-sunxi.org/chips/GT-DDR3-2Gbit-B-DIE-(X8,X16).pdf",

    :tRCD      => {:ns => 13.125},
    :tRP       => {:ns => 13.125},
    :tRTW      => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRTODT    => {:ck => 0}, # 0 - default, 1 - extra cycle
})

###############################################################################

# It is DDR3-1600, but we still derive from DDR-1333 9-9-9 and just
# tweak the timings
MEM4G16D3EABG_125 = derive_from_JEDEC_DDR3_1333_9_9_9({
    :density   => 4096,
    :page_size => 2048,
    :io_width  => 16,
    :label     => "MEMPHIS MEM4G16D3E ABG-125",
    :url       => "http://www.memphis.ag/fileadmin/datasheets/MEM4G16D3EABG_10.pdf",

    :tRCD     => {:ns => 13.125},
    :tRP      => {:ns => 13.125},
    :tRC      => {:ns => 48.125},
    :tRAS     => {:ns => 35.0},
    :tFAW     => {:ns => 30.0},
    :tRRD     => {:ck => 4, :ns => 6.0},
    :tCKE     => {:ck => 3, :ns => 5.0},
    :tRFC     => {:ns => 260.0},
    :tRTW     => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRTODT   => {:ck => 0}, # 0 - default, 1 - extra cycle
})

###############################################################################

H5TQ2G63BFR = derive_from_JEDEC_DDR3_1333_9_9_9({
    :density   => 2048,
    :page_size => 2048,
    :io_width  => 16,
    :label     => "Hynix H5TQ2G63BFR",
    :url       => "http://hands.com/~lkcl/H5TQ2G63BFR.pdf",
    :tRTW     => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRTODT   => {:ck => 0}, # 0 - default, 1 - extra cycle
})

###############################################################################

GENERIC_DDR3_1333 = derive_from_JEDEC_DDR3_1333_9_9_9({
    :page_size => 2048,
    :io_width  => 16,
    :tRTW     => {:ck => 0}, # 0 - default, 1 - extra cycle
    :tRTODT   => {:ck => 0}, # 0 - default, 1 - extra cycle
})

###############################################################################

def get_generic_board()
    return {
        dram_chip: GENERIC_DDR3_1333,
        dram_para: {
            zq:     123,
            odt_en: 0,
            tpr3:   0,
            tpr4:   0,
            emr1:   0,
        }
    }
end

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
        },
        "Mele_A1000" => {
            url:       "http://linux-sunxi.org/Mele_A1000",
            dram_size: 512,
            dram_chip: H5TQ2G63BFR,
            dram_para: {
                zq:     123,
                odt_en: 0,
                tpr3:   0,
                tpr4:   0,
                emr1:   0,
            }
        },
    }
end
