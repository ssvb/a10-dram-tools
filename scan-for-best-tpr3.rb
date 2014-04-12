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

require 'zlib'
require 'generator'

# Check if we have all the tools and are provided with a proper working directory

tools_are_available = true
`which a10-meminfo > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0
`which a10-watchdog > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0
`which a10-set-tpr3 > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0
`which lima-memtester > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0

if not ARGV[0] or not File.directory?(ARGV[0]) or not tools_are_available then
    printf("Usage: #{$PROGRAM_NAME}dramtest.rb [working_directory]\n")
    printf("\n")
    printf("If you set this script to run by default after the system startup,\n")
    printf("then it is going to probe various settings of 'dram_tpr3' and test\n")
    printf("their stability with a lima-memtester tool. The final results are\n")
    printf("represented as subdirectories with files in the directory\n")
    printf("tree inside of 'working_directory'.\n")
    printf("\n")
    printf("Note: expect a lot of reboots during this process!\n")
    printf("\n")
    printf("This script needs to be run as root, and also it needs\n")
    printf("a few tools to be installed:\n")
    printf("   a10-meminfo\n")
    printf("   a10-watchdog\n")
    printf("   a10-set-tpr3\n")
    printf("   lima-memtester\n")
    if not tools_are_available then
        printf("\nSome of the required tools are not found! Please fix this.\n")
    end
    exit(1)
end

$root_directory = ARGV[0]

# Check the current memory configuration

a10_meminfo_log = `a10-meminfo`
a10_meminfo_log_crc32 = Zlib::crc32(a10_meminfo_log)

if not a10_meminfo_log =~ /dram_clk\s*=\s*(\d+)/ then
    printf("Error: a10-meminfo is not installed\n")
    exit(1)
end

dram_freq = $1

$subtest_directory = File.join($root_directory, dram_freq + "MHz-" +
                               sprintf("%08X", a10_meminfo_log_crc32))

# Ensure that a subdirectory exists for this configuration
Dir.mkdir($subtest_directory) if not File.directory?($subtest_directory)

# Save the a10-meminfo log for future reference
fh = File.open(File.join($subtest_directory, "_a10_meminfo.txt"), "w")
fh.write(a10_meminfo_log)
fh.close()

# Now pick a previously untested tpr3 configuration

tpr3_gen = Generator.new {|tpr3_gen|
    [0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00,
     0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38].each {|mfxdly|
        [0x3, 0x2, 0x1, 0x0, 0xe, 0xd, 0xc].each {|sdphase|
            tpr3_gen.yield((mfxdly << 16) | (sdphase * 0x1111))
        }
    }
}

def log_progress(log_name, message)
    fh = File.open(log_name, "w")
    fh.write(message)
    fh.close
    `sync`
    sleep(1)
end

def read_file(filename)
    fh = File.open(filename)
    data = fh.read
    fh.close
    return data
end

def run_test(tpr3_log_name, tpr3, suffix)

    # Keep a notice about the current tpr3 check progress
    fh = File.open(File.join($subtest_directory, "_current_work.txt"), "w")
    fh.write(File.basename(tpr3_log_name))
    fh.close

    log_progress(tpr3_log_name,
        "before configuring tpr3" + suffix)

    if not `a10-set-tpr3 #{sprintf("0x%08X", tpr3)}` =~ /Done/ then
        log_progress("executing a10-set-tpr3 failed")
        exit(1)
    end

    log_progress(tpr3_log_name,
        "after configuring tpr3 and before running memtester")

    memtester_ok_count = 0
    memtester_total_count = 0

    1.upto(5) {
        `lima-memtester 8M 1`
        memtester_ok_count += 1 if $?.to_i == 0
        memtester_total_count += 1
        log_progress(tpr3_log_name,
                     sprintf("memtester success rate: %d/%d",
                             memtester_ok_count, memtester_total_count))
    }

    log_progress(tpr3_log_name,
        sprintf("FINISHED, memtester success rate: %d/%d",
                memtester_ok_count, memtester_total_count))

    # The system will be rebooted by the a10-watchdog
    exit(1)
end

tpr3_gen.each {|tpr3|
    tpr3_log_file = File.join($subtest_directory, sprintf("tpr3_0x%08X", tpr3))
    if not File.exists?(tpr3_log_file) then
        run_test(tpr3_log_file, tpr3, ", try1")
    elsif read_file(tpr3_log_file) == "before configuring tpr3, try1" then
        run_test(tpr3_log_file, tpr3, ", try2")
    elsif read_file(tpr3_log_file) == "before configuring tpr3, try2" then
        run_test(tpr3_log_file, tpr3, ", try3")
    end
}

# We are done with all the work
if File.exists?(File.join($subtest_directory, "_current_work.txt")) then
    File.delete(File.join($subtest_directory, "_current_work.txt"))
end
