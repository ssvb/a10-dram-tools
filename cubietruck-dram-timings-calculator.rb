#!/usr/bin/env ruby
#
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

# From http://dl.linux-sunxi.org/chips/GT-DDR3-2Gbit-B-DIE-(X8,X16).pdf
GT8UB256M8_BG = {
             #   tCK  CL  CWL
    "tCK" => [[  2.5,  6,  5],  # 300MHz - 400MHz
              [1.875,  7,  6],  # 400MHz - 533MHz
              [  1.5,  9,  7],  # 533MHz - 667MHz
              [ 1.25, 11,  8]], # 667MHz - 800MHz

    # tRFC is taken from https://github.com/linux-sunxi/u-boot-sunxi/blob/87ca6dc0262d/arch/arm/cpu/armv7/sunxi/dram.c#L415
    # for 4Gb density with a little bit of extra safety margin
    "tXS"  => 320.0,       # tRFC(min) + 10ns

    "tRCD" => 13.125,
    "tRP"  => 13.125,
    "tRC"  => 49.5,
    "tRAS" => 36.0,
    "tFAW" => 30.0,        # For page size 1K (M8/X8 variant)
    "tRRD" => [4, 6.0],    # For page size 1K (M8/X8 variant)
    "tCKE" => [3, 5.625],
    "tWTR" => [4, 7.5],
    "tXP"  => [3, 6.0],
    "tMRD" => [4, 0.001],
    "tRTP" => [4, 7.5],

    "tWR"  => 15.0,
}

# Bitfields for DDR_PHYCTL_DTPR0, DDR_PHYCTL_DTPR1, DDR_PHYCTL_DTPR2 from
# RK30xx manual represented as [highest bit, lowest bit, add constant, name]
$tpr_bitfields = [
    [ # .tpr0
        [31, 31,  0, "tCCD"],
        [30, 25,  0, "tRC"],
        [24, 21,  0, "tRRD"],
        [20, 16,  0, "tRAS"],
        [15, 12,  0, "tRCD"],
        [11,  8,  0, "tRP"],
        [ 7,  5,  0, "tWTR"],
        [ 4,  2,  0, "tRTP"],
        [ 1,  0,  4, "tMRD"],
    ],
    [ # .tpr1
        [23, 16,  0, "tRFC"],
        [15, 12,  0, "reserved"],
        [11, 11,  0, "tRTODT"],
        [10,  9, 12, "tMOD"],
        [ 8,  3,  0, "tFAW"],
        [ 2,  2,  0, "tRTW"],
    ],
    [ # .tpr2
        [28, 19,  0, "tDLLK"],
        [18, 15,  0, "tCKE"],
        [14, 10,  0, "tXP"],
        [ 9,  0,  0, "tXS"],
    ]
]

# Convert an array with 3 magic constants to a key->value hash
def convert_from_tpr(tpr)
    result = {}
    tpr.each_index {|i|
        $tpr_bitfields[i].each {|v|
            maxbit = v[0]
            minbit = v[1]
            x = (tpr[i] >> minbit) & ((1 << (maxbit - minbit + 1)) - 1)
            result[v[3]] = x + v[2]
        }
    }
    return result
end

# Convert from a key->value hash back to an array with 3 magic constants
def convert_to_tpr(a)
    result = [0, 0, 0]
    tmp_hash = {}
    $tpr_bitfields.each_index {|i|
        $tpr_bitfields[i].each {|v|
            tmp_hash[v[3]] = [i, v[1], v[2]]
        }
    }
    a.each {|k, v|
        result[tmp_hash[k][0]] |= (v - tmp_hash[k][2]) << tmp_hash[k][1]
    }
    return result
end

# Get CL value for the selected DRAM clock frequency
def get_cl(dram_freq, dram_timings)
    tCK = 1000.0 / dram_freq
    dram_timings["tCK"].each {|v| return v[1] if v[0] <= tCK }
end

def get_cwl(dram_freq, dram_timings)
    tCK = 1000.0 / dram_freq
    dram_timings["tCK"].each {|v| return v[2] if v[0] <= tCK }
end

def get_mr0_WR(dram_freq, dram_timings)
    tCK = 1000.0 / dram_freq
    return (dram_timings["tWR"] / tCK).ceil.to_i
end

# Convert from nanoseconds to cycles, but no less than 'min_ck'
def ns_to_ck(dram_freq, dram_timings, param_name)
    min_ck = 0
    ns     = dram_timings[param_name]
    if dram_timings[param_name].is_a?(Array) then
        min_ck = dram_timings[param_name][0]
        ns     = dram_timings[param_name][1]
    end
    ck = (dram_freq * ns / 1000.0).ceil.to_i
    if ck > min_ck then
        return ck
    else
        return min_ck
    end
end

def calc_tpr(dram_freq, dram_timings)
    tpr_cas9 = [0x42d899b7, 0xa090, 0x22a00]
    tmp = convert_from_tpr(tpr_cas9)
    tmp["tXS"] =  ns_to_ck(dram_freq, dram_timings, "tXS")
    tmp["tRCD"] = ns_to_ck(dram_freq, dram_timings, "tRCD")
    tmp["tRP"]  = ns_to_ck(dram_freq, dram_timings, "tRP")
    tmp["tRC"]  = ns_to_ck(dram_freq, dram_timings, "tRC")
    tmp["tRAS"] = ns_to_ck(dram_freq, dram_timings, "tRAS")
    tmp["tFAW"] = ns_to_ck(dram_freq, dram_timings, "tFAW")
    tmp["tRRD"] = ns_to_ck(dram_freq, dram_timings, "tRRD")
    tmp["tCKE"] = ns_to_ck(dram_freq, dram_timings, "tCKE")
    tmp["tWTR"] = ns_to_ck(dram_freq, dram_timings, "tWTR")
    tmp["tXP"]  = ns_to_ck(dram_freq, dram_timings, "tXP")
    tmp["tMRD"] = ns_to_ck(dram_freq, dram_timings, "tMRD")
    tmp["tRTP"] = ns_to_ck(dram_freq, dram_timings, "tRTP")
    return convert_to_tpr(tmp)
end

# Print a part of dram_para stuct for u-boot sources
def print_tpr(comment, dram_freq, dram_timings)

    tpr = calc_tpr(dram_freq, dram_timings)

    # A sanity check: ensure that the roundtrip conversion to the
    # key->value hash and back to three 32-bit magic constants does
    # not introduce any errors
    new_tpr = convert_to_tpr(convert_from_tpr(tpr))
    raise "Roundtrip conversion failed" unless new_tpr[0] == tpr[0] &&
                                               new_tpr[1] == tpr[1] &&
                                               new_tpr[2] == tpr[2]

    printf("/* %s\n", comment)

    tmp = convert_from_tpr(tpr)
    used_keys = {}

    # Show the most interesting values in a special sorting order
    ["tRCD", "tRC", "tRAS", "tRP", "tFAW", "tRRD", "tCKE", "tRP",
     "tWTR", "tXP", "tMRD", "tRTP"].each {|k|
        used_keys[k] = 1
        printf(" * %8s = %8.2f ns (%d)\n", k,
               tmp[k].to_f * 1000 / dram_freq, tmp[k])
    }
    # Show the rest of the values in any order
    tmp.each {|k, v|
        next if used_keys[k]
        printf(" * %8s = %8.2f ns (%d)\n", k,
               tmp[k].to_f * 1000 / dram_freq, tmp[k])
    }
    printf(" *\n")
    printf(" * WR (write recovery) needs to be set to at least %d in MR0\n",
           get_mr0_WR(dram_freq, dram_timings))
    printf(" */\n")

    printf("static struct dram_para dram_para = {\n")
    printf("\t.type = 3,\n")
    printf("\t.rank_num = 1,\n")
    printf("\t.density = 4096,\n")
    printf("\t.io_width = 8,\n")
    printf("\t.bus_width = 32,\n")
    printf("\t.size = 2048,\n")
    printf("\n")
    printf("\t.zq = 0x7f,\n")
    printf("\t.odt_en = 0,\n")

    printf("\n")

    printf("\t.clock = %d,\n", dram_freq)
    printf("\t.cas   = %d,\n", get_cl(dram_freq, dram_timings))
    printf("\t.tpr0  = 0x%08X,\n", tpr[0])
    printf("\t.tpr1  = 0x%08X,\n", tpr[1])
    printf("\t.tpr2  = 0x%08X,\n", tpr[2])
    printf("\t.tpr3  = 0x00072222, /* Phase shift magic */\n")
    printf("\t.tpr4  = 0x00000001, /* T1/T2 */\n")
    printf("\t.tpr5  = 0x00000000, /* Unused in u-boot */\n")
    printf("\t.emr1  = 0x00000004, /* Fixme: ODT, AL, ... */\n")
    printf("\t.emr2  = 0x%08X, /* Note: only CWL is set */\n",
           ([get_cwl(dram_freq, dram_timings), 5].max - 5) << 3)
    printf("\t.emr3  = 0x00000000,\n")
    printf("};\n")

end

if not ARGV[0] then
    printf("Please provide the desired dram clock frequency (in MHz) as a\n")
    printf("command line argument for this script\n")
    exit(0)
end

# Sanitize input to put it into the [360, 648] range and ensure
# that it is divisible by 24
dram_freq = [[ARGV[0].to_i, 360].max, 648].min / 24 * 24

print_tpr(sprintf("Cubietruck dram timings for %dMHz", dram_freq),
          dram_freq, GT8UB256M8_BG)
