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
excluded_projects = "#{v2c_config_dir_source_root}/project_exclude_list.txt"
if File.exist?(excluded_projects)
  begin
    f_excl = File.new(excluded_projects, 'r')
    f_excl.each do |line_raw|
      exclude_expr, comment = line_raw.chomp.split('#')
      #puts "exclude_expr is #{exclude_expr}"
      next if exclude_expr.empty?
      # TODO: we probably need a per-platform implementation,
      # since exclusion is most likely per-platform after all
      arr_excl_proj_expr.push(exclude_expr)
    end
  ensure
    f_excl.close
  end
end

class UnitWorkData
  WORK_FLAG_IS_ROOT_DIR = 1
  def initialize(arr_proj_files, str_destination_dir, work_flags)
    @arr_proj_files = arr_proj_files
    @str_destination_dir = str_destination_dir
    @work_flags = work_flags
  end
  attr_accessor :arr_proj_files
  attr_accessor :str_destination_dir
end

arr_unit_work = Array.new

arr_project_subdirs = Array.new

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
    dir_entries_match_subset_new = dir_entries.grep(/#{proj_file_regex_tweaked}/)
    dir_entries_match_subset.concat(dir_entries_match_subset_new)
  }

  dir_entries_match_subset.uniq!
  log_debug "Initially grepped candidates within directory: #{dir_entries_match_subset.inspect}"

  # Shortcut: return immediately if pre-list ended up empty already:
  return nil if dir_entries_match_subset.empty?

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
          proj_file_generic_deathbound_regex = Regexp.new("#{match_prefix}#{proj_file_deathbound_regex}#{match_suffix}", case_insensitive_regex_match_option_flag)
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

# FIXME: completely broken - should stat command_output_file against the file dependencies
# in the array, to determine whether to rebuild.
def command_file_dependencies_changed(command_output_file, arr_file_deps)
  time_proj = File.stat(str_proj_file).mtime.to_i
  time_cmake_folder = 0
  config_dir_local = "#{f}/#{$v2c_config_dir_local}"
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

DETECT_MAC_OS_RESOURCE_FORK_FILES_REGEX_OBJ = %r{^\._.*}
Find.find('./') do
  |f|
  next if not test(?d, f)
  # skip symlinks since they might be pointing _backwards_!
  next if FileTest.symlink?(f)

  is_excluded_recursive = false
  if not excl_regex_recursive.nil?
    #puts "MATCH: #{f} vs. #{excl_regex_recursive}"
    if f.match(excl_regex_recursive)
      is_excluded_recursive = true
    end
  end
  # Also, skip CMake build directories! (containing CMake-generated .vcproj files!)
  # FIXME: more precise checking: check file _content_ against CMake generation!
  if true != is_excluded_recursive
    if f =~ /\/build[^\/]*$/i
      is_excluded_recursive = true
    end
  end
  if true == is_excluded_recursive
    puts "EXCLUDED RECURSIVELY #{f}!"
    Find.prune() # throws exception to skip entire recursive directories block
  end

  is_excluded_single = false
  if not excl_regex_single.nil?
    #puts "MATCH: #{f} vs. #{excl_regex_single}"
    if f.match(excl_regex_single)
      is_excluded_single = true
    end
  end
  #puts "excluded: #{is_excluded_single}"
  if true == is_excluded_single
    puts "EXCLUDED SINGLE #{f}!"
    next
  end

  log_info "processing #{f}!"
  dir_entries = Dir.entries(f)

  log_debug "entries: #{dir_entries}"

  vcproj_extension = 'vcproj'
  vcxproj_extension = 'vcxproj'

  # In each directory, find the .vc[x]proj files to use.
  # In case of .vcproj type files, prefer xxx_vc8.vcproj,
  # but in cases of directories where this is not available, use a non-_vc8 file.
  # WARNING: ensure comma separation between entries!
  arr_proj_file_regex = [ \
    "_vc10\.#{vcxproj_extension}$",
    "\.#{vcxproj_extension}$",
    "_vc8\.#{vcproj_extension}$",
    "\.#{vcproj_extension}$" \
  ]

  arr_dir_proj_files = search_project_files_in_dir_entries(dir_entries, arr_proj_file_regex, case_insensitive_regex_match_option_flag)

  if not arr_dir_proj_files.nil?
    arr_dir_proj_files.delete_if { |proj_file_candidate|
      delete_element = false
      if DETECT_MAC_OS_RESOURCE_FORK_FILES_REGEX_OBJ.match(proj_file_candidate)
        log_info "Deleting unrelated Mac OS resource fork file #{f}/#{proj_file_candidate}"
        delete_element = true
      end
      delete_element
    }
  end

  # No project file at all? Skip directory.
  next if arr_dir_proj_files.nil?

  str_cmakelists_file = "#{f}/CMakeLists.txt"

  # Check whether the directory already contains a CMakeLists.txt,
  # and if so, whether it can be safely rewritten.
  # These checks arguably perhaps shouldn't be done in the recursive handler,
  # but directly in the main conversion handler instead. TODO?
  if (!dir_entries.grep(/^CMakeLists.txt$/i).empty?)
    log_debug dir_entries
    log_debug "CMakeLists.txt exists in #{f}, checking!"
    want_new_cmakelists_file = v2c_want_cmakelists_rewritten(str_cmakelists_file)
    next if false == want_new_cmakelists_file
  end

  arr_proj_files = arr_dir_proj_files.collect { |projfile|
    suggest_specific_naming = false
    if true == suggest_specific_naming
      if projfile =~ /.#{vcproj_extension}$/i
        if projfile =~ /_vc8.#{vcproj_extension}$/i
        else
          log_info "Darn, no _vc8.vcproj in #{f}! Should have offered one..."
        end
      end
    end
    str_proj_file = "#{f}/#{projfile}"
    log_debug "Checking CMake-side generation possibility of #{str_proj_file}"
    if true == v2c_is_project_file_generated_by_cmake(str_proj_file)
      log_info "Skipping CMake-generated MSVS file #{str_proj_file}"
      next
    end
    str_proj_file
  }

  # Filter out nil entries (caused by "next" above)
  arr_proj_files.compact!

  next if arr_proj_files.nil?

  rebuild = 0
  if File.exist?(str_cmakelists_file)
    # is .vcproj newer (or equal: let's rebuild copies with flat timestamps!)
    # than CMakeLists.txt?
    # NOTE: if we need to add even more dependencies here, then it
    # might be a good idea to do this stuff properly and use a CMake-based re-build
    # infrastructure instead...
    # FIXME: doesn't really seem to work... yet?

    # verify age of .vcproj file... (NOT activated: experimental feature!)
    # arr_file_deps = [ str_proj_file ]
    # rebuild = command_file_dependencies_changed(str_cmakelists_file, arr_file_deps)
  else
    # no CMakeLists.txt at all, definitely process this project
    rebuild = 2
  end
  if rebuild > 0
    log_debug "REBUILD #{f}!! #{rebuild}"
  end

  # The root directory is special: in case of the V2C part being included within
  # a larger CMake tree, it's already being accounted for
  # (add_subdirectory() of it by other files), otherwise it should have a custom CMakeLists.txt
  # which includes our "all projects list" CMake file.
  # Note that the V2C root dir might contain another project
  # (in the case of it being the CMake source root it better shouldn't!!) -
  # then include the root directory project by placing a CMakeLists_native.txt there
  # and have it include the auto-generated CMakeLists.txt.
  is_root_dir = (f == './')

  arr_project_subdirs.push(f) unless is_root_dir

  # For recursive invocation we used to have _external spawning_
  # of a new vcproj2cmake.rb session, but we _really_ don't want to do that
  # since Ruby startup latency is extremely high
  # (3 seconds startup vs. 0.3 seconds payload compute time with our script!)

  # Collect the list of projects to convert,
  # then call v2c_convert_project_outer() multi-threaded!
  # (although threading is said to be VERY slow in Ruby -
  # but still it should provide some sizeable benefit).
  log_debug "Submitting #{arr_proj_files.inspect} to be converted in #{f}."
  unit_work = UnitWorkData.new(arr_proj_files, f, is_root_dir ? UnitWorkData::WORK_FLAG_IS_ROOT_DIR : 0)
  arr_unit_work.push(unit_work)

  #output.split("\n").each do |line|
  #  puts "[parent] output: #{line}"
  #end
  #puts
end

# Hrmm, many Ruby implementations have "green threads", i.e.
# implementing _cooperative_ (non-parallel) threading.
# Perhaps there's a flag to query whether a particular Ruby Thread
# implementation has cooperative or real (multi-core) threading.
# Otherwise we should probably just use Process.fork() (TODO)
# (I hate all those dirty thread implementations anyway,
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
  # FIXME: str_cmakelists_file_location (that CMakeLists.txt naming)
  # should be an implementation detail of inner handling.
  str_cmakelists_file_location = "#{myWork.str_destination_dir}/CMakeLists.txt"
  v2c_convert_project_outer(unitGlobal.script_location, unitGlobal.source_root, myWork.arr_proj_files, str_cmakelists_file_location)
end

unitGlobal = UnitGlobalData.new("#{script_path}/vcproj2cmake.rb", source_root)

# Well, what I'd actually like to check is whether Process.fork()
# is supported or not. But this doesn't seem to be possible,
# thus we'll have to check for non-Windows (or possibly some
# check for POSIX might be doable somehow).
is_hampered_os = (ENV['OS'] == 'Windows_NT')

$v2c_enable_processes = (false == is_hampered_os)

# TODO: should perhaps take into account number of CPU cores, too.
want_multi_processing = (arr_unit_work.length > 5)

if (want_multi_processing and $v2c_enable_processes)
  # See also http://stackoverflow.com/a/1076445
  log_info 'recursively converting projects, multi-process.'
  arr_unit_work.each { |myWork|
    fork {
      execute_work_unit(unitGlobal, myWork)
    }
  }
  Process.waitall
elsif (want_multi_processing and $v2c_enable_threads)
  log_info 'Recursively converting projects, multi-threaded.'

  # "Ruby-Threads erzeugen"
  #    http://home.vr-web.de/juergen.katins/ruby/buch/tut_threads.html

  threads = []

  for unit_work in arr_unit_work
    threads << Thread.new(unit_work) { |myWork|
      execute_work_unit(unitGlobal, myWork)
    }
  end

  threads.each { |aThread| aThread.join }
else # non-threaded
  log_info 'Recursively converting projects, NON-threaded.'
  arr_unit_work.each { |myWork|
    execute_work_unit(unitGlobal, myWork)
  }
end

# Now, write out the file for the projects list (separate from any
# multi-processing implementation).
# FIXME: since the conversion above may end up multi-processed yet arr_project_subdirs cannot
# be updated on worker side (and in some cases .vcproj conversion *will* be skipped,
# e.g. in case of CMake-converted .vcproj:s),
# we should include only those entries where each directory
# now actually does contain a CMakeLists.txt file.
projects_list_file_name = 'all_sub_projects.txt'
projects_list_file_rel = "#{v2c_path_config.get_rel_config_dir_source_root_temp_store()}/#{projects_list_file_name}"
projects_list_file = "#{v2c_path_config.get_abs_config_dir_source_root_temp_store()}/#{projects_list_file_name}"
v2c_source_root_write_projects_list_file(projects_list_file, $v2c_generator_file_create_permissions, arr_project_subdirs)

# Finally, create a skeleton fallback file if needed.
v2c_source_root_ensure_usable_cmakelists_skeleton_file(unitGlobal.script_location, source_root, projects_list_file_rel)
v2c_convert_finished()
