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

require_relative 'tpr3-common.rb'

if not ARGV[0] or not File.directory?(ARGV[0]) then
    printf("Usage: #{$PROGRAM_NAME} [results_directory] > report.html\n")
    printf("\n")
    printf("Where:\n")
    printf("    results_directory - is the directory populated by\n")
    printf("                        the scan-for-best-tpr3.rb script\n")
    printf("    report.html       - is the output of this script\n")
    exit(1)
end

def parse_subtest_dir(dir, adj)

    mfxdly_list   = [0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00,
                     0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38]
    sdphase_list  = [36, 54, 72, 90, 108, 126]

    tpr3_status_logs = {}
    memtester_logs = {}
    tpr3_print_name = {}

    score_per_sdphase_label = {}
    stability_score = 0
    memtester_subtest_stats = {}
    lane_r_fail_stats = [0] * 4
    lane_w_fail_stats = [0] * 4
    lane_r_fail_list = [{}, {}, {}, {}]
    lane_w_fail_list = [{}, {}, {}, {}]
    bit_fail_stats = [0] * 32

    tpr3_generator(adj).each {|tpr3_info|
        tpr3 = tpr3_info[:tpr3]
        tpr3_status_logs[tpr3] = read_file(dir, sprintf(
                                            "tpr3_0x%08X", tpr3))
        memtester_logs[tpr3] = (read_file(dir, sprintf(
                                 "tpr3_0x%08X.memtester", tpr3)) or "")
        if memtester_logs[tpr3] == "" then
            memtester_logs[tpr3] = (read_file(dir,
                sprintf("tpr3_0x%08X.hardening.memtester", tpr3)) or "")
        end

        tpr3_status_log = tpr3_status_logs[tpr3]

        tpr3_print_name[tpr3] = sprintf("0x%06X", tpr3)
        if tpr3_status_log =~ /memtester success rate: (\d+)\/(\d+)/ then
            stability_score += $1.to_i
            tmp = tpr3_info[:sdphase_deg]
            score_per_sdphase_label[tmp] = (score_per_sdphase_label[tmp] or 0) + $1.to_i
        end
        memtester_log = memtester_logs[tpr3]
        if memtester_log =~ /FAILURE: 0x([0-9a-f]{8}) != 0x([0-9a-f]{8}).*?\((.*)\)/ then
            val1 = $1.to_i(16)
            val2 = $2.to_i(16)
            memtester_subtest_stats[$3] = (memtester_subtest_stats[$3] or 0) + 1
            print_name = sprintf("0x%02X", tpr3 >> 16)
            3.downto(0) {|lane|
                mask = 0xFF << (lane * 8)
                if (val1 & mask) != (val2 & mask) then
                    if memtester_log =~ /WRITE FAILURE/ then
                        lane_w_fail_list[lane][tpr3] = true
                        lane_w_fail_stats[lane] += 1
                    elsif memtester_log =~ /READ FAILURE/ then
                        lane_r_fail_list[lane][tpr3] = true
                        lane_r_fail_stats[lane] += 1
                    end
                    print_name += sprintf("<b>%X</b>", (tpr3 >> (lane * 4)) & 0xF)
                else
                    print_name += sprintf("%X", (tpr3 >> (lane * 4)) & 0xF)
                end
            }
            tpr3_print_name[tpr3] = print_name
            0.upto(31) {|bit|
                mask = 1 << bit
                if (val1 & mask) != (val2 & mask) then
                    bit_fail_stats[bit] += 1
                end
            }
        end
    }

    def get_nice_color(dir, tpr3, data, memtester_log)

        workdata = (read_file(dir, "_current_work_item.txt") or "")
        if workdata.include?(sprintf("%08X", tpr3)) then
            return "#C0C0C0" # gray marker - work is still in progress
        end

        tpr3_hardened_log = read_file(dir, sprintf("tpr3_0x%08X.hardening", tpr3))
        if tpr3_hardened_log then
            if tpr3_hardened_log == "FINISHED, memtester success rate: 100/100" then
                return "#008000"
            else
                return "#60FF60"
            end
        end

        passed_tests = 0
        total_tests = 1
        if data =~ /memtester success rate: (\d+)\/(\d+)/ then
            passed_tests = $1.to_i
            total_tests = $2.to_i
        end
        if passed_tests >= 10 then
            color = "#40C040"
        else
            def lerp(a, b, ratio) return (a + (b - a) * ratio).to_i end
            red_part = 0xFF
            if memtester_log =~ /READ FAILURE/ then
                green_part = lerp(0x50, 0xD0, Math.sqrt(passed_tests + total_tests) / 4.5)
                blue_part = 0
            elsif memtester_log =~ /WRITE FAILURE/ then
                blue_part = lerp(0x50, 0xD0, Math.sqrt(passed_tests + total_tests) / 4.5)
                green_part = 0
            else
                blue_part = lerp(0x0, 0x50, Math.sqrt(passed_tests + total_tests) / 4.5)
                green_part = lerp(0x0, 0x50, Math.sqrt(passed_tests + total_tests) / 4.5)
            end
            color = sprintf("#%02X%02X%02X", red_part, green_part, blue_part)
        end
        return color
    end

    html_report = sprintf("<table border=1 style='border-collapse: collapse;")
    html_report << sprintf(" empty-cells: show; font-family: arial; font-size: small;")
    html_report << sprintf(" white-space: nowrap; background: #F0F0F0;'>\n")
    html_report << sprintf("<tr><th>mfxdly")
    sdphase_list.each {|sdphase|
#        next if not gen_tpr3(0, sdphase, adj)
        score_per_sdphase_label[sdphase] = 0 if not score_per_sdphase_label[sdphase]
        html_report << sprintf("<th>phase=%d", sdphase)
    }
    mfxdly_list.each {|mfxdly|
        html_report << sprintf("<tr><th><b>0x%02X</b>", mfxdly)
        sdphase_list.each {|sdphase|
            tpr3 = gen_tpr3(mfxdly, sdphase, adj)
            if not tpr3 then
                html_report << "<td>"
                next
            end
            data = tpr3_status_logs[tpr3]
            if not data then
                html_report << "<td>"
                next
            end
            memtester_log = memtester_logs[tpr3]
            color = get_nice_color(dir, tpr3, data, memtester_log)
            html_report << sprintf("<td bgcolor=%s title='%s'>%s", color, data + "\n" + memtester_log, tpr3_print_name[tpr3])
        }
    }
    html_report << sprintf("</table>\n")

    return {
        :html_report => html_report,
        :memtester_subtest_stats => memtester_subtest_stats,
        :lane_r_fail_stats => lane_r_fail_stats,
        :lane_w_fail_stats => lane_w_fail_stats,
        :lane_r_fail_list => lane_r_fail_list,
        :lane_w_fail_list => lane_w_fail_list,
        :bit_fail_stats => bit_fail_stats,
        :stability_score => stability_score,
        :score_per_sdphase_label => score_per_sdphase_label,
    }
end

print "
<p>
This is a DRAM tuning/overclocking stability report for various <a href='http://linux-sunxi.org'>Allwinner
A10/A13/A20 based devices</a>. It can be automatically generated by the tools from
<a href='https://github.com/ssvb/a10-meminfo'>https://github.com/ssvb/a10-meminfo</a>.
Here we primarily focus on finding optimal
<a href='https://github.com/linux-sunxi/u-boot-sunxi/blob/87ca6dc0262d18b7/board/sunxi/dram_cubietruck.c#L20'>dram_tpr3</a>
values, tuned individually for every sunxi device. Currently these values need to be hardcoded
into the sources of the <a href='http://linux-sunxi.org/U-boot'>u-boot-sunxi</a> bootloader.
The dram_tpr3 parameter is just a hexadecimal number, composed of the following bit-fields:
<ul>
<li>bits [22:20] - MFWDLY of the command lane
<li>bits [18:16] - MFBDLY of the command lane
<li>bits [15:12] - SDPHASE of the byte lane 3
<li>bits  [11:8] - SDPHASE of the byte lane 2
<li>bits   [7:4] - SDPHASE of the byte lane 1
<li>bits   [3:0] - SDPHASE of the byte lane 0
</ul>

The <a href='https://github.com/OLIMEX/OLINUXINO/blob/master/HARDWARE/RK3066-PDFs/Rockchip%20RK30xx%20TRM%20V2.0.pdf'>RK30XX manual</a>
can be checked to find more details about the MFWDLY, MFBDLY and SDPHASE bit fields.
The Rockchip 30XX family of SoCs is apparently using a bit different revision of the
same DRAM controller IP. So while there is no perfect match with the DRAM controller
in Allwinner A10/A13/A20, it is still good enough.
</p>
<p>
Results interpretation:
<ul>
<li>The shades of pure RED mean hardware deadlocks. Too many of them sometimes
indicate insufficient dcdc3 voltage, which is configured as
<a href='https://github.com/linux-sunxi/sunxi-boards/blob/c36a1c2186b4/sys_config/a20/cubietruck.fex#L11'>dcdc3_vol</a>
variable in fex files.
<li>The shades of RED/ORANGE/YELLOW mean data corruption on read operations. This may be attributed
to other reasons. Including, but not limited to phase misalignment between different byte lanes.
See the Figure 6 from
<a href='http://www.altera.com/literature/wp/wp-01034-Utilizing-Leveling-Techniques-in-DDR3-SDRAM.pdf'>Altera
- Utilizing Leveling Techniques in DDR3 SDRAM Memory Interfaces</a> as a reasonaby good illustration.
<li>The shades of RED/PURPLE/MAGENTA mean data corruption on write operations.
<li>LIGHTGREEN - no problems detected during only a few minutes of running
<a href='https://github.com/ssvb/lima-memtester/'>lima-memtester</a>.
<li>DARKGREEN - no problems detected during up to roughly half an hour run of lima-memtester
(these extra 'hardening' tests are performed after all the preliminary data has been collected).
But even these dram_tpr3 values still need thorough verification by a much longer run of lima-memtester
(8-10 hours is reasonable) and other stress tests.
<li>Some digits of the dram_tpr3 values in the table(s) below may be shown using bold font.
This indicates data corruption problem detected in the corresponding byte lane(s).
</ul>

Note: after all the tests have successfully passed for some dram_tpr3 value, it is still
a good idea to increase the dcdc3 voltage by 0.025V and/or reduce the DRAM clock speed
by 24MHz in order to have some safety margin. Selecting the dram_tpr3 values from the
middle of some large green isle is assumed to be a good idea too (it should be less
sensitive to the parameters drift caused by temperature changes or some other
environmental factors).
</p>
"

dirlist = []
Dir.glob(File.join(ARGV[0], "*")).each {|f|
    next if not File.directory?(f)
    dirlist.push(f)
}

def strip_html_tags(text)
    return text.gsub(/\<[\/]?a.*?\>/, "")
end

# Group results from the same device/configuration/description
tmp = {}
dirlist.sort.each {|f|
    if File.basename(f) =~ /(.*MHz\-\d+\.\d+V-[0-9A-F]{8})/ then
        id = $1
        id = (read_file(f, "_description.txt") or "") + " : " + id
        tmp[id] = [] if not tmp.has_key?(id)
        tmp[id].push(f)
    end
}
dirlist = []
tmp.to_a.sort {|x,y| strip_html_tags(x[0]) <=> strip_html_tags(y[0]) }.each {|x|
    dirlist.push(x[1])
}

dirlist.each {|a|
    a10_meminfo = read_file(a[0], "_a10_meminfo.txt")
    if not a10_meminfo =~ /dram_bus_width\s*=\s*(\d+)/ then
        raise("Error: dram_bus_width is not found in the a10-meminfo log\n")
    end
    $number_of_lanes = $1.to_i / 8

    printf("<h2><b>%s</b></h2>\n",
           (read_file(a[0], "_description.txt") or "Unknown device"))

    printf("<table border=1 style='border-collapse: collapse;")
    printf(" empty-cells: show; font-family: Consolas,Monaco,Lucida Console,Liberation Mono,DejaVu Sans Mono,Bitstream Vera Sans Mono,Courier New, monospace; font-size: small;")
    printf(" white-space: nowrap; background: #F0F0F0;'>\n")

    a.each {|f|
        jobs_finder_generator(f, {:sorted => true}).each {|job_info|
            adj = job_info[:lane_phase_adjustments]
    printf("<tr>")
    printf("<td><table border=0 style='border-collapse: collapse;")
    printf(" empty-cells: show; font-family: Consolas,Monaco,Lucida Console,Liberation Mono,DejaVu Sans Mono,Bitstream Vera Sans Mono,Courier New, monospace; font-size: small;")
    printf(" white-space: nowrap; background: #F0F0F0;'>\n")
    printf("<tr><td>%s", a10_meminfo.gsub("\n", "<br>"))
    printf("</table>")

            subtest_results = parse_subtest_dir(f, adj)
            printf("<td>%s", subtest_results[:html_report])
            printf("<td>")

            printf("Lane phase adjustments: [%s]<br>", adj.reverse.join(", "))
            memtester_subtest_stats = subtest_results[:memtester_subtest_stats].to_a
            memtester_subtest_stats.sort! {|x, y| y[1] <=> x[1] }
            printf("Error statistics from memtester: [%s]<br>",
                   memtester_subtest_stats.map {|a|
                       sprintf("%s=%d", a[0], a[1])
                   }.join(", "))
            column_scores = subtest_results[:score_per_sdphase_label].sort.map {|a| a[1] }
            printf("<br>")
            1.upto(column_scores.size) {|s|
                score, i = column_scores.each_index.map {|i|
                     tmp = column_scores.slice(i, s)
                     tmp.size == s ? (tmp.inject 0, :+) : 0
                 }.each_with_index.max
                 printf("Best number of successful memtester runs, which span over %d columns (%d-%d): %d<br>",
                        s, i, i + s - 1, score)
            }

            def print_lane_err_stats(prefix, lane_fail_stats, lane_fail_list)
                printf("<br>%s errors per lane: [%s]. ", prefix,
                       lane_fail_stats.reverse.join(", "))

                worst_lane_id = lane_fail_stats.each_with_index.max[1]
                worst_lane_fail_list = lane_fail_list[worst_lane_id]
                printf("Lane %d is the most noisy/problematic.<br>", worst_lane_id)

                something_is_still_bad = false
                lane_fail_list.each_with_index {|fail_list, lane_id|
                    matched_cnt = 0
                    total_cnt = 0
                    fail_list.each {|tpr3, dummy|
                        matched_cnt += 1 if worst_lane_fail_list.has_key?(tpr3)
                        total_cnt += 1
                    }
                    if total_cnt > 0 and lane_id != worst_lane_id then
                        something_is_still_bad = true if matched_cnt != total_cnt

                        if matched_cnt > 0 then
                            printf("Errors from the lane %d are %.1f%% eclipsed by the worst lane %d.<br>",
                                   lane_id, (matched_cnt.to_f / total_cnt.to_f) * 100,
                                   worst_lane_id)
                        else
                            printf("Errors from the lane %d are not intersecting with the errors from the worst line %d.<br>",
                                   lane_id, worst_lane_id)
                        end
                    end
                }
                return worst_lane_id
            end

            print_lane_err_stats("Read", subtest_results[:lane_r_fail_stats],
                                         subtest_results[:lane_r_fail_list])
            print_lane_err_stats("Write", subtest_results[:lane_w_fail_stats],
                                          subtest_results[:lane_w_fail_list])

#            if something_is_still_bad then
#                adj1 = adj.each_with_index.map {|x, i| i == worst_lane_id ? x : x - 1}
#                adj2 = adj.each_with_index.map {|x, i| i == worst_lane_id ? x : x + 1}
#                printf("<br>Need to try lane phase adjustments <b>[%s]</b> and <b>[%s]</b> for further analysis.<br>",
#                      adj1.reverse.join(", "), adj2.reverse.join(", "))
#            end
        }
    }
    printf("</table>")
    printf("</p>\n")
}
