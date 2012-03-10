# This file is part of the vcproj2cmake build converter (vcproj2cmake.sf.net)
#
# user-modifiable file containing common vcproj2cmake settings, included by all vcproj2cmake scripts.
# NOTE that in addition to this file a vcproj2cmake_settings.user.rb
# file (for local customization of the settings in this more
# global/default file) will be loaded if available.

# Script execution log level (0: no logging, 1: errors only, 2: +warnings, 3: +info, 4: +debug, 5: all).
$v2c_log_level = 3

# local config directory as created in every project which needs specific settings
# (possibly required in root project space only)
$v2c_config_dir_local = "./cmake/vcproj2cmake"

# directory where CMake modules reside (from CMAKE_SOURCE_DIR root).
# Filename case is not really standardized,
# thus you might want to tweak this setting.
$v2c_module_path_root = "cmake/Modules"

# directory where project-local modules reside.
$v2c_module_path_local = "./#{$v2c_module_path_root}"

# Whether to verify that files that are listed in a project are ok
# (e.g. they might not exist, perhaps due to filename having wrong case).
$v2c_validate_vcproj_ensure_files_ok = 1

# Whether to actively fail the conversion in case any errors have been
# encountered. Strongly recommended to active this,
# since generating an incorrect CMakeLists.txt
# will make a CMake configure run barf,
# at which point the previous CMake-generated build system is history
# and thus targets for automatic rebuild of CMakeLists.txt are gone, too,
# necessitating a painful manual re-execution
# of vcproj2cmake_recursive.rb plus arguments
# after having fixed all problematic .vcproj settings.
$v2c_validate_vcproj_abort_on_error = 1

# Configures amount of useful comments left in generated CMakeLists.txt
# files
# 0 == completely disabled (not recommended)
# 1 == useful bare minimum
# 2 == standard (default)
# 3 == verbose
# 4 == extra verbose
$v2c_generator_comments_level = 2

# Specifies the format of the timestamp which indicates the
# moment in time that an output file has been generated at.
# To be specified as Ruby Time.strftime() format.
# Disable it or provide empty string to skip addition of a timestamp variable.
# Note that giving an overly detailed format (such as appending %M%S)
# will have the side effect of a newly generated timestamp value changing
# each minute and second (i.e. the content of the output file is "different"),
# causing our generator to detect the content as changed
# and thus bogusly writing out the actually unchanged configuration file again.
$v2c_generator_timestamp_format = '%Y%m%d_%H'

# Initial number of spaces for indenting in the text output files
$v2c_generator_indent_initial_num_spaces = 0

# Number of spaces to increment by
$v2c_generator_indent_step = 2

# The CMakeLists.txt files we create originate from a tempfile,
# which always gets created with very restrictive access permissions (0600).
# Since there's usually not much of a reason not to grant read access
# of these build files to other people, we'll use a public 0644
# as the default value.
$v2c_generator_file_create_permissions = 0644

# Indicates that the project conversion run is supposed to be a one-time event
# rather than "on-going tracking of continued development on the side of the
# parsed project files".
# ENABLING NOT RECOMMENDED since it will disable automatic rebuilding
# - only for cases where you are sure that you intend to completely leave
# the originating platform behind # and subsequently maintain all build aspects
# on the side of the generated platform (CMake).
# This switch will disable elements such as:
# - the "auto-generated file" marker
# - all hooks for custom code (since the generated file will never
#   be re-generated, it can now reliably host any permanent modifications on its own)
# - the automatic rebuild of generated files which would happen
#   whenever there is an update to the originating project file
$v2c_generator_one_time_conversion_only = false

# Whether to parse and generate configuration info about precompiled headers.
# Currently disabled by default (not verified yet, and module file not checked in yet).
$v2c_target_precompiled_header_enable = false

# Whether we would like to have multi-threaded operation
# for project conversion (vcproj2cmake_recursive.rb).
# Not very useful since several Ruby implementations
# have "green threads" (cooperative threading rather than
# multi-core!), IOW it's _SLOWER_ than serialized operation!
# Currently still disabled by default (better have some more testing).
# Also, console output is likely to get intermingled (semi-readable).
# Should implement scoped output management if this turns out to be
# a problem.
$v2c_enable_threads = false
