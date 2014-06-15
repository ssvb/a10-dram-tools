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

def read_file(dir = nil, name)
    fullname = dir ? File.join(dir, name) : name
    return if not File.exists?(fullname)
    fh = File.open(fullname, "rb")
    data = fh.read
    fh.close
    return data
end

# Decodes the SDPHASE bit field value (see the RK30XX manual) to a
# value in degrees.

def convert_sdphase_deg_to_tpr3(sdphase_deg)
    return {36 => 0x3, 54 => 0x2, 72 => 0x1, 90 => 0x0, 108 => 0xe,
                   126 => 0xd, 144 => 0xc}[sdphase_deg]
end

# Encodes the phase from degrees to the SDPHASE bit field format.

def convert_sdphase_tpr3_to_deg(sdphase_tpr3)
    return {0x3 => 36, 0x2 => 54, 0x1 => 72, 0x0 => 90, 0xe => 108,
               0xd => 126, 0xc => 144}[sdphase_tpr3]
end

# Generate a tpr3 32-bit number from the MFWDLY, MFBDLY and SDPHASE bit
# fields. See the RK30XX manual for the description of these bit fields.
# The tpr3 value itself is just Allwinner specific way of storing these
# bit fields in a 32-bit parameter variable for use in the fex files
# or in u-boot.

def gen_tpr3_unadjusted(mfxdly, sdphase_deg, number_of_lanes)
    sdphase_tpr3 = convert_sdphase_deg_to_tpr3(sdphase_deg)
    return (sdphase_tpr3 * (0x1111 >> (4 * (4 - number_of_lanes)))) | (mfxdly << 16)
end

# Applies a specified phase adjustment to a tpr3 value and returns
# an updated tpr3 value.

def apply_tpr3_adjustment(tpr3, lane_phase_adjust)
    lane_phase_adjust.each_index {|lane|
        mask = 0xF << (lane * 4)
        x = (tpr3 >> (lane * 4)) & 0xF
        sdphase = {0x3 => 36, 0x2 => 54, 0x1 => 72, 0x0 => 90, 0xe => 108,
                   0xd => 126, 0xc => 144}[x]
        raise "bad sdphase in tpr3" if not sdphase
        sdphase += lane_phase_adjust[lane] * 18
        return if sdphase < 36 or sdphase > 126
        sdphase = [[sdphase, 36].max, 144].min
        x = {36 => 0x3, 54 => 0x2, 72 => 0x1, 90 => 0x0, 108 => 0xe,
                   126 => 0xd, 144 => 0xc}[sdphase]
        tpr3 &= ~mask
        tpr3 |= x << (lane * 4)
    }
    return tpr3
end

# Generate a tpr3 value and apply lane specific phase adjustments to it.

def gen_tpr3(mfxdly, sdphase_deg, adj)
    tpr3_unadjusted = gen_tpr3_unadjusted(mfxdly, sdphase_deg, adj.size)
    tpr3 = apply_tpr3_adjustment(tpr3_unadjusted, adj)
    return tpr3
end

# Returns a generator, which can produce a sequence of tpr3 values needed
# for the test run, using 'adj' array for individual lane phase adjustments.

def tpr3_generator(adj)
    number_of_lanes = adj.size
    tpr3_gen = Enumerator::Generator.new {|tpr3_gen|
        [0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00,
         0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38].each {|mfxdly|
            [0x3, 0x2, 0x1, 0x0, 0xe, 0xd].each {|sdphase_tpr3|
                sdphase_deg = convert_sdphase_tpr3_to_deg(sdphase_tpr3)
                tpr3_unadjusted = gen_tpr3_unadjusted(mfxdly, sdphase_deg,
                                                      number_of_lanes)
                tpr3 = apply_tpr3_adjustment(tpr3_unadjusted, adj)
                if tpr3 then
                    tpr3_gen.yield({
                        :tpr3 => tpr3,
                        :tpr3_unadjusted => tpr3_unadjusted,
                        :sdphase_deg => sdphase_deg
                    })
                end
            }
        }
    }
end

# Scans the directory for 'job' description files. Each job is actually
# fully encoded in the file name. Example:
#
#    _job_phase+=[+0,+0,+1,+0].priority_1000
#
# The file name begins with the '_job_' prefix. And then there
# are dot separated fields. The example above uses lane phase
# adjustments [0, 0, 1, 0]. The adjustments are represented
# as 18 degree steps. It means that there is no phase tweak
# for the lanes 0, 2 and 3. And lane 1 needs a phase adjustment
# by +18 degrees.

# The 'priority' part specifies the priority of this job. Jobs with
# the higher priority number will be processed first. The jobs with
# equal priority are either handled in a deterministic order (just
# sorted by name) or in a random order. This is configured by the
# 'sorted' key to a boolean variable in the 'opts' hash.
#
# If there is a '.done' suffix in the job file name, then this
# job is considered as already completed.
#
# The 'jobs_finder_generator' function returns a generator, which
# can produce a sequence of job descriptors (hashes with a bunch
# of keys).

def jobs_finder_generator(dir, opts)
    jobs_finder_gen = Enumerator::Generator.new {|jobs_finder_gen|
        jobs_list = {}
        Dir.glob(File.join(dir, "_job_*")).each {|fullpath|
            filename = File.basename(fullpath)
            priority = (filename =~ /\.priority_(\d+)/) ? $1.to_i : 0
            jobs_list[priority] = [] if not jobs_list.has_key?(priority)
            jobs_list[priority].push(fullpath)
        }
        # Sort the jobs based on priority
        jobs_list.sort.reverse.each {|jobs_priority_bin|
            # Pick jobs from the highest priority bin in random
            # or sorted order
            list_of_fullpaths = opts[:sorted] ? jobs_priority_bin[1].sort :
                                                jobs_priority_bin[1].shuffle
            list_of_fullpaths.each {|fullpath|
                # Parse the job information
                filename = File.basename(fullpath)
                if filename =~ /phase\+\=\[(.*?)\]/ then
                    adj = $1.split(",").reverse.map {|x| x.to_i}
                    jobs_finder_gen.yield({
                        :lane_phase_adjustments => adj,
                        :priority => jobs_priority_bin[0],
                        :done => (fullpath =~ /\.done$/) ? true : false,
                        :hardening => (filename =~ /hardening/) ? true : false,
                        :job_file_name => fullpath,
                    })
                end
            }
        }
    }
end
