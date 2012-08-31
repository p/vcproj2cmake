#!/usr/bin/ruby

require 'fileutils'
require 'find'
require 'pathname'

script_fqpn = File.expand_path $0
script_path = Pathname.new(script_fqpn).parent
source_root = Dir.pwd

def log_info(str)
  # We choose to not log an INFO: prefix (reduce log spew).
  $stdout.puts str
end

def log_error(str); $stderr.puts "ERROR: #{str}" end

def log_fatal(str); log_error "#{str}. Aborting!"; exit 1 end

def create_directory(dir)
  if File.exist?(dir)
    return true
  end
  if FileUtils.mkdir_p dir
    return true
  end
  return false
end

def do_delay(delay)
  log_info "Waiting #{delay} seconds..."
  sleep(delay)
end

log_info 'Welcome to the guided install of vcproj2cmake!'



# Not enough testing/development, thus allow users to bail out...
# (I wanted to commit my files now, but it's not finished)
# Those who feel daring enough might decide to disable this check.
user_abort_delay = 15
log_info "Unfortunately this script is not quite ready for public consumption yet!\nThus please press Ctrl-C within #{user_abort_delay} seconds to abort, otherwise experimental installation will continue"
do_delay(user_abort_delay)

cmake_bin='cmake'
ccmake_bin='ccmake'

log_info 'Verifying cmake binary availability.'
output = `#{cmake_bin} --version`
if not $?.success?
  log_fatal 'cmake binary not found - you probably need to install a CMake package'
end

log_info 'Creating build directory for guided installation.'
build_install_dir = "#{script_path}/build_install"
if not create_directory(build_install_dir)
  log_fatal "could not create build directory at #{build_install_dir}"
end

if not Dir.chdir(build_install_dir)
  log_fatal 'could not change into build directory for guided installation'
end

# I'm not sure whether it's a good idea to have Subversion fetching done
# as a build-time rule. This requires us to re-configure things multiple
# times (to provide the install target once all preconditions are
# fulfilled).
# The (possibly better) alternative would be to do SVN fetching at configure
# time.

# Hmm, we probably should also support the Qt-based GUI.
output = `#{ccmake_bin} --help`
if not $?.success?
  log_fatal 'could not run ccmake - perhaps it is not installed. On Debian-based Linux, installing the cmake-curses-gui package might help.'
end

log_info 'About to prepare the build tree (CMake configure run) which is required for installation of vcproj2cmake components. Please setup configuration as needed there, then proceed (do CMake Configure run multiple times, and finally press Generate).'
do_delay(10)
system "#{ccmake_bin} ../"
if not $?.success?
  log_fatal 'invocation of ccmake failed'
end

system "#{cmake_bin} ."
if not $?.success?
  log_error ''
  log_fatal \
    'a CMake configure run failed\n' \
    'Probably verification of the configuration data for installation of vcproj2cmake components failed.\n' \
    'You should re-run this installer and re-configure CMake variables to contain valid references.\n\n'
end

log_info ''
log_info 'Will now attempt to install vcproj2cmake components into the .vc[x]proj-based source tree you configured.'
log_info ''

# Figure out which CMAKE_MAKE_PROGRAM is configured (ninja? make?),
# then use it for install.

def grep_cmakecache_variable_value(cmakecache_location, cmake_var)
  var_value = nil
  File.open(cmakecache_location) { |cmakecache_file|
    cmakecache_file.grep(/#{cmake_var}:(STRING|.*PATH)=/).each { |line|
      var_value = line.chomp.split('=')[1]
    }
  }
  return var_value
end

build_cmd = 'make' # assume a suitable fallback
cmakecache_location = "#{build_install_dir}/CMakeCache.txt"

build_cmd = grep_cmakecache_variable_value(cmakecache_location, 'CMAKE_MAKE_PROGRAM')

log_info "Detected build command #{build_cmd}."

system "#{build_cmd} all"
if not $?.success?
  log_fatal 'execution of all target failed'
end

system "#{cmake_bin} ."
if not $?.success?
  log_error ''
  log_fatal 'second CMake configure run failed'
end

system "#{build_cmd} install"
if not $?.success?
  log_fatal 'installation of vcproj2cmake components into a .vc[x]proj source tree failed'
end

system "#{build_cmd} convert_source_root_recursive"
if not $?.success?
  log_fatal 'hmm'
end

# Now change into project dir, create build subdir, run ccmake -DCMAKE_BUILD_TYPE=Debug ../
# , try to build it.

SOURCE_ROOT_VAR = 'v2ci_vcproj_proj_source_root'
def get_proj_source_root(cmakecache_location)
  return grep_cmakecache_variable_value(cmakecache_location, SOURCE_ROOT_VAR)
end

proj_source_dir = get_proj_source_root(cmakecache_location)
if not proj_source_dir
  log_fatal "failed to figure out source dir of project (build dir is: #{build_install_dir})"
end

log_info "changing into source directory #{proj_source_dir} of converted project"
if not Dir.chdir(proj_source_dir)
  log_fatal "could not change into source directory #{proj_source_dir} of converted project"
end

proj_build_dir = "#{proj_source_dir}.build"
log_info "creating build directory #{proj_build_dir}"
if not create_directory(proj_build_dir)
  log_fatal "could not create project build dir #{proj_build_dir}"
end

log_info "changing into build directory #{proj_build_dir} of converted project"
if not Dir.chdir(proj_build_dir)
  log_fatal "could not change into build directory #{proj_build_dir} of converted project"
end

cmake_invocation_proj = "#{ccmake_bin} -DCMAKE_BUILD_TYPE=Debug #{proj_source_dir}"
log_info "Running #{cmake_invocation_proj} to configure the converted project"
do_delay(5)
system(cmake_invocation_proj)
if not $?.success?
  log_error 'cmake invocation for source tree of converted project failed - this may be due to a missing main CMakeLists.txt file there, or due to some build configuration error.'
  log_fatal "implementation not finished - please change into the project source directory at #{proj_source_dir} and create a proper infrastructure there (e.g. a main CMakeLists.txt containing add_subdirectory() commands etc.) to properly include the CMakeLists.txt files of the converted sub projects"
end

log_info "Successfully(?) created a build environment at #{proj_build_dir} for converted source project #{proj_source_dir}."
log_info "You can now change into #{proj_build_dir} and start building the project with your CMake configuration."
log_info ''

$stdout.puts 'INFO: done.'
$stdout.puts 'Given a successfully newly converted/configured build tree,'
$stdout.puts 'you may now attempt to run various build targets'
$stdout.puts '(see useful "make help" when on Makefile generator) within this tree'
$stdout.puts '(which references the files within your .vc[x]proj-based source tree).'
$stdout.puts ''
$stdout.puts 'If building fails due to various include files not found/missing,'
$stdout.puts 'then you should add find_package() commands to V2C hook scripts'
$stdout.puts 'and make sure that raw include directories'
$stdout.puts '(those originally specified in .vc[x]proj)'
$stdout.puts 'map to the corresponding xxx_INCLUDE_DIR variable'
$stdout.puts 'as figured out by find_package(), by adding this mapping'
$stdout.puts 'to include_mappings.txt.'
$stdout.puts 'Or perhaps it is simply a case of not having properly configured'
$stdout.puts 'a crucial environment variable (BOOSTROOT, QTDIR, ...)'
$stdout.puts 'that the original project happens to expect'
$stdout.puts 'to be properly supplied by the user for a correctly working build.'
$stdout.puts ''
$stdout.puts 'Also, it is probably a good idea to review the steps that this script executed in order to get a grasp of how to setup such a build.'
