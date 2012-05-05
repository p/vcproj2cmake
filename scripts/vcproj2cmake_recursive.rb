#!/usr/bin/ruby -w

require 'find'
require 'tempfile'
require 'pathname'

# HACK: have $script_dir as global variable currently
$script_dir = File.dirname(__FILE__)

def tweak_load_path
  script_dir_lookup = $script_dir.clone

  script_dir_lookup += '/.'
  $LOAD_PATH.unshift(script_dir_lookup) unless $LOAD_PATH.include?(script_dir_lookup)
  script_dir_lookup += '/lib'
  $LOAD_PATH.unshift(script_dir_lookup) unless $LOAD_PATH.include?(script_dir_lookup)

  #puts "LOAD_PATH: #{$LOAD_PATH.inspect}\n" # nice debugging
end

tweak_load_path()

require 'vcproj2cmake/v2c_core' # (currently) large amount of random "core" functionality

require 'vcproj2cmake/util_file' # V2C_Util_File.mkdir_p()

CMAKELISTS_AUTO_GENERATED_REGEX_OBJ = /#{V2C_TEXT_FILE_AUTO_GENERATED_MARKER}/
VCPROJ_IS_GENERATED_BY_CMAKE_REGEX_OBJ = %r{CMakeLists.txt}

################
#     MAIN     #
################

# FIXME: currently this code below is too unstructured / dirty
# (many parts open-coded rather than clean helpers).
# But for now, I just don't care ;)


script_fqpn = File.expand_path $0
script_path = Pathname.new(script_fqpn).parent
source_root = Dir.pwd

script_location = "#{script_path}/vcproj2cmake.rb"

if not File.exist?($v2c_config_dir_local)
  V2C_Util_File.mkdir_p $v2c_config_dir_local
end

time_cmake_root_folder = 0
arr_excl_proj_expr = Array.new()
time_cmake_root_folder = File.stat($v2c_config_dir_local).mtime.to_i
excluded_projects = "#{$v2c_config_dir_local}/project_exclude_list.txt"
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

class Thread_Work
  def initialize(str_proj_file_location, str_cmakelists_file_location)
    @str_proj_file_location = str_proj_file_location
    @str_cmakelists_file_location = str_cmakelists_file_location
  end
  attr_accessor :str_proj_file_location
  attr_accessor :str_cmakelists_file_location
end

arr_thread_work = Array.new

arr_project_subdirs = Array.new

# FIXME: should _split_ operation between _either_ scanning entire .vcproj hierarchy into a
# all_sub_projects.txt, _or_ converting all sub .vcproj as listed in an existing all_sub_projects.txt file.
# (provide suitable command line switches)
# Hmm, or perhaps port _everything_ back into vcproj2cmake.rb,
# providing --recursive together with --scan or --convert switches for all_sub_projects.txt generation or use.


# Pre-configure a directory exclusion pattern regex:
arr_excl_dir_expr_skip_recursive_static = [ '\.svn', '\.git' ] # TODO transform this into a config setting?

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

Find.find('./') do
  |f|
  # skip symlinks since they might be pointing _backwards_!
  next if FileTest.symlink?(f)
  next if not test(?d, f)

  # skip CMake build directories! (containing CMake-generated .vcproj files!)
  # FIXME: more precise checking: check file _content_ against CMake generation!
  is_excluded = false
  if f =~ /^build/i
    is_excluded = true
  else
    if not excl_regex_single.nil?
      #puts "MATCH: #{f} vs. #{excl_regex_single}"
      if f.match(excl_regex_single)
        is_excluded = true
      end
    end
  end
  #puts "excluded: #{is_excluded}"
  if is_excluded == true
    puts "EXCLUDED SINGLE #{f}!"
    next
  end

  if f.match(excl_regex_recursive)
    puts "EXCLUDED RECURSIVELY #{f}!"
    Find.prune() # throws exception to skip entire recursive directories block
  end

  # HACK: temporary helper to quickly switch between .vcproj/.vcxproj
  want_proj = 'vcproj'

  puts "processing #{f}!"
  dir_entries = Dir.entries(f)
  #puts "entries: #{dir_entries}"
  vcproj_files = dir_entries.grep(/\.#{want_proj}$/i)
  #puts vcproj_files

  # No project file type at all? Immediately skip directory.
  next if vcproj_files.nil?

  # in each directory, find the .vcproj file to use.
  # Prefer xxx_vc8.vcproj, but in cases of directories where this is
  # not available, use a non-_vc8 file.
  projfile = nil
  vcproj_files.each do |vcproj_file|
    if vcproj_file =~ /_vc8.#{want_proj}$/i
      # ok, we found a _vc8 version, quit searching since this is what we prefer
      projfile = vcproj_file
      break
    end
    if vcproj_file =~ /.#{want_proj}$/i
      projfile = vcproj_file
	# do NOT break here (another _vc8 file might come along!)
    end
  end
  #puts "projfile is #{projfile}"

  # No project file at all? Skip directory.
  next if projfile.nil?

  str_cmakelists_file = "#{f}/CMakeLists.txt"

  # Check whether the directory already contains a CMakeLists.txt,
  # and if so, whether it can be safely rewritten.
  # These checks arguably perhaps shouldn't be done in the recursive handler,
  # but directly in the main conversion handler instead. TODO?
  if (!dir_entries.grep(/^CMakeLists.txt$/i).empty?)
    #puts dir_entries
    #puts "CMakeLists.txt exists in #{f}, checking!"
    prior_file_was_generated_by_v2c = ''
    begin
      f_cmakelists = File.new(str_cmakelists_file, 'r')
      prior_file_was_generated_by_v2c = f_cmakelists.grep(CMAKELISTS_AUTO_GENERATED_REGEX_OBJ)
    ensure
      f_cmakelists.close
    end
    was_custom_native_file = prior_file_was_generated_by_v2c.empty?
    if was_custom_native_file
      # For zero-size files, the auto-generation marker check above is obviously
      # not delivering a useful result...
      if File.zero?(str_cmakelists_file)
        # zero-size files may have happened due to out-of-disk-space issues,
        # thus ensure overwriting in such cases.
        puts 'ZERO-SIZE FILE detected, overwriting!'
      else
        puts "existing #{str_cmakelists_file} is custom, \"native\" form --> skipping!"
        next
      end
    else
	# ok, it _is_ a CMakeLists.txt, but a temporary vcproj2cmake one
	# which we can overwrite.
      puts "existing #{str_cmakelists_file} is our own auto-generated file --> replacing!"
    end
  end

  # Now proceed with conversion of .vcproj file:
  str_proj_file = "#{f}/#{projfile}"

  # Detect .vcproj files actually generated by CMake generator itself:
  cmakelists_text = ''
  begin
    f_vcproj = File.new(str_proj_file, 'r')
    cmakelists_text = f_vcproj.grep(VCPROJ_IS_GENERATED_BY_CMAKE_REGEX_OBJ)
  ensure
    f_vcproj.close
  end
  if not cmakelists_text.empty?
    puts "Skipping CMake-generated MSVS file #{str_proj_file}"
    next
  end

  if projfile =~ /_vc8.#{want_proj}$/i
  else
    puts "Darn, no _vc8.vcproj in #{f}! Should have offered one..."
  end
  # verify age of .vcproj file... (NOT activated: experimental feature!)
  rebuild = 0
  if File.exist?(str_cmakelists_file)
    # is .vcproj newer (or equal: let's rebuild copies with flat timestamps!)
    # than CMakeLists.txt?
    # NOTE: if we need to add even more dependencies here, then it
    # might be a good idea to do this stuff properly and use a CMake-based re-build
    # infrastructure instead...
    # FIXME: doesn't really seem to work... yet?
    time_proj = File.stat(str_proj_file).mtime.to_i
    time_cmake_folder = 0
    config_dir_local = "#{f}/#{$v2c_config_dir_local}"
    if File.exist?(config_dir_local)
      time_cmake_folder = File.stat(config_dir_local).mtime.to_i
    end
    time_CMakeLists = File.stat(str_cmakelists_file).mtime.to_i
    #puts "TIME: CMakeLists #{time_CMakeLists} proj #{time_proj} cmake_folder #{time_cmake_folder} cmake_root_folder #{time_cmake_root_folder}"
    if time_proj > time_CMakeLists
      #puts "modified: project!"
      rebuild = 1
    elsif time_cmake_folder > time_CMakeLists
      #puts "modified: cmake/!"
      rebuild = 1
    elsif time_cmake_root_folder > time_CMakeLists
      #puts "modified: cmake/ root!"
      rebuild = 1
    end
  else
    # no CMakeLists.txt at all, definitely process this project
    rebuild = 2
  end
  if rebuild > 0
    #puts "REBUILD #{f}!! #{rebuild}"
  end
  #puts str_proj_file

  # the root directory is special: it might contain another project (it shouldn't!!),
  # thus we need to skip it if so (then include the root directory
  # project by placing a CMakeLists_native.txt there and have it include the
  # auto-generated CMakeLists.txt)
  arr_project_subdirs.push(f) unless f == './'

  # For recursive invocation we used to have _external spawning_
  # of a new vcproj2cmake.rb session, but we _really_ don't want to do that
  # since Ruby startup latency is extremely high
  # (3 seconds startup vs. 0.3 seconds payload compute time with our script!)

  # Collect the list of projects to convert, then call v2c_convert_project_outer() multi-threaded! (although threading is said to be VERY slow in Ruby - but still it should provide some sizeable benefit).
  thread_work = Thread_Work.new(str_proj_file, str_cmakelists_file)
  arr_thread_work.push(thread_work)

  #output.split("\n").each do |line|
  #  puts "[parent] output: #{line}"
  #end
  #puts
end

# Hrmm, many Ruby implementations have "green threads", i.e.
# implementing _cooperative_ (non-parallel) threading.
# Perhaps there's a flag to query whether a particular Ruby Thread
# implementation has cooperative or real (multi-core) threading.
# Otherwise we should probably just use Process.fork()
# (I hate all those dirty thread implementations anyway,
# real separate-process handling with clean IPC is a much better idea
# in several cases).
if ($v2c_enable_threads)
  puts 'Recursively converting projects, multi-threaded.'

  # "Ruby-Threads erzeugen"
  #    http://home.vr-web.de/juergen.katins/ruby/buch/tut_threads.html

  threads = []

  for thread_work in arr_thread_work
    threads << Thread.new(thread_work) { |myWork|
      v2c_convert_project_outer(script_location, myWork.str_proj_file_location, myWork.str_cmakelists_file_location, source_root)
    }
  end

  threads.each { |aThread| aThread.join }
else # non-threaded
  puts 'Recursively converting projects, NON-threaded.'
  arr_thread_work.each { |myWork|
    v2c_convert_project_outer(script_location, myWork.str_proj_file_location, myWork.str_cmakelists_file_location, source_root)
  }
end

def write_projects_list_file(output_file_fqpn, create_permissions, arr_project_subdirs)
  # write into temporary file, to avoid corrupting previous file due to syntax error abort, disk space or failure issues
  begin
    tmpfile = Tempfile.new('vcproj2cmake_recursive')
    projlistfile = File.open(tmpfile.path, 'w')

    arr_project_subdirs.each { |subdir|
      # FIXME: should be using the CMake syntax generator class for this add_subdirectory() stuff as well...
      if subdir.include? ' ' # quote strings containing spaces!!
        projlistfile.puts("add_subdirectory(\"#{subdir}\")")
      else
        projlistfile.puts("add_subdirectory(#{subdir})")
      end
    }

  ensure
    # Make sure to close it:
    projlistfile.close

    # make sure to close that one as well...
    tmpfile.close
  end

  util_permanentize_temp_file(tmpfile, output_file_fqpn, create_permissions)
end

# Finally, write out the file for the projects list (separate from any
# multi-threaded implementation).
write_projects_list_file("#{$v2c_config_dir_local}/all_sub_projects.txt", $v2c_generator_file_create_permissions, arr_project_subdirs)
