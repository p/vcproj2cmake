#!/usr/bin/ruby -w

require 'find'
require 'pathname'

# HACK: have $script_dir as global variable currently
$script_dir = File.dirname(__FILE__)

def v2cc_load_path_extend_for_own_libs
  script_dir_lookup = $script_dir.clone

  script_dir_lookup += '/.'
  $LOAD_PATH.unshift(script_dir_lookup) unless $LOAD_PATH.include?(script_dir_lookup)
  script_dir_lookup += '/lib'
  $LOAD_PATH.unshift(script_dir_lookup) unless $LOAD_PATH.include?(script_dir_lookup)

  #puts "LOAD_PATH: #{$LOAD_PATH.inspect}\n" # nice debugging
end

v2cc_load_path_extend_for_own_libs()

require 'vcproj2cmake/v2c_core' # (currently) large amount of random "core" functionality

################
#     MAIN     #
################

# FIXME: currently this code below still is a bit unstructured / dirty
# (some parts open-coded rather than clean helpers).


script_fqpn = File.expand_path $0
script_path = Pathname.new(script_fqpn).parent
source_root = Dir.pwd

v2c_path_config = v2c_get_path_config(source_root)

v2c_config_dir_source_root = v2c_path_config.get_abs_config_dir_source_root()
time_cmake_root_folder = 0
arr_excl_proj_expr = Array.new()
time_cmake_root_folder = File.stat(v2c_config_dir_source_root).mtime.to_i
excluded_projects = File.join(v2c_config_dir_source_root, 'project_exclude_list.txt')
read_commented_text_file_lines(excluded_projects) do |line_payload|
  exclude_expr = line_payload
  #puts "exclude_expr is #{exclude_expr}"
  next if exclude_expr.empty?
  # TODO: we probably need a per-platform implementation,
  # since exclusion is most likely per-platform after all
  arr_excl_proj_expr.push(exclude_expr)
end

class UnitWorkData
  WORK_FLAG_IS_SOLUTION_DIR = 1
  def initialize(arr_proj_files, str_destination_dir, work_flags)
    @arr_proj_files = arr_proj_files
    @str_destination_dir = str_destination_dir
    @work_flags = work_flags
  end
  attr_accessor :arr_proj_files
  attr_accessor :str_destination_dir
  attr_accessor :work_flags
end

arr_work_units = Array.new

# FIXME: should _split_ operation between _either_ scanning entire .vcproj hierarchy into a
# all_sub_projects.txt, _or_ converting all sub .vcproj as listed in an existing all_sub_projects.txt file.
# (provide suitable command line switches)
# Hmm, or perhaps port _everything_ back into vcproj2cmake.rb,
# providing --recursive together with --scan or --convert switches for all_sub_projects.txt generation or use.


# Pre-configure a directory exclusion pattern regex:
arr_excl_dir_expr_skip_recursive_static = [ \
  '\.svn', \
  '\.git', \
  '__MACOSX' \
] # TODO transform this into a config setting? Also, each entry should have a description string

# NOTE: arr_excl_expr is expected to contain entries with already
# regex-compatible (potentially escaped) content (we will not run
# Regexp.escape() on that content, since that would reduce freedom
# of expression on the user side!)

def generate_multi_regex(regex_prefix, arr_excl_expr)
  excl_regex = nil
  if not arr_excl_expr.empty?
    excl_regex = "#{regex_prefix}\/("
    excl_regex += arr_excl_expr.join('|')
    excl_regex += ')$'
  end
  return excl_regex
end

# The regex to exclude a single specific directory within the hierarchy:
excl_regex_single = generate_multi_regex('^\.', arr_excl_proj_expr)

# The regex to exclude a match (and all children!) within the hierarchy:
excl_regex_recursive = generate_multi_regex('', arr_excl_dir_expr_skip_recursive_static)

# Guards against exceptions due to encountering mismatching-encoding entries
# within the directory.
def dir_entries_grep_skip_broken(dir_entries, regex)
  dir_entries.grep(regex)
rescue ArgumentError => e
  if not V2C_Ruby_Compat::string_start_with(e.message, 'invalid byte sequence')
    raise
  end
  # Hrmpf, *some* entry failed. Rescue operations,
  # by going through each entry manually and logging/skipping broken ones.
  array_collect_compact(dir_entries) do |entry|
    result = nil
    begin
      if not regex.match(entry).nil?
        result = entry
      end
    rescue ArgumentError => e
      if V2C_Ruby_Compat::string_start_with(e.message, 'invalid byte sequence')
        log_error "Dir entry #{entry} has invalid (foreign?) encoding (#{e.message}), skipping!"
        result = nil
      else
        raise
      end
    end
    result
  end
end

# Filters suitable project files in a directory's entry list.
# arr_proj_file_regex should contain regexes for project file matches
# in most (very specific check) to least preferred (generic, catch-all check) order.
def search_project_files_in_dir_entries(dir_entries, arr_proj_file_regex, case_insensitive_regex_match_option_flag)
  # Check pre-conditions.
  arr_proj_file_regex.each { |proj_file_regex|
    if proj_file_regex.include?('(')
      raise V2C_GeneratorError, "regex #{proj_file_regex} is expected to NOT be a match-type (containing brackets) regex!"
    end
  }

  # Somehow implement preference order filtering
  # of possibly multi-matched project file types
  # (to properly prefer e.g. <name>_vc8.vcproj rather than <name>.vcproj
  # and thus ONLY return the most strongly preferred variant).
  # This appears to be a non-trivial task.
  # Indeed, the current implementation *is* quite complex.
  # Maybe there's actually a much easier way to do it - I don't know...

  # Try hard to have an implementation with at most O(n) complexity.
  # Well, our easiest implementation doesn't have that... (more like O(n^2)?).

  # As pre-processing (to get rid of all completely irrelevant entries),
  # figure out the few initially matching files within the directory
  # which actually match in general and thus are candidates:
  dir_entries_match_subset = Array.new
  arr_proj_file_regex.each { |proj_file_regex|
    proj_file_regex_tweaked = Regexp.new(proj_file_regex.to_s, case_insensitive_regex_match_option_flag)
    dir_entries_match_subset_new = dir_entries_grep_skip_broken(dir_entries, /#{proj_file_regex_tweaked}/)
    dir_entries_match_subset.concat(dir_entries_match_subset_new)
  }

  dir_entries_match_subset.uniq!
  log_debug "Initially grepped candidates within directory: #{dir_entries_match_subset.inspect}"

  # Shortcut: return immediately if pre-list ended up empty already:
  return dir_entries_match_subset if dir_entries_match_subset.empty?

  dir_entries_match_subset_remaining = dir_entries_match_subset.clone

  # Regexes going from most specific to least specific.
  arr_proj_file_regex_remaining = arr_proj_file_regex.clone
  arr_proj_file_regex.each { |proj_file_regex|
    # We're analyzing this more specific regex right now -
    # this means in future we won't need this very regex any more :)
    arr_proj_file_regex_remaining.delete(proj_file_regex)
    proj_file_generic_match_regex = Regexp.new("(.*)(#{proj_file_regex})(.*)", case_insensitive_regex_match_option_flag)
    log_debug "Apply regex #{proj_file_generic_match_regex} on dir_entries_match_subset_remaining"
    less_specific_dir_entries_to_remove = nil
    dir_entries_match_subset_remaining.each { |dir_entry|
      matchdata = dir_entry.match(proj_file_generic_match_regex)
      if not matchdata.nil?
        match_prefix = matchdata[1]
        match_suffix = matchdata[3]
        log_debug "Applied #{proj_file_generic_match_regex}: FOUND specific entry #{dir_entry} (resulting prefix \"#{match_prefix}\", suffix \"#{match_suffix}\"), now removing all similar dir entries having related matches of less specific regexes"
        less_specific_dir_entries_to_remove = Array.new
        arr_proj_file_regex_remaining.each { |proj_file_deathbound_regex|
          regex_full = match_prefix + proj_file_deathbound_regex + match_suffix
          proj_file_generic_deathbound_regex = Regexp.new(regex_full, case_insensitive_regex_match_option_flag)
          dir_entries_match_subset_remaining.each { |proj_file_deathbound|
            # Obviously need to skip that very entry that we found:
            next if dir_entry.eql?(proj_file_deathbound)

            matchdata_deathbound = proj_file_deathbound.match(proj_file_generic_deathbound_regex)
            log_debug "matched #{proj_file_deathbound} against #{proj_file_generic_deathbound_regex} (options #{proj_file_generic_deathbound_regex.options}) --> matchdata #{matchdata_deathbound}"
            if not matchdata_deathbound.nil?
              log_debug "FOUND deathbound candidate #{proj_file_deathbound} (lost against #{dir_entry} due to match regex #{proj_file_deathbound_regex})"
              less_specific_dir_entries_to_remove.push(proj_file_deathbound)
            end
          }
        }
      end
    }
    if not less_specific_dir_entries_to_remove.nil?
      dir_entries_match_subset_remaining -= less_specific_dir_entries_to_remove
    end
  }
  log_debug \
    "Filtered:\n" \
    "fileset #{dir_entries_match_subset_remaining.inspect}\n" \
    "from #{dir_entries_match_subset.inspect}\n" \
    "via regexes #{arr_proj_file_regex.inspect}"
  # No project file type at all? Immediately skip directory.
  return nil if dir_entries_match_subset_remaining.empty?
  return dir_entries_match_subset_remaining
end

DETECT_MAC_OS_RESOURCE_FORK_FILES_REGEX_OBJ = %r{^\._}

def filter_unwanted_project_files(arr_dir_proj_files)
  if not arr_dir_proj_files.nil?
    arr_dir_proj_files.delete_if { |proj_file_candidate|
      delete_element = false
      if DETECT_MAC_OS_RESOURCE_FORK_FILES_REGEX_OBJ.match(proj_file_candidate)
        proj_file_candidate_location = File.join(dir, proj_file_candidate)
        log_info "Deleting element containing unrelated Mac OS resource fork file #{proj_file_candidate_location}"
        delete_element = true
      end
      delete_element
    }
  end
  arr_dir_proj_files
end

# FIXME: completely broken - should stat command_output_file against the file dependencies
# in the array, to determine whether to rebuild.
def command_file_dependencies_changed(command_output_file, arr_file_deps)
  time_proj = File.stat(str_proj_file).mtime.to_i
  time_cmake_folder = 0
  config_dir_local = File.join(f, $v2c_config_dir_local)
  if File.exist?(config_dir_local)
    time_cmake_folder = File.stat(config_dir_local).mtime.to_i
  end
  time_CMakeLists = File.stat(str_cmakelists_file).mtime.to_i
  log_debug "TIME: CMakeLists #{time_CMakeLists} proj #{time_proj} cmake_folder #{time_cmake_folder} cmake_root_folder #{time_cmake_root_folder}"
  if time_proj > time_CMakeLists
    log_debug "modified: project!"
    rebuild = 1
  elsif time_cmake_folder > time_CMakeLists
    log_debug "modified: cmake/!"
    rebuild = 1
  elsif time_cmake_root_folder > time_CMakeLists
    log_debug "modified: cmake/ root!"
    rebuild = 1
  end
end

case_insensitive_regex_match_option_flag = nil
str_case_match_type = ''
if true == $v2c_parser_proj_files_case_insensitive_match
  str_case_match_type = 'IN'
  case_insensitive_regex_match_option_flag = Regexp::IGNORECASE
end
log_info "Doing case-#{str_case_match_type}SENSITIVE matching on project file candidates!"

# Cannot use Array.compact() for Find.find()
# since that one is "special" (at least on < 1.9!?)
# ("Local Jump Error" http://www.ruby-forum.com/topic/153730 )
arr_filtered_dirs = Array.new

Find.find('./') do |item|
  next if not test(?d, item)
  dir = item

  log_debug "CRAWLED: #{dir}"

  # skip symlinks since they might be pointing _backwards_!
  next if FileTest.symlink?(dir)

  is_excluded_recursive = false
  if not excl_regex_recursive.nil?
    #puts "MATCH: #{dir} vs. #{excl_regex_recursive}"
    if dir.match(excl_regex_recursive)
      is_excluded_recursive = true
    end
  end
  # Also, skip CMake build directories! (containing CMake-generated .vcproj files!)
  # FIXME: more precise checking: check file _content_ against CMake generation!
  if true != is_excluded_recursive
    if dir =~ /\/build[^\/]*$/i
      is_excluded_recursive = true
    end
  end
  if true == is_excluded_recursive
    puts "EXCLUDED RECURSIVELY #{dir}!"
    Find.prune() # throws exception to skip entire recursive directories block
  end

  is_excluded_single = false
  if not excl_regex_single.nil?
    #puts "MATCH: #{dir} vs. #{excl_regex_single}"
    if dir.match(excl_regex_single)
      is_excluded_single = true
    end
  end
  #puts "excluded: #{is_excluded_single}"
  if true == is_excluded_single
    puts "EXCLUDED SINGLE #{dir}!"
    next
  end
  arr_filtered_dirs.push(dir)
end

log_debug "arr_filtered_dirs: #{arr_filtered_dirs.inspect}"


def cmakelists_may_get_created(dir, dir_entries)
  want_new_cmakelists_file = true

  str_cmakelists_file = File.join(dir, CMAKELISTS_FILE_NAME)

  # Check whether the directory already contains a CMakeLists.txt,
  # and if so, whether it can be safely rewritten.
  # These checks arguably perhaps shouldn't be done in the recursive handler,
  # but directly in the main conversion handler instead. TODO?
  if (!dir_entries.grep(/^#{CMAKELISTS_FILE_NAME}$/i).empty?)
    log_debug dir_entries
    log_debug "#{CMAKELISTS_FILE_NAME} exists in #{dir}, checking!"
    want_new_cmakelists_file = v2c_want_cmakelists_rewritten(str_cmakelists_file)
  end
  want_new_cmakelists_file
end


csproj_extension = 'csproj'
vcproj_extension = 'vcproj'
vcxproj_extension = 'vcxproj'

# In each directory, find the .vc[x]proj files to use.
# In case of .vcproj type files, prefer xxx_vc8.vcproj,
# but in cases of directories where this is not available, use a non-_vc8 file.
# WARNING: ensure comma separation between array elements!
arr_proj_file_regex = [
  "_vc10\.#{vcxproj_extension}$",
  "\.#{vcxproj_extension}$",
  "_vc8\.#{vcproj_extension}$",
  "\.#{vcproj_extension}$",
  "\.#{csproj_extension}$",
]

# The (usually root-level) directory of the whole "emulated" "solution".
solution_dir = './'

arr_project_subdirs = Array.new

arr_filtered_dirs.each do |dir|
  log_info "processing #{dir}!"
  dir_entries = Dir.entries(dir)

  log_debug "entries: #{dir_entries.inspect}"

  arr_dir_proj_files = search_project_files_in_dir_entries(dir_entries, arr_proj_file_regex, case_insensitive_regex_match_option_flag)

  arr_dir_proj_files = filter_unwanted_project_files(arr_dir_proj_files)

  arr_proj_files = array_collect_compact(arr_dir_proj_files) do |projfile|
    suggest_specific_naming = false
    if true == suggest_specific_naming
      if projfile =~ /.#{vcproj_extension}$/i
        if projfile =~ /_vc8.#{vcproj_extension}$/i
        else
          log_info "Darn, no _vc8.vcproj in #{dir}! Should have offered one..."
        end
      end
    end
    str_proj_file = File.join(dir, projfile)
    log_debug "Checking CMake-side generation possibility of #{str_proj_file}"
    if true == v2c_is_project_file_generated_by_cmake(str_proj_file)
      log_info "Skipping CMake-generated MSVS file #{str_proj_file}"
      next
    end
    str_proj_file
  end

#  rebuild = 0
#  if File.exist?(str_cmakelists_file)
#    # is .vcproj newer (or equal: let's rebuild copies with flat timestamps!)
#    # than CMakeLists.txt?
#    # NOTE: if we need to add even more dependencies here, then it
#    # might be a good idea to do this stuff properly and use a CMake-based re-build
#    # infrastructure instead...
#    # FIXME: doesn't really seem to work... yet?
#
#    # verify age of .vcproj file... (NOT activated: experimental feature!)
#    # arr_file_deps = [ str_proj_file ]
#    # rebuild = command_file_dependencies_changed(str_cmakelists_file, arr_file_deps)
#  else
#    # no CMakeLists.txt at all, definitely process this project
#    rebuild = 2
#  end
#  if rebuild > 0
#    log_debug "REBUILD #{dir}!! #{rebuild}"
#  end

  # The root directory is special: in case of the V2C part
  # being included within a larger CMake tree,
  # it's already being accounted for (add_subdirectory() of it by other files),   # otherwise it should have a custom CMakeLists.txt
  # which includes our "all projects list" CMake file.
  # Note that the V2C root dir might contain another project
  # (in the case of it being the CMake source root it better shouldn't!!) -
  # then include the root directory project by placing a CMakeLists_native.txt there
  # and have it include the auto-generated CMakeLists.txt.

  is_solution_dir = (dir == solution_dir)

  is_sub_dir = (true != is_solution_dir)

  if is_sub_dir
    # No project file at all? Skip directory.
    next if arr_proj_files.empty?
  end

  if not cmakelists_may_get_created(dir, dir_entries)
    if is_solution_dir
      log_error "cannot create CMakeLists.txt in solution directory #{dir}!?"
    end
    next
  end

  if is_sub_dir
    arr_project_subdirs.push(dir)
  end

  # For recursive invocation we used to have _external spawning_
  # of a new vcproj2cmake.rb session, but we _really_ don't want to do that
  # since Ruby startup latency is extremely high
  # (3 seconds startup vs. 0.3 seconds payload compute time with our script!)

  # Collect the list of projects to convert,
  # then attempt to call v2c_convert_local_projects_outer()
  # in some parallel execution mode!
  # (although threading is said to be VERY slow in Ruby -
  # but still it should provide some sizeable benefit).
  log_debug "Submitting #{arr_proj_files.inspect} to be converted in #{dir}."
  unit_work = UnitWorkData.new(arr_proj_files, dir, is_solution_dir ? UnitWorkData::WORK_FLAG_IS_SOLUTION_DIR : 0)
  arr_work_units.push(unit_work)

  #output.split("\n").each do |line|
  #  puts "[parent] output: #{line}"
  #end
  #puts
end

# Hrmm, many Ruby implementations have "green threads", i.e.
# implementing _cooperative_ (non-parallel) threading.
# Perhaps there's a flag to query whether a particular Ruby Thread
# implementation has cooperative or real (multi-core) threading.
# Otherwise we should probably just prefer to use Process.fork()
# (I hate all those dirty global-addressspace thread implementations anyway,
# real separate-process handling with clean IPC is a much better idea
# in several cases).

# Small helper to hold all settings which are common to all threads.
class UnitGlobalData
  def initialize(script_location, source_root)
    @script_location = script_location
    @source_root = source_root
  end
  attr_accessor :script_location
  attr_accessor :source_root
end

def execute_work_unit(unitGlobal, myWork)
  v2c_convert_local_projects_outer(unitGlobal.script_location, unitGlobal.source_root, myWork.arr_proj_files, myWork.str_destination_dir, nil, (myWork.work_flags & UnitWorkData::WORK_FLAG_IS_SOLUTION_DIR) > 0)
end

def execute_work_units(unitGlobal, arr_work_units)
  log_info 'Worker starting.'
  arr_work_units.each { |work_unit|
    execute_work_unit(unitGlobal, work_unit)
  }
  log_info 'Worker finished.'
end

def execute_work_package(unitGlobal, workPackage, want_multi_processing)
  if (want_multi_processing and $v2c_enable_processes)
    # See also http://stackoverflow.com/a/1076445
    log_info 'Recursively converting projects, multi-process.'
    workPackage.each { |arr_work_units_per_worker|
      pid = fork {
        log_info("Process ID #{Process.pid()} started.")
        # Nope, does not seem to be true - anyway,
        # we'll keep this code since I'm not entirely sure...
        #begin
          execute_work_units(unitGlobal, arr_work_units_per_worker)
        #rescue Exception => e
        #  # Need to add an open-coded exception logging line
        #  # since foreign-process exceptions will be swallowed silently!
        #  puts "EXCEPTION!! #{e.inspect} #{e.backtrace}"
        #end
      }
      log_info("Worker PID #{pid} forked.")
    }
    log_info 'Waiting for all worker processes to finish...'
    results = Process.waitall
    log_info 'Waiting for all worker processes: done.'
    # MAKE DAMN SURE to properly signal exit status
    # in case any of the sub processes happened to fail,
    # otherwise it would be silently swallowed! (exit 0, success)
    results.each { |result|
      worker_exitstatus = result[1].exitstatus
      if 0 != worker_exitstatus
        log_error "Worker (PID #{result[0]}) indicated failure (non-zero exit status #{worker_exitstatus}), exiting!"
        # Side note: be sure to read
        # http://www.bigfastblog.com/ruby-exit-exit-systemexit-and-at_exit-blunder
        exit worker_exitstatus
      end
    }
  elsif (want_multi_processing and $v2c_enable_threads)
    log_info 'Recursively converting projects, multi-threaded.'

    # "Ruby-Threads erzeugen"
    #    http://home.vr-web.de/juergen.katins/ruby/buch/tut_threads.html

    threads = []

    for arr_work_units_per_worker in workPackage
      threads << Thread.new(arr_work_units_per_worker) { |arr_work_units|
        log_info "Thread #{Thread.current.object_id} started."
        execute_work_units(unitGlobal, arr_work_units)
      }
    end

    log_info 'Waiting for all worker threads to finish...'
    # This amount ought to be enough even for the most daring of environments...
    thread_wait_seconds = 120
    threads.each { |aThread|
      # Could add a count here, to bail out only after a certain limit is reached
      while aThread.join(thread_wait_seconds).nil?
        # Still running!? It's best to cleanly(?) error out completely,
        # since continuing (i.e. merely breaking out of the loop)
        # while having a thread running and remaining in unknown state
        # may cause really un-"nice" issues.
        log_warn "Worker thread (ID #{aThread.object_id}, (#{aThread.inspect}) still running after #{thread_wait_seconds} seconds!? Exiting!"
        exit 1
      end
    }
    log_info 'Waiting for all worker threads: done.'
  else # single-process
    log_info 'Recursively converting projects, single-process.'
    for arr_work_units_per_worker in workPackage
      execute_work_units(unitGlobal, arr_work_units_per_worker)
    end
  end
end

def submit_work(unitGlobal, arr_work_units)
  # I'm in fact not sure at all whether this code
  # constitutes a cleanly abstracted implementation
  # (e.g. launch a fixed number of workers, *then* submit work via IPC)
  # of a thread/process pool, but for now... I don't care. ;)


  # Well, what I'd actually like to check is whether Process.fork()
  # is supported or not. But this doesn't seem to be possible,
  # thus we'll have to check for non-Windows (or possibly some
  # check for POSIX might be doable somehow).
  is_hampered_os = (ENV['OS'] == 'Windows_NT')

  $v2c_enable_processes = (false == is_hampered_os)

  num_work_units = arr_work_units.length

  want_multi_processing = (num_work_units > 4)

  num_workers = 1
  # In case of parallel processing, do *not* spawn as many
  # workers as we have work units (for big project source trees
  # this could amount to a DoS of the machine).
  # Do that expensive CPU count query only if we need it...
  if want_multi_processing
    num_cpu_cores = number_of_processors()

    # Definitely have one more worker than number of processing units created,
    # to make sure that scheduler *always* has available
    # at least one readily runnable worker.
    num_workers = num_cpu_cores + 1

    # IMPORTANT CHECK: for large machines, we obviously
    # don't want more workers than the number of work units to be handled.
    if num_workers > num_work_units
      num_workers = num_work_units
    end
  end

  num_work_units_per_worker = num_work_units / num_workers
  # Account for division remainder:
  if (num_work_units_per_worker * num_workers) < num_work_units
    num_work_units_per_worker += 1
  end

  log_info "#{num_work_units} work units, #{num_workers} workers --> determined #{num_work_units_per_worker} work units per worker."

  workPackage = Array.new
  while true
    log_debug "arr_work_units.length #{arr_work_units.length}"
    arr_worker_work_units = arr_work_units.slice!(0, num_work_units_per_worker)
    log_debug "per-worker length: #{arr_worker_work_units.length}, num_work_units_per_worker #{num_work_units_per_worker}"
    break if arr_worker_work_units.nil? or arr_worker_work_units.empty?
    workPackage.push(arr_worker_work_units)
  end

  execute_work_package(unitGlobal, workPackage, want_multi_processing)
end

unitGlobal = UnitGlobalData.new(File.join(script_path, 'vcproj2cmake.rb'), source_root)

log_info 'Work for generation of projects to be submitted...'

submit_work(unitGlobal, arr_work_units)

log_info 'Work for generation of projects finished - starting post-processing steps...'

# Now, write out the file for the projects list (separate from any
# multi-processing implementation).
# But only do this if indeed we do have any projects located in sub dirs
# (the root file can obviously handle its own local projects, no
# add_subdirectory() things needed).
if not arr_project_subdirs.empty?
  v2c_projects_list_handle_sub_dirs(Pathname.new(source_root), arr_project_subdirs)
end

v2c_convert_finished()
