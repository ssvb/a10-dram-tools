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

VERBOSE = false
require_relative 'a10-dram-info.rb'

###############################################################################

# Bitfields for DDR_PHYCTL_DTPR0, DDR_PHYCTL_DTPR1, DDR_PHYCTL_DTPR2 from
# RK30xx manual represented as [highest bit, lowest bit, add constant, name]
$tpr_bitfields = [
    [ # .tpr0
        [31, 31,  4, :tCCD],
        [30, 25,  0, :tRC],
        [24, 21,  0, :tRRD],
        [20, 16,  0, :tRAS],
        [15, 12,  0, :tRCD],
        [11,  8,  0, :tRP],
        [ 7,  5,  0, :tWTR],
        [ 4,  2,  0, :tRTP],
        [ 1,  0,  4, :tMRD],
    ],
    [ # .tpr1
        [23, 16,  0, :tRFC],
        [15, 12,  0, :reserved],
        [11, 11,  0, :tRTODT],
        [10,  9, 12, :tMOD],
        [ 8,  3,  0, :tFAW],
        [ 2,  2,  0, :tRTW],
    ],
    [ # .tpr2
        [28, 19,  0, :tDLLK],
        [18, 15,  0, :tCKE],
        [14, 10,  0, :tXP],
        [ 9,  0,  0, :tXS],
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
    dram_timings[:tCK].each {|v| return v[1] if v[0] <= tCK }
end

def get_cwl(dram_freq, dram_timings)
    tCK = 1000.0 / dram_freq
    dram_timings[:tCK].each {|v| return v[2] if v[0] <= tCK }
end

def get_mr0_WR(dram_freq, dram_timings)
    tCK = 1000.0 / dram_freq
    return (dram_timings[:tWR][:ns] / tCK).ceil.to_i
end

# Convert from nanoseconds to cycles, but no less than 'min_ck'
def ns_to_ck(dram_freq, dram_timings, param_name)
    min_ck = dram_timings[param_name][:ck]
    ns     = dram_timings[param_name][:ns]
    if ns then
        ck = (dram_freq * ns / 1000.0).ceil.to_i
        ck = min_ck if min_ck and ck < min_ck
        return ck
    else
        return min_ck
    end
end

def calc_tpr(dram_freq, dram_timings)
    tpr_cas9 = [0x42d899b7, 0xa090, 0x22a00]
    tmp = convert_from_tpr(tpr_cas9)
    tmp[:tXS]    = ns_to_ck(dram_freq, dram_timings, :tXS)
    tmp[:tRCD]   = ns_to_ck(dram_freq, dram_timings, :tRCD)
    tmp[:tRP]    = ns_to_ck(dram_freq, dram_timings, :tRP)
    tmp[:tRC]    = ns_to_ck(dram_freq, dram_timings, :tRC)
    tmp[:tRAS]   = ns_to_ck(dram_freq, dram_timings, :tRAS)
    tmp[:tFAW]   = ns_to_ck(dram_freq, dram_timings, :tFAW)
    tmp[:tRRD]   = ns_to_ck(dram_freq, dram_timings, :tRRD)
    tmp[:tCKE]   = ns_to_ck(dram_freq, dram_timings, :tCKE)
    tmp[:tWTR]   = ns_to_ck(dram_freq, dram_timings, :tWTR)
    tmp[:tXP]    = ns_to_ck(dram_freq, dram_timings, :tXP)
    tmp[:tMRD]   = ns_to_ck(dram_freq, dram_timings, :tMRD)
    tmp[:tRTP]   = ns_to_ck(dram_freq, dram_timings, :tRTP)
    tmp[:tDLLK]  = ns_to_ck(dram_freq, dram_timings, :tDLLK)
    tmp[:tRTW]   = ns_to_ck(dram_freq, dram_timings, :tRTW)
    tmp[:tMOD]   = ns_to_ck(dram_freq, dram_timings, :tMOD)
    tmp[:tRTODT] = ns_to_ck(dram_freq, dram_timings, :tRTODT)
    tmp[:tRFC]   = ns_to_ck(dram_freq, dram_timings, :tRFC)
    tmp[:tCCD]   = ns_to_ck(dram_freq, dram_timings, :tCCD)

    # Apply extra requirements from the RK30XX manual:
    #     tXS  = max(tXS, tXSDLL)
    #     tXP  = max(tXP, tXPDLL)
    #     tRTP = max(tRTP, 2)
    #     tCKE = max(tCKE, tCKESR)
    tmp[:tXS] = [tmp[:tXS], tmp[:tDLLK]].max
    tmp[:tXP] = [tmp[:tXP], ns_to_ck(dram_freq, dram_timings, :tXPDLL)].max
    tmp[:tRTP] = [tmp[:tRTP], 2].max
    tmp[:tCKE] += 1 # tCKESR = tCKE(min) + 1 nCK

    tpr = convert_to_tpr(tmp)

    # A sanity check: ensure that the roundtrip conversion to the
    # key->value hash and back to three 32-bit magic constants does
    # not introduce any errors
    convert_from_tpr(tpr).each {|k, v|
        raise "Roundtrip conversion failed" if tmp[k] != v
    }
    return tpr
end

def print_verbose_timings_info(tmp, dram_freq, dram_timings)
    used_keys = {}
    printf("/* %s\n", "")
    # Show the most interesting values in a special sorting order
    [:tRCD, :tRP, :tRAS, :tRC, :tFAW, :tRRD, :tCKE, :tWTR, :tXP, :tMRD, :tRTP].each {|k|
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
end

# Print a part of dram_para stuct for u-boot sources
def generate_dram_para(board, dram_freq)

    dram_timings = board[:dram_chip]

    tpr = calc_tpr(dram_freq, dram_timings)

    tmp = convert_from_tpr(tpr)
    cas = get_cl(dram_freq, dram_timings)

    if VERBOSE then
        print_verbose_timings_info(tmp, dram_freq, dram_timings)
    end

    printf("static struct dram_para dram_para = {")
    printf(" /* DRAM timings: %d-%d-%d-%d */\n",
           cas, tmp[:tRCD], tmp[:tRP], tmp[:tRAS])
    printf("\t.clock     = %d,\n", dram_freq)
    printf("\t.type      = 3,\n")
    printf("\t.rank_num  = 1,\n")
    printf("\t.density   = #{dram_timings[:density]},\n")
    printf("\t.io_width  = #{dram_timings[:io_width]},\n")
    printf("\t.bus_width = %d,\n", 8 * board[:dram_size] /
                                   dram_timings[:density] *
                                   dram_timings[:io_width])

    printf("\t.cas       = %d,\n", cas)
    printf("\t.zq        = 0x%x,\n", board[:dram_para][:zq])
    printf("\t.odt_en    = %d,\n", board[:dram_para][:odt_en])
    printf("\t.size      = %d,\n", board[:dram_size])
    printf("\t.tpr0      = 0x%x,\n", tpr[0])
    printf("\t.tpr1      = 0x%x,\n", tpr[1])
    printf("\t.tpr2      = 0x%x,\n", tpr[2])
    printf("\t.tpr3      = 0x%x,\n", board[:dram_para][:tpr3])
    printf("\t.tpr4      = 0x%x,\n", board[:dram_para][:tpr4])
    printf("\t.tpr5      = 0x0,\n")
    printf("\t.emr1      = 0x%x,\n", board[:dram_para][:emr1])
    printf("\t.emr2      = 0x%x,\n",
           ([get_cwl(dram_freq, dram_timings), 5].max - 5) << 3)
    printf("\t.emr3      = 0x0,\n")
    printf("};\n")
end

boards = get_the_list_of_boards()

if not ARGV[0] or not ARGV[1] or not boards[ARGV[0]] then
    printf("Usage: #{$PROGRAM_NAME} [board_name] [dram_clock_frequency]\n")
    printf("\nThe list of supported boards:\n")
    boards.sort.each {|name, info|
        printf("    %s\n", name)
    }
    exit(1)
end

# Sanitize input to put it into the [360, 648] range
dram_freq = [[ARGV[1].to_i, 300].max, 667].min

generate_dram_para(boards[ARGV[0]], dram_freq)
