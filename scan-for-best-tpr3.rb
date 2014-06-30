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

raise "Please upgrade ruby to at least version 1.9" if RUBY_VERSION =~ /^1\.8/

require 'zlib'
require_relative 'tpr3-common.rb'

# No more than 5 minutes would be ever needed
$watchdog_max_timeout = 5 * 60

# Check if we have all the tools and are provided with a proper working directory

def tool_exists(tool_name)
    `which #{tool_name} > /dev/null 2>&1`
    if $?.to_i != 0 then
        printf("Error: the required '%s' executable is not found in PATH\n", tool_name)
        return false
    else
        return true
    end
end

tools_are_available = true
`which a10-meminfo > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0
`which a10-stdin-watchdog > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0
`which a10-set-tpr3 > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0
`which lima-memtester > /dev/null 2>&1`
tools_are_available = false if $?.to_i != 0

if not ARGV[0] or not File.directory?(ARGV[0]) then
    printf("Usage: #{$PROGRAM_NAME} [working_directory] <text_description>\n")
    printf("\n")
    printf("If you set this script to run by default after the system startup,\n")
    printf("then it is going to probe various settings of 'dram_tpr3' and test\n")
    printf("their stability with the lima-memtester tool. The final results are\n")
    printf("represented as subdirectories with files in the directory tree\n")
    printf("inside of 'working_directory'. The optional 'text_description'\n")
    printf("argument may be specified to provide a text description for this\n")
    printf("configuration. This description will be used in the nice html\n")
    printf("tables created by the 'parse-tpr3-results.rb' script.\n")
    printf("\n")
    printf("The #{$PROGRAM_NAME} script needs to be run as root. And it\n")
    printf("also needs a few other helper tools to be installed:\n")
    printf("   a10-meminfo\n")
    printf("   a10-stdin-watchdog\n")
    printf("   a10-set-tpr3\n")
    printf("   lima-memtester\n")
    printf("\n")
    printf("Note: expect a lot of reboots during the whole process!\n")
    exit(1)
end

if not tool_exists("a10-meminfo") or
   not tool_exists("a10-stdin-watchdog") or
   not tool_exists("a10-set-tpr3")
then
   printf("You can get it at https://github.com/ssvb/a10-meminfo/\n")
   exit(1)
end

if not tool_exists("lima-memtester") then
   printf("You can get it at https://github.com/ssvb/lima-memtester/\n")
   exit(1)
end

###############################################################################

$root_directory = ARGV[0]

# Check the current memory configuration

a10_meminfo_log = `a10-meminfo`.strip
hostname = `hostname`.strip

hardware_id = "unknown"
if `cat /proc/cpuinfo` =~ /Hardware\s*\:\s*(sun.*?)[\s\n$]/ then
    hardware_id = $1
end

# [    2.255645] axp20_buck3: 700 <--> 3500 mV at 1250 mV
if `dmesg` =~ /axp20_buck3: \d+ <--> \d+ mV at (\d+) mV/ then
    dcdc3_vol = $1.to_i
end

if not a10_meminfo_log =~ /dram_clk\s*=\s*(\d+)/ then
    raise("Error: bad dram_clk from a10-meminfo")
end
dram_freq = $1

if not a10_meminfo_log =~ /dram_bus_width\s*=\s*(\d+)/ then
    raise("Error: bad dram_bus_width from a10-meminfo")
end

number_of_lanes = $1.to_i / 8

if not a10_meminfo_log =~ /dram_tpr3\s*=\s*0[Xx]([0-9a-fA-F]+)/ then
    raise("Error: bad dram_tpr3 from a10-meminfo")
end

default_tpr3 = $1.to_i(16)

# Add the dcdc3 voltage information to the memtester log
a10_meminfo_log = "dcdc3_vol         = %d\n" % (dcdc3_vol or 0) + a10_meminfo_log
# Calculate CRC32 with dram_tpr3 information filtered out
a10_meminfo_log_crc32 = Zlib::crc32(a10_meminfo_log.gsub(
                                    /(dram_tpr3\s+=\s+0x\d+)/, ""))

$subtest_directory = File.join($root_directory,
                               hostname + "-" + hardware_id + "-" +
                               dram_freq + "MHz-" +
                               "%.3fV-" % (dcdc3_vol.to_f / 1000) +
                               sprintf("%08X", a10_meminfo_log_crc32))

# Ensure that a subdirectory exists for this configuration

def schedule_new_job(dir, adj, priority)
    job_file_name = "_job_phase+=[" +
        adj.reverse.map {|a| sprintf("%s%d", (a < 0 ? "" : "+"), a)}.join(",") +
       "].priority_%d" % priority
    job_file_full_path = File.join(dir, job_file_name)
    if not File.exists?(job_file_full_path) then
        fh = File.open(job_file_full_path, "w")
        fh.close
    end
end

if not File.directory?($subtest_directory) then
    Dir.mkdir($subtest_directory)

    # Save the a10-meminfo log for future reference
    fh = File.open(File.join($subtest_directory, "_a10_meminfo.txt"), "w")
    fh.write(a10_meminfo_log)
    fh.close()

    # Schedule the first iteration with no per-lane phase adjustments
    schedule_new_job($subtest_directory, [0] * number_of_lanes, 1000)
end

# Setup the hardware watchdog and provide some functions to control it

$watchdog = IO.popen(sprintf("a10-stdin-watchdog %d", $watchdog_max_timeout), "w")

def reset_watchdog_timeout(new_timeout)
    if new_timeout > $watchdog_max_timeout then
        raise "Bad watchdog timeout"
    end
    $watchdog.printf("%d\n", new_timeout)
    $watchdog.sync
end

def disable_watchdog()
    $watchdog.printf("-1\n")
    $watchdog.sync
    sleep(1)
end

def log_progress(log_name, message)
    fh = File.open(log_name, "wb")
    fh.write(message)
    fh.sync
    fh.close
    `sync`
    sleep(1)
end

def run_test(tpr3_log_name, tpr3, suffix, hardening)

    # Keep a notice about the current tpr3 check progress
    fh = File.open(File.join($subtest_directory, "_current_work_item.txt"), "w")
    fh.write(File.basename(tpr3_log_name))
    fh.close

    # 15 seconds to setup tpr3 should be enough
    reset_watchdog_timeout(15) 

    log_progress(tpr3_log_name,
        "before configuring tpr3" + suffix)

    if not `a10-set-tpr3 #{sprintf("0x%08X", tpr3)}` =~ /Done/ then
        log_progress(tpr3_log_name, "executing a10-set-tpr3 failed")
        exit(1)
    end

    log_progress(tpr3_log_name,
        "after configuring tpr3 and before running memtester")

    memtester_ok_count = 0
    memtester_total_count = 0

    1.upto(hardening ? 100 : 10) {|iteration|
        memtester_env_opts = "MEMTESTER_EARLY_EXIT=1 MEMTESTER_SKIP_STUCK_ADDRESS=1"
        if not hardening then
            if iteration < 5 then
                # solidbits,bitflip
                memtester_env_opts +=" MEMTESTER_TEST_MASK=0x1100"
            else
                # solidbits,bitflip,bitspread
                memtester_env_opts +=" MEMTESTER_TEST_MASK=0x1900"
            end
        end

        # Sleep a bit to cool down
        if iteration == 3 then
            reset_watchdog_timeout(120)
            printf("sleep 100 seconds in order to cool the CPU down\n")
            sleep(100)
        end

        # 2 minutes per individual lima-memtester run should be enough
        reset_watchdog_timeout(hardening ? 4 * 60 : 2 * 60)
        # Run memtester
        printf("run memtester, iteration %d\n", iteration)
        memtester_log = `#{memtester_env_opts} lima-memtester 12M 1 2>&1 >/dev/null`
        memtester_log.force_encoding("ASCII-8BIT")
        memtester_ok_count += 1 if $?.to_i == 0
        memtester_total_count += 1
        log_progress(tpr3_log_name,
                     sprintf("memtester success rate: %d/%d",
                             memtester_ok_count, memtester_total_count))
        if memtester_ok_count != memtester_total_count then
            log_progress(tpr3_log_name + ".memtester", memtester_log)
            break
        end
    }

    log_progress(tpr3_log_name,
        sprintf("FINISHED, memtester success rate: %d/%d",
                memtester_ok_count, memtester_total_count))

    # We are done with this work item
    if File.exists?(File.join($subtest_directory, "_current_work_item.txt")) then
        File.delete(File.join($subtest_directory, "_current_work_item.txt"))
    end

    # The system will be rebooted by the a10-stdin-watchdog
    reset_watchdog_timeout(0)
    while true do end
end

# The second optional command line argument is a description text
description_filename = File.join($subtest_directory, "_description.txt")
if ARGV[1] and not File.exists?(description_filename) then
    fh = File.open(description_filename, "w")
    fh.write(ARGV[1])
    fh.close
end

[false, true].each {|enforced_hardening|
    jobs_finder_generator($subtest_directory, {:sorted => false}).each {|job_info|
        next if job_info[:done] and not enforced_hardening
        $lane_phase_adjust = job_info[:lane_phase_adjustments]

        tpr3_reordered_generator($lane_phase_adjust,
                                 default_tpr3,
                                 $subtest_directory).each {|tpr3_info|
            tpr3 = tpr3_info[:tpr3]
            tpr3_log_file = File.join($subtest_directory,
                                      sprintf("tpr3_0x%08X", tpr3))

            hardening = (job_info[:hardening] or enforced_hardening)
            if not read_file(tpr3_log_file) ==
                   "FINISHED, memtester success rate: 10/10"
            then
                hardening = false
            end

            tpr3_log_file += ".hardening" if hardening
            if not File.exists?(tpr3_log_file) then
                run_test(tpr3_log_file, tpr3, ", try1", hardening)
            elsif read_file(tpr3_log_file) == "before configuring tpr3, try1" then
                run_test(tpr3_log_file, tpr3, ", try2", hardening)
            end
        }

        if not job_info[:done] then
            File.rename(job_info[:job_file_name], job_info[:job_file_name] + ".done")
        end
    }
}

disable_watchdog()

# We are done with all the work
if File.exists?(File.join($subtest_directory, "_current_work_item.txt")) then
    File.delete(File.join($subtest_directory, "_current_work_item.txt"))
end
