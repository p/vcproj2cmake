# This file is part of the vcproj2cmake build converter (vcproj2cmake.sf.net)
#

require 'tempfile'
require 'vcproj2cmake/util_file' # V2C_Util_File.cmp()

$VERBOSE=true

V2C_LOG_LEVEL_OFF = 0
V2C_LOG_LEVEL_FATAL = 1
V2C_LOG_LEVEL_ERROR = 2
V2C_LOG_LEVEL_WARN = 3
V2C_LOG_LEVEL_INFO = 4
V2C_LOG_LEVEL_DEBUG = 5
V2C_LOG_LEVEL_TRACE = 6

def load_configuration_file(str_file, str_descr, arr_descr_loaded)
  success = false
  begin
    load str_file
    arr_descr_loaded.push("#{str_descr} #{str_file}")
    success = true
  rescue LoadError
    # Ignore it (config file is optional!).
    # Need a dummy var to silence Excellent warning
    # (nope, unused dummy var will trigger Ruby warning -
    # use existing "success").
    success = true
  end
  return success
end

def load_configuration
  # FIXME: we should be offering instances of configuration classes
  # to be customized in the user settings files!
  # That way, rather than having the user possibly _create_ ad-hoc
  # incorrectly spelt global variables, we'll have a restricted set
  # of class members which the user may modify
  # --> the user will _know_ immediately in case
  # a now non-existent class member gets modified
  # (i.e. a config file update happened!).

  # load common settings
  settings_file_prefix = 'vcproj2cmake_settings'
  settings_file_extension = 'rb'
  arr_descr_loaded = Array.new
  settings_file_standard = "#{settings_file_prefix}.#{settings_file_extension}"
  load_configuration_file(settings_file_standard, 'standard settings file', arr_descr_loaded)
  settings_file_user = "#{settings_file_prefix}.user.#{settings_file_extension}"
  str_descr = 'user-specific customized settings file'
  str_msg_extra = nil
  if not load_configuration_file(settings_file_user, str_descr, arr_descr_loaded)
    str_msg_extra = "#{str_descr} #{settings_file_user} not available, skipped"
  end
  str_msg = "Read #{arr_descr_loaded.join(' and ')}"
  if not str_msg_extra.nil?
    str_msg += " (#{str_msg_extra})"
  end
  str_msg += '.'
  puts str_msg
end

load_configuration()

class V2C_Path_Config
  def initialize(master_project_source_dir)
    @source_root = master_project_source_dir
    @rel_config_dir_source_root = $v2c_config_dir_local
    @config_dir_source_root = "#{@source_root}/#{@rel_config_dir_source_root}"
    # Provide a special directory for temporary/generated content that's not
    # supposed to be added to SCM (entire content can be ignored easily,
    # by mentioning this directory in SCM config files such as .gitignore)
    temp_store_dir_name = "generated_temporary_content"
    @rel_config_dir_source_root_temp_store = "#{@rel_config_dir_source_root}/#{temp_store_dir_name}"
    @config_dir_source_root_temp_store = "#{@config_dir_source_root}/#{temp_store_dir_name}"
    if not File.exist?(@config_dir_source_root_temp_store)
      V2C_Util_File.mkdir_p @config_dir_source_root_temp_store
    end
  end
  def get_abs_source_root; @source_root end
  # Returns the location of the V2C config dir located below V2C's source root
  # (V2C_MASTER_PROJECT_SOURCE_DIR).
  def get_rel_config_dir_source_root(); @rel_config_dir_source_root end
  def get_abs_config_dir_source_root(); @config_dir_source_root end
  # Returns a suitable location for *temporary* storage purposes
  # (this content should not be committed to SCM).
  def get_rel_config_dir_source_root_temp_store(); @rel_config_dir_source_root_temp_store end
  def get_abs_config_dir_source_root_temp_store(); @config_dir_source_root_temp_store end
end

def v2c_get_path_config(master_project_source_dir)
  V2C_Path_Config.new(master_project_source_dir)
end

# TODO: make this a user-visible config setting soon
$v2c_generate_self_contained_file = 0

# At least currently, this is a custom plugin mechanism.
# It doesn't have anything to do with e.g.
# Ruby on Rails Plugins, which is described by
# "15 Rails mit Plug-ins erweitern"
#   http://openbook.galileocomputing.de/ruby_on_rails/ruby_on_rails_15_001.htm

$arr_plugin_parser = Array.new

class V2C_Core_Plugin_Info
  def initialize
    @version = 0 # plugin API version that this plugin supports
  end
  attr_accessor :version
end

class V2C_Core_Plugin_Info_Parser < V2C_Core_Plugin_Info
  def initialize
    super()
    @parser_name = nil
    @extension_name = nil
  end
  attr_accessor :parser_name
  attr_accessor :extension_name
end

def V2C_Core_Add_Plugin_Parser(plugin_parser)
  if 1 == plugin_parser.version
    $arr_plugin_parser.push(plugin_parser)
    puts "registered parser plugin #{plugin_parser.parser_name} (.#{plugin_parser.extension_name})"
    return true
  else
    puts "parser plugin #{plugin_parser.parser_name} indicates wrong version #{plugin_parser.version}"
    return false
  end
end

# Use specially named "v2c_plugins" dir to avoid any resemblance/clash
# with standard Ruby on Rails plugins mechanism.
v2c_plugin_dir = "#{$script_dir}/v2c_plugins"

PLUGIN_FILE_REGEX_OBJ = %r{v2c_(parser|generator)_.*\.rb$}
Find.find(v2c_plugin_dir) { |f_plugin|
  if PLUGIN_FILE_REGEX_OBJ.match(f_plugin)
    puts "loading plugin #{f_plugin}!"
    load f_plugin
  end
  # register project file extension name in plugin manager array, ...
}

# TODO: to be automatically filled in from parser plugins

plugin_parser_vs10 = V2C_Core_Plugin_Info_Parser.new

plugin_parser_vs10.version = 1
plugin_parser_vs10.parser_name = 'Visual Studio 10'
plugin_parser_vs10.extension_name = 'vcxproj'

V2C_Core_Add_Plugin_Parser(plugin_parser_vs10)

plugin_parser_vs7_vfproj = V2C_Core_Plugin_Info_Parser.new

plugin_parser_vs7_vfproj.version = 1
plugin_parser_vs7_vfproj.parser_name = 'Visual Studio 7+ (Fortran .vfproj)'
plugin_parser_vs7_vfproj.extension_name = 'vfproj'

V2C_Core_Add_Plugin_Parser(plugin_parser_vs7_vfproj)


#*******************************************************************************************************

# since the .vcproj multi-configuration environment has some settings
# that can be specified per-configuration (target type [lib/exe], include directories)
# but where CMake unfortunately does _NOT_ offer a configuration-specific equivalent,
# we need to fall back to using the globally-scoped CMake commands (include_directories() etc.).
# But at least let's optionally allow the user to precisely specify which configuration
# (empty [first config], "Debug", "Release", ...) he wants to have
# these settings taken from.
$config_multi_authoritative = ''

FILENAME_MAP_DEF = "#{$v2c_config_dir_local}/define_mappings.txt"
FILENAME_MAP_DEP = "#{$v2c_config_dir_local}/dependency_mappings.txt"
FILENAME_MAP_LIB_DIRS = "#{$v2c_config_dir_local}/lib_dirs_mappings.txt"
FILENAME_MAP_LIB_DIRS_DEP = "#{$v2c_config_dir_local}/lib_dirs_dep_mappings.txt"


# Additionally enable Ruby's $DEBUG in case we want at least debug level.
if $v2c_log_level >= V2C_LOG_LEVEL_DEBUG
  $DEBUG=true
end

def log_debug(str)
  return if $v2c_log_level < V2C_LOG_LEVEL_DEBUG
  puts str
end

def log_info(str)
  # We choose to not log an INFO: prefix (reduce log spew).
  puts str
end

def log_warn(str); puts "WARNING: #{str}" if $v2c_log_level >= V2C_LOG_LEVEL_WARN end

def log_todo(str); puts "TODO: #{str}" if $v2c_log_level >= V2C_LOG_LEVEL_ERROR end

def log_error(str); $stderr.puts "ERROR: #{str}" if $v2c_log_level >= V2C_LOG_LEVEL_ERROR end

# FIXME: should probably replace most log_fatal()
# with exceptions since in many cases
# one would want to have _partial_ aborts of processing only.
# Soft error handling via exceptions would apply to errors due to problematic input -
# but errors due to bugs in our code should cause immediate abort.
def log_fatal(str); log_error "#{str}. Aborting!" if $v2c_log_level > V2C_LOG_LEVEL_OFF; exit 1 end

def log_implementation_bug(str); log_fatal(str) end

class Logger
  def initialize(class_name, log_descriptor)
    @class_name = class_name
    # FIXME: log_descriptor not obeyed yet!
  end

  # Ensures proper copy&paste'ability of some log items (e.g.
  # filenames).
  # E.g. a dot directly following a filename would disrupt proper
  # filename-only selection.
  def escape_item(file); "\"#{file}\"" end

  def error(str); log_error(formatter(str)) end
  def fixme(str); log_error(formatter("FIXME: #{str}")) end
  def warn(str); log_warn(formatter(str)) end
  def info(str); log_info(formatter(str)) end
  def debug(str); log_debug(formatter(str)) end

  # "Ruby Exceptions", http://rubylearning.com/satishtalim/ruby_exceptions.html
  # NOTE: user side should probably re-raise() the exception in most cases...
  def unhandled_exception(e, action)
    log_error "unhandled exception occurred during #{action}! #{e.message}, #{e.backtrace.inspect}"
  end
  def unhandled_functionality(str_description); error "unhandled functionality: #{str_description}" end

  private
  # I don't know WTH @class_name is not initialized. Probably an init order issue or whatever the heck is happening here. Oh well...
  #def formatter(str) "#{@class_name}: #{str}" end
  def formatter(str) str end
end

module Logging
  # This is the magical bit that gets mixed into your classes
  def logger
    Logging.logger
  end

  # Global, memoized, lazy initialized instance of a logger
  def self.logger
    @logger ||= Logger.new(self.class.name, STDOUT)
  end

  def todo(str)
    log_todo str
  end
end

# FIXME: currently our classes _derive_ from V2C_LoggerBase in most cases,
# however it's common practice to have log channel provided as a class member
# or even a global variable. Should thus rework things to have a class member each
# (best supplied as ctor param, to have flexible output channel configuration
# by external elements).
# See http://stackoverflow.com/questions/917566/ruby-share-logger-instance-among-module-classes

module Logging_Redirector
  # This is the magical bit that gets mixed into your classes
  def logger
    # HACK: logger method currently disabled:
    #Logging.logger
    logger_member
  end

  # Global, memoized, lazy initialized instance of a logger
  def self.logger
    @logger ||= Logger.new(self.class.name, STDOUT)
  end

  def logger_member
    self # HACK - we're currently the base class of certain classes, but ultimately the logger target should be a ctor param (i.e., member) of all classes). This trick allows us to do a gradual migration :)
  end

  def todo(str)
    log_todo str
  end
end

class V2C_LoggerBase < Logger
  include Logging_Redirector

  def initialize
    super(self.class.name, STDOUT)
  end
end

# Change \ to /, and remove leading ./
def normalize_path(p)
  felems = p.tr('\\', '/').split('/')
  # DON'T eradicate single '.' !!
  felems.shift if felems[0] == '.' and felems.size >= 2
  File.join(felems)
end

def escape_char(in_string, esc_char)
  #puts "in_string #{in_string}"
  in_string.gsub!(/#{esc_char}/, "\\#{esc_char}")
  #puts "in_string quoted #{in_string}"
end

BACKSLASH_REGEX_OBJ = %r{\\}
def escape_backslash(in_string)
  # "Escaping a Backslash In Ruby's Gsub": "The reason for this is that
  # the backslash is special in the gsub method. To correctly output a
  # backslash, 4 backslashes are needed.". Oerks - oh well, do it.
  # hrmm, seems we need some more even...
  # (or could we use single quotes (''') for that? Too lazy to retry...)
  in_string.gsub!(BACKSLASH_REGEX_OBJ, '\\\\\\\\')
end

# This method's output is quite a bit better
# than a simple #{hash.inspect}.
def log_hash(hash)
  log_debug '** log_hash **'
  hash.each { |key, value|
    log_debug "#{key} --> #{value}"
  }
end

# Helper for Ruby 1.8 unsorted hash vs. Ruby 1.9 sorted hash.
# We _definitely_ want output files to be generated from sorted hashes,
# since they _are required_ to end up with reproducible, identical content -
# if content happened to change from conversion run to the next one,
# then a huge penalty of a _full rebuild_ of an entire build tree would ensue!

# See syntax at http://www.ruby-mine.de/2006/12/4/gef-hrliche-sicherheitsl-cken-in-cgi-rb
if (RUBY_VERSION < '1.9') # FIXME exact version where it got introduced?
  def hash_ensure_sorted(hash_out)
    # NOTE: if this method bombs with a weird "undefined method <=> for nil:NilClass" sort error,
    # then this quite certainly means that one of the hash entries
    # is a (quite useless) nil mapping.
    # --> fix the invoking code to not add such an entry.
    #log_hash(hash_out)
    hash_out = hash_out.sort
  end
  # Hrmm, hash_ensure_sorted() does not work - introduce
  # hash_ensure_sorted_each() instead which returns either Array or
  # sorted Hash, for use of .each().
  def hash_ensure_sorted_each(hash_out)
    return hash_out.sort # returns an _Array_
  end
else
  def hash_ensure_sorted(hash_out); end # DUMMY (>= 1.9 hash is sorted by default)
  def hash_ensure_sorted_each(hash_out)
    return hash_out.sort # returns a _Hash_
  end
end

COMMENT_LINE_REGEX_OBJ = %r{^\s*#}
def read_mappings(filename_mappings, mappings)
  # line format is: "tag:PLATFORM1:PLATFORM2=tag_replacement2:PLATFORM3=tag_replacement3"
  if File.exists?(filename_mappings)
    #Hash[*File.read(filename_mappings).scan(/^(.*)=(.*)$/).flatten]
    File.open(filename_mappings, 'r').each do |line|
      next if COMMENT_LINE_REGEX_OBJ.match(line)
      b, c = line.chomp.split(':')
      if not b.nil?
        mappings[b] = c
      end
    end
  else
    log_debug "NOTE: #{filename_mappings} NOT AVAILABLE"
  end
  #log_debug mappings['kernel32']
  #log_debug mappings['mytest']
end

# Read mappings of both current project and source root.
# Ordering should definitely be _first_ current project,
# _then_ global settings (a local project may have specific
# settings which should _override_ the global defaults).
def read_mappings_combined(filename_mappings, mappings, master_project_dir)
  read_mappings(filename_mappings, mappings)
  return if not master_project_dir
  # read common mappings (in source root) to be used by all sub projects
  # FIXME: in case of global recursive operation, this data part is _constant_,
  # thus we should avoid reading it anew for each project!
  read_mappings("#{master_project_dir}/#{filename_mappings}", mappings)
  #log_hash(mappings)
  #hash_ensure_sorted(mappings)
end

def push_platform_defn(platform_defs, platform, defn_value)
  #log_debug "adding #{defn_value} on platform #{platform}"
  if platform_defs[platform].nil?; platform_defs[platform] = Array.new end
  platform_defs[platform].push(defn_value)
end

# IMPORTANT NOTE: the generator/target/parser class hierarchy and _naming_
# is supposed to be eerily similar to the one used by CMake, i.e.
# basically our parser class hierarchy is the inverse
# of what CMake implements for its generators.
# Dito for naming of individual methods...
#
# Global generator: generates/manages parts which are not project-local/target-related (i.e., manages things related to the _entire solution_ configuration)
# local generator: has a Makefile member (which contains a list of targets),
#   then generates project files by iterating over the targets via a newly generated target generator each.
# target generator: generates targets. This is the one creating/producing the output file stream. Not provided by all generators (VS10 yes, VS7 no).

class V2C_ParserError < StandardError
end

class V2C_Info_Condition
  def initialize(str_condition = nil)
    @str_condition = str_condition
    @build_type = nil # WARNING: it may contain spaces!
    @platform = nil
  end
  attr_reader :str_condition
  # FIXME: Q&D interim function - I don't think such raw handling should be in this data container...
  BUILD_TYPE_SCAN_QD_REGEX_OBJ = %r{^'\$\(Configuration\)\|\$\(Platform\)'=='(.*)\|(.*)'$}
  def get_build_platform
    update_build_type_platform
    return @platform
  end
  def get_build_type
    update_build_type_platform
    return @build_type
  end
  def set_build_type(build_type); @build_type = build_type end
  def set_platform(platform); @platform = platform end

  # Returns true if we are at least as strict as the other condition,
  # i.e. indicates whether the other condition is fulfilled within our realms.
  # For the theory behind this, see e.g. Truth Table
  # ( http://en.wikipedia.org/wiki/Truth_table ) and
  # http://en.wikipedia.org/wiki/Logical_conditional and http://en.wikipedia.org/wiki/Entailment
  def entails(condition_other)
    build_type = get_build_type()
    build_platform = get_build_platform()
    log_debug "condition: build_type #{build_type} platform #{build_platform}"
    if not condition_other.nil?
      log_debug "condition_other: build_type #{condition_other.get_build_type()} platform #{condition_other.get_build_platform()}"
      build_type_other = condition_other.get_build_type()
      if not build_type_other.nil?
        return false if build_type_other != build_type
      end
      platform_other = condition_other.get_build_platform()
      if not platform_other.nil?
        return false if platform_other != build_platform
      end
    end
    log_debug "ENTAILS!"
    return true
  end

  private

  # Indicates whether our attributes are maximally specific.
  def build_config_fully_qualified
    not @build_type.nil? and not @platform.nil?
  end
  def update_build_type_platform
    return if build_config_fully_qualified()

    # For now, prefer raw build_type (VS7) only in case no complex condition string is available.
    if not str_condition.nil?
      log_debug "str_condition: #{@str_condition}"
      build_type = nil
      platform = nil
      @str_condition.scan(BUILD_TYPE_SCAN_QD_REGEX_OBJ) {
        build_type = $1
        platform = $2
      }
      if build_type.nil? or build_type.empty?
        # TODO!!
        log_fatal "could not parse build type from condition #{str_condition}"
      end
      @build_type = build_type
      @platform = platform
    end
  end
end

# @brief Mostly used to manage the condition element...
class V2C_Info_Elem_Base
  def initialize
    @condition = nil # V2C_Info_Condition
  end
  attr_accessor :condition
end

module V2C_Include_Dir_Defines
  SYSTEM = 1
  BEFORE = 2
  AFTER = 4
end

class V2C_Info_Include_Dir < V2C_Info_Elem_Base
  def initialize
    super()
    @dir = String.new
    @flags = 0 # V2C_Include_Dir_Defines::SYSTEM etc.
  end
  attr_accessor :dir
  attr_accessor :flags
  def is_system; return (@flags & V2C_Include_Dir_Defines::SYSTEM) > 0 end
  def is_before; return (@flags & V2C_Include_Dir_Defines::BEFORE) > 0 end
  def is_after; return (@flags & V2C_Include_Dir_Defines::AFTER) > 0 end
end

class V2C_Tool_Base_Info
  def initialize(tool_variant_specific_info)
    @name = nil # Hmm, do we need this member? (do we really want to know the tool name??)
    @suppress_startup_banner_enable = false # used by at least VS10 Compiler _and_ Linker, thus it's member of the common base class.
    @show_progress_enable = false

    # _base_ class member to provide a mechanism to intelligently translate tool (compiler, linker) configurations
    # as specified by the original build environment files (e.g. compiler flags, warnings, ...)
    # into values as used by _other_ candidates (e.g. MSVC vs. gcc etc.).
    @arr_tool_variant_specific_info = Array.new
    if not tool_variant_specific_info.nil?
      tool_variant_specific_info.original = true
      @arr_tool_variant_specific_info.push(tool_variant_specific_info)
    end
  end
  attr_accessor :name
  attr_accessor :suppress_startup_banner_enable
  attr_accessor :show_progress_enable
  attr_accessor :arr_tool_variant_specific_info
end

class V2C_Tool_Define_Base_Info < V2C_Tool_Base_Info
  def initialize(tool_variant_specific_info)
    super(tool_variant_specific_info)
    @hash_defines = Hash.new
  end
  attr_accessor :hash_defines
end

class V2C_Tool_Specific_Info_Base
  def initialize
    @original = false # bool: true == gathered from parsed project, false == converted from other original tool-specific entries
  end
  attr_accessor :original
end

class V2C_Tool_Compiler_Specific_Info_Base < V2C_Tool_Specific_Info_Base
  def initialize(compiler_name)
    super()
    @compiler_name = compiler_name
    @arr_flags = Array.new
    @arr_disable_warnings = Array.new
  end
  attr_accessor :compiler_name
  attr_accessor :arr_flags
  attr_accessor :arr_disable_warnings
end

class V2C_Tool_Compiler_Specific_Info_MSVC_Base < V2C_Tool_Compiler_Specific_Info_Base
  def initialize(compiler_name)
    super(compiler_name)
    @warning_level = 3 # numeric value (for /W4 etc.); TODO: translate into MSVC /W... flag
  end
  attr_accessor :warning_level
end

class V2C_Tool_Compiler_Specific_Info_MSVC7 < V2C_Tool_Compiler_Specific_Info_MSVC_Base
  def initialize
    super('MSVC7')
  end
end

class V2C_Tool_Compiler_Specific_Info_MSVC10 < V2C_Tool_Compiler_Specific_Info_MSVC_Base
  def initialize
    super('MSVC10')
  end
end

class V2C_Precompiled_Header_Info
  def initialize
    # @use_mode: known VS10 content is "NotUsing" / "Create" / "Use"
    # (corresponding VS8 values are 0 / 1 / 2)
    # NOTE VS7 (2003) had 3 instead of 2 (i.e. changed to 2 after migration!)
    @use_mode = 0
    @header_source_name = '' # the header (.h) file to precompile
    @header_binary_name = '' # the precompiled header binary to create or use
  end
  attr_accessor :use_mode
  attr_accessor :header_source_name
  attr_accessor :header_binary_name
end

module V2C_Compiler_Defines
  BASIC_RUNTIME_CHECKS_DEFAULT = 0
  BASIC_RUNTIME_CHECKS_STACKFRAME = 1
  BASIC_RUNTIME_CHECKS_UNINITIALIZED_LOCAL_USAGE = 2
  BASIC_RUNTIME_CHECKS_FAST = 3
  COMPILE_AS_DEFAULT = 0
  COMPILE_AS_C = 1
  COMPILE_AS_CXX = 2
  CRT_MULTITHREADED = 1
  CRT_MULTITHREADED_DEBUG = 2
  CRT_MULTITHREADED_DLL = 3
  CRT_MULTITHREADED_DEBUG_DLL = 4
  DEBUG_INFO_FORMAT_DISABLED = 0
  DEBUG_INFO_FORMAT_OLDSTYLE = 1
  DEBUG_INFO_FORMAT_NONE = 2
  DEBUG_INFO_FORMAT_PDB = 3
  DEBUG_INFO_FORMAT_EDITANDCONTINUE = 4
  INLINE_FUNCTION_EXPANSION_DEFAULT = -1
  INLINE_FUNCTION_EXPANSION_DISABLED = 0
  INLINE_FUNCTION_EXPANSION_ONLYEXPLICITINLINE = 1
  INLINE_FUNCTION_EXPANSION_ANYSUITABLE = 2
end

class V2C_Tool_Compiler_Info < V2C_Tool_Define_Base_Info
  include V2C_Compiler_Defines
  def initialize(tool_variant_specific_info = nil)
    super(tool_variant_specific_info)
    @arr_info_include_dirs = Array.new
    @asm_listing_location = nil
    @basic_runtime_checks = BASIC_RUNTIME_CHECKS_DEFAULT
    @compile_as = COMPILE_AS_DEFAULT
    @debug_information_format = DEBUG_INFO_FORMAT_DISABLED
    @rtti = true
    @precompiled_header_info = nil
    @detect_64bit_porting_problems_enable = true # TODO: translate into MSVC /Wp64 flag; Enabled by default is preferable, right?
    @exception_handling = 1 # we do want it enabled, right? (and as Sync?)
    @inline_function_expansion = INLINE_FUNCTION_EXPANSION_DEFAULT
    @minimal_rebuild_enable = false
    @multi_core_compilation_enable = false # TODO: translate into MSVC10 /MP flag...; Disabled by default is preferable (some builds might not have clean target dependencies...)
    @pdb_filename = nil
    @warnings_are_errors_enable = false # TODO: translate into MSVC /WX flag
    @show_includes_enable = false # Whether to show the filenames of included header files. TODO: translate into MSVC /showIncludes flag
    @function_level_linking_enable = false
    @intrinsic_functions_enable = false
    @runtime_library_variant = V2C_VSToolCompilerDefines::VS_DEFAULT_SETTING_RUNTIMELIBRARY
    @static_code_analysis_enable = false # TODO: translate into MSVC7/10 /analyze flag
    @string_pooling_enable = false
    @treat_wchar_t_as_builtin_type_enable = false
    @optimization = 0 # currently supporting these values: 0 == Non Debug, 1 == Min Size, 2 == Max Speed, 3 == Max Optimization
  end
  attr_accessor :arr_info_include_dirs
  attr_accessor :asm_listing_location
  attr_accessor :basic_runtime_checks
  attr_accessor :compile_as
  attr_accessor :debug_information_format
  attr_accessor :rtti
  attr_accessor :precompiled_header_info
  attr_accessor :detect_64bit_porting_problems_enable
  attr_accessor :exception_handling
  attr_accessor :inline_function_expansion
  attr_accessor :minimal_rebuild_enable
  attr_accessor :multi_core_compilation_enable
  attr_accessor :pdb_filename
  attr_accessor :warnings_are_errors_enable
  attr_accessor :show_includes_enable
  attr_accessor :function_level_linking_enable
  attr_accessor :intrinsic_functions_enable
  attr_accessor :runtime_library_variant
  attr_accessor :static_code_analysis_enable
  attr_accessor :string_pooling_enable
  attr_accessor :treat_wchar_t_as_builtin_type_enable
  attr_accessor :optimization

  def get_include_dirs(flag_system, flag_before)
    #arr_includes = Array.new
    #@arr_info_include_dirs.each { |inc_dir_info|
    #  # TODO: evaluate flag_system and flag_before
    #  # and collect only those dirs that match these settings
    #  # (equivalent to CMake include_directories() SYSTEM / BEFORE).
    #  arr_includes.push(inc_dir_info.dir)
    #}
    arr_includes = @arr_info_include_dirs.collect { |inc_dir_info| inc_dir_info.dir }
    return arr_includes
  end
end

class V2C_Tool_Linker_Specific_Info < V2C_Tool_Specific_Info_Base
  def initialize(linker_name)
    super()
    @linker_name = linker_name
    @arr_flags = Array.new
  end
  attr_accessor :linker_name
  attr_accessor :arr_flags
end

class V2C_Tool_Linker_Specific_Info_MSVC < V2C_Tool_Linker_Specific_Info
  def initialize(linker_name)
    super(linker_name)
  end
end

class V2C_Tool_Linker_Specific_Info_MSVC7 < V2C_Tool_Linker_Specific_Info_MSVC
  def initialize()
    super('MSVC7')
  end
end

class V2C_Tool_Linker_Specific_Info_MSVC10 < V2C_Tool_Linker_Specific_Info_MSVC
  def initialize()
    super('MSVC10')
  end
end

class V2C_Dependency_Info
  def initialize(dependency)
    @dependency = dependency # string (filename path or target name)
    @is_target_name = false
  end
  attr_accessor :dependency
  attr_accessor :is_target_name
end

module V2C_Linker_Defines
  BASE_ADDRESS_NOT_SET = 0xffffffff
  COMDAT_FOLDING_DEFAULT = 0 # VS7: optFoldingDefault
  COMDAT_FOLDING_NOFOLDING = 1 # VS7: optNoFolding
  COMDAT_FOLDING_FOLDING = 2 # VS7: optFolding
  # FIXME: there are some other subsystems such as Native (NT driver) and POSIX
  SUBSYSTEM_NOT_SET = 0
  SUBSYSTEM_CONSOLE = 1 # VS10 "Console"
  SUBSYSTEM_WINDOWS = 2 # VS10 "Windows"
  SUBSYSTEM_NATIVE = 3 # VS10 "Native"
  SUBSYSTEM_EFI_APPLICATION = 4 # VS10 "EFIApplication"
  SUBSYSTEM_EFI_BOOT_SERVICE = 5 # VS10 "EFIBootService"
  SUBSYSTEM_EFI_ROM = 6 # VS10 "EFIROM"
  SUBSYSTEM_EFI_RUNTIME = 7 # VS10 "EFIRuntime"
  SUBSYSTEM_POSIX = 8 # VS10 "Posix"
  SUBSYSTEM_WINDOWS_CE = 9 # VS10 "WindowsCE"
  MACHINE_NOT_SET = 0 # VS10: "Not Set", VS7: 0
  MACHINE_X86 = 1 # x86 / i386; VS7: 1
  MACHINE_X64 = 17 # VS7: 17
end

class V2C_Tool_Linker_Info < V2C_Tool_Base_Info
  include V2C_Linker_Defines
  def initialize(tool_variant_specific_info = nil)
    super(tool_variant_specific_info)
    @arr_dependencies = Array.new # V2C_Dependency_Info (we need an attribute which indicates whether this dependency is a library _file_ or a target name, since we should be reliably able to decide whether we can add "debug"/"optimized" keywords to CMake variables or target_link_library() parms)
    @base_address = BASE_ADDRESS_NOT_SET
    @comdat_folding = COMDAT_FOLDING_DEFAULT
    @data_execution_prevention_enable = true # Suitable default?
    @arr_delay_load_dlls = Array.new
    @generate_debug_information_enable = false
    @generate_map_file_enable = false
    @arr_ignore_specific_default_libraries = Array.new
    @link_incremental = 0 # 1 means NO, thus 2 probably means YES?
    @map_file_name = nil
    @module_definition_file = nil
    @optimize_references_enable = false
    @pdb_file = nil
    @per_user_redirection_enable = false
    @randomized_base_address_enable = false
    @register_output_enable = false
    @strip_private_symbols_file = nil
    @subsystem = SUBSYSTEM_CONSOLE
    @target_machine = MACHINE_NOT_SET
    @uac_manifest_enable = false # EnableUAC (MSVC linker /MANIFESTUAC option); for now we'll assume that it's NOT MSVC-specific, i.e. other linkers sometimes possibly are able to do UAC manifests, too.
    @arr_lib_dirs = Array.new
  end
  attr_accessor :arr_dependencies
  attr_accessor :base_address
  attr_accessor :comdat_folding
  attr_accessor :data_execution_prevention_enable
  attr_accessor :arr_delay_load_dlls
  attr_accessor :generate_debug_information_enable
  attr_accessor :generate_map_file_enable
  attr_accessor :arr_ignore_specific_default_libraries
  attr_accessor :link_incremental
  attr_accessor :map_file_name
  attr_accessor :module_definition_file
  attr_accessor :optimize_references_enable
  attr_accessor :pdb_file
  attr_accessor :per_user_redirection_enable
  attr_accessor :randomized_base_address_enable
  attr_accessor :register_output_enable
  attr_accessor :strip_private_symbols_file
  attr_accessor :subsystem
  attr_accessor :target_machine
  attr_accessor :uac_manifest_enable
  attr_accessor :arr_lib_dirs
  attr_accessor :arr_tool_variant_specific_info
end

class V2C_Tool_MIDL_Specific_Info < V2C_Tool_Specific_Info_Base
  def initialize(midl_name)
    super()
    @midl_name = midl_name
    @arr_flags = Array.new
  end
  attr_accessor :midl_name
  attr_accessor :arr_flags
end

class V2C_Tool_MIDL_Specific_Info_MSVC7 < V2C_Tool_MIDL_Specific_Info
  def initialize()
    super('MSVC7')
  end
end

class V2C_Tool_MIDL_Specific_Info_MSVC10 < V2C_Tool_MIDL_Specific_Info
  def initialize()
    super('MSVC10')
  end
end

class V2C_Tool_MIDL_Info < V2C_Tool_Define_Base_Info
  def initialize(tool_variant_specific_info = nil)
    super(tool_variant_specific_info)
    @header_file_name = nil
    @iface_id_file_name = nil
    @mktyplib_compatible = false
    @type_library_name = nil
  end
  attr_accessor :header_file_name
  attr_accessor :iface_id_file_name
  attr_accessor :mktyplib_compatible
  attr_accessor :type_library_name
end

module V2C_TargetConfig_Defines
  CFG_TYPE_INVALID = -1 # detect improper entries
  CFG_TYPE_UNKNOWN = 0 # VS7/10 typeUnknown (utility), 0
  CFG_TYPE_APP = 1 # VS7/10 typeApplication (.exe), 1
  CFG_TYPE_DLL = 2 # VS7/10 typeDynamicLibrary (.dll), 2
  CFG_TYPE_STATIC_LIB = 4 # VS7/10 typeStaticLibrary, 4
  CFG_TYPE_GENERIC = 10 # VS7/10 typeGeneric (Makefile?), 10
  CHARSET_SBCS = 0
  CHARSET_UNICODE = 1
  CHARSET_MBCS = 2
  MFC_FALSE = 0
  MFC_STATIC = 1
  MFC_DYNAMIC = 2
end

# FIXME: all related parts should be renamed into something like
# Framework_Config or Toolkit_Config or some such,
# depending on which members this class ends up containing.
class V2C_Target_Config_Build_Info < V2C_Info_Elem_Base
  include V2C_TargetConfig_Defines
  def initialize
    @cfg_type = CFG_TYPE_INVALID

    # 0 == no MFC
    # 1 == static MFC
    # 2 == shared MFC
    @use_of_mfc = 0 # V2C_TargetConfig_Defines::MFC_*
    @use_of_atl = 0
    @charset = 0 # Simply uses VS7 values for now. V2C_TargetConfig_Defines::CHARSET_*
    @whole_program_optimization = 0 # Simply uses VS7 values for now. TODO: should use our own enum definition or so.; it seems for CMake the related setting is target/directory property INTERPROCEDURAL_OPTIMIZATION_<CONFIG> (described by Wikipedia "Interprocedural optimization")
    @use_debug_libs = false
    @atl_minimizes_crt_lib_usage_enable = false
  end
  attr_accessor :cfg_type
  attr_accessor :use_of_mfc
  attr_accessor :use_of_atl
  attr_accessor :charset
  attr_accessor :whole_program_optimization
  attr_accessor :use_debug_libs
  attr_accessor :atl_minimizes_crt_lib_usage_enable
end

class V2C_Tools_Info < V2C_Info_Elem_Base
  def initialize
    @arr_compiler_info = Array.new
    @arr_linker_info = Array.new
    @arr_midl_info = Array.new
  end
  attr_accessor :arr_compiler_info
  attr_accessor :arr_linker_info
  attr_accessor :arr_midl_info
end

# Common base class of both file config and project config.
class V2C_Config_Base_Info < V2C_Info_Elem_Base
  def initialize
    @tools = V2C_Tools_Info.new
  end
  attr_accessor :tools
end

# Carries project-global configuration data.
class V2C_Project_Config_Info < V2C_Config_Base_Info
  def initialize
    super()
    @output_dir = nil
    @intermediate_dir = nil
  end
  attr_accessor :output_dir
  attr_accessor :intermediate_dir
end

# Carries per-file-specific configuration data
# (which overrides the project globals).
class V2C_File_Config_Info < V2C_Config_Base_Info
  def initialize
    super()
    @excluded_from_build = false
  end
  attr_accessor :excluded_from_build
end

# Carries Source Control Management (SCM) setup.
class V2C_SCC_Info
  def initialize
    @project_name = nil
    @local_path = nil
    @provider = nil
    @aux_path = nil
  end

  attr_accessor :project_name
  attr_accessor :local_path
  attr_accessor :provider
  attr_accessor :aux_path
end

class V2C_BuildConfigurationEntry
  def initialize
    @description = nil
    @platform = nil
    @build_type = nil
  end
  attr_accessor :description
  attr_accessor :platform
  attr_accessor :build_type
end

class V2C_Build_Platform_Configs
  def initialize
    @arr_entries = Array.new # V2C_BuildConfigurationEntry
    @arr_registered_platforms = Array.new # String
  end
  # Register a platform for subsequent addition.
  # Used to keep a close eye on the platforms a project
  # pretends to support.
  def register_platform(platform_name)
    add_elem_unique(@arr_registered_platforms, platform_name)
  end
  # Add a platform data struct
  # for one of the registered platforms.
  def add(config_entry)
    if not @arr_registered_platforms.include?(config_entry.platform)
      raise V2C_ParserError, "project file failed to supply a registered platform (#{@arr_registered_platforms.inspect}) before adding #{config_entry.inspect}"
    end
    @arr_entries.push(config_entry)
  end
  def get_platforms()
    # Cannot use block-based Array.uniq() (Ruby 1.9.x only).
    arr_platforms = Array.new
    @arr_entries.each { |entry|
      platform_name = entry.platform
      if not arr_platforms.include?(platform_name)
        arr_platforms.push(platform_name)
      end
    }
    return arr_platforms
  end
  def get_build_types(platform_name)
    arr_build_types = Array.new
    @arr_entries.each { |entry|
      next if not entry.platform == platform_name
      build_type = entry.build_type
      add_elem_unique(arr_build_types, build_type)
    }
    return arr_build_types
  end
  private
  def add_elem_unique(arr, elem)
    if not arr.include?(elem)
      arr.push(elem)
    end
  end
end

class V2C_Filters_Container
  def initialize
    @arr_filters = Array.new # the array which contains V2C_Info_Filter elements. Now supported by VS10 parser. FIXME: rework VS7 parser to also create a linear array of filters!
    # In addition to the filters Array, we also need a filters Hash
    # for fast lookup when intending to insert a new file item of the project.
    # There's now a new ordered hash which might preserve the ordering
    # as guaranteed by an Array, but we cannot use it since it's too new (Ruby 1.9!).
    @hash_filters = Hash.new
  end
  def append(filter_info)
    # Hmm, no need to check the hash for existing filter
    # since overriding is ok, right?
    @hash_filters[filter_info.name] = filter_info
    @arr_filters.push(filter_info)
  end
end

module V2C_File_List_Types
  TYPE_NONE = 0
  TYPE_COMPILES = 1
  TYPE_INCLUDES = 2
  TYPE_RESOURCES = 3
  TYPE_MIDL = 4
end

class V2C_File_List_Info
  include V2C_File_List_Types
  def initialize(name, type = TYPE_NONE)
    @name = name # VS10: One of None, ClCompile, ClInclude, ResourceCompile; VS7: the name of the filter that contains these files
    @type = type
    @arr_files = Array.new # V2C_Info_File elements
  end
  attr_accessor :name
  attr_accessor :type
  attr_reader :arr_files
  def append_file(file_info); @arr_files.push(file_info) end
  def get_list_type_name()
    list_types =
     [ 'unknown', # VS10: None
       'sources', # VS10: ClCompile
       'headers', # VS10: ClInclude
       'resources', # VS10: ResourceCompile
       #'midl' # VS10: Midl # MIDL is _not_ supposed to be here, I think (MIDL-related files are sorted within ClCompile/ClInclude categories...)
     ]
    type = @type <= TYPE_RESOURCES ? @type : TYPE_NONE
    return list_types[type]
  end
  def get_generated_files
    arr_generated = @arr_files.collect { |file_info|
      #puts "#{file_info.path_relative} #{file_info.is_generated}"
      next if not file_info.is_generated
      file_info.path_relative
    }
    return arr_generated
  end
end


class V2C_File_Lists_Container
  def initialize
    # FIXME: the array/hash combo should perhaps be merged
    # with identical functionality in V2C_Filters_Container (new class?).
    @arr_file_lists = Array.new # V2C_File_List_Info:s, array (serves to maintain ordering)
    @hash_file_lists = Hash.new # dito, but hashed! (serves to maintain fast lookup)
  end
  attr_reader :arr_file_lists
  def lookup_from_name(file_list_name)
    return @hash_file_lists[file_list_name]
  end
  def append(file_list)
    name = file_list.name
    file_list_existing = lookup_from_name(name)
    file_list_append = file_list_existing
    if file_list_append.nil?
      register(file_list)
      file_list_append = file_list
    end
  end

  private
  # registers a file list (does NOT do collision checks!)
  def register(file_list)
    @arr_file_lists.push(file_list)
    @hash_file_lists[file_list.name] = file_list
  end
end

# Well, in fact in Visual Studio, "target" and "project"
# seem to be pretty much synonymous...
# FIXME: we should still do better separation between these two...
# Formerly called V2C_Target.
#
# Default values of its members should be useful defaults
# *irrespective* of defaults defined by specific build environments (e.g. VS7, VS10).
# In most cases, this means choosing "error values" initially,
# for the project validator to be able to yell about it
# in case a certain parser type did then NOT handle
# assigning useful values to them.
class V2C_Project_Info < V2C_Info_Elem_Base # We need this base to always consistently get a condition element - but the VS10-side project info actually most likely does not have/use it!
  def initialize
    @type = nil # project type
    # Interesting discussion about VS ProjectType:
    # "C vs C++ or any C varient"
    #   http://hardforum.com/archive/index.php/t-1574698.html

    # VS10: in case the main project file is lacking a ProjectName element,
    # the project will adopt the _exact name part_ of the filename,
    # thus enforce this ctor taking a project name to use as a default if no ProjectName element is available:
    @name = nil

    # the original environment (build environment / IDE)
    # which defined the project (MSVS7, MSVS10 - Visual Studio, etc.).
    # _Short_ name - may NOT contain whitespace.
    # Perhaps we should also be supplying a long name, too? ('Microsoft Visual Studio 7')
    @orig_environment_shortname = nil
    @arr_p_original_project_files = nil # (optional) a list of native project files that this project info has been parsed from
    @creator = nil # VS7 "ProjectCreator" setting
    @guid = nil
    @root_namespace = nil
    @version = nil

    # .vcproj Keyword attribute ("Win32Proj", "MFCProj", "ATLProj", "MakeFileProj", "Qt4VSv1.0").
    # TODO: should perhaps do Keyword-specific post-processing at generator
    # (to enable Qt integration, etc.):
    @vs_keyword = nil
    @scc_info = V2C_SCC_Info.new
    @build_platform_configs = V2C_Build_Platform_Configs.new # VS10 only: manages settings such as e.g. Configuration "Release", Platform "Win32", strings "Release|Win32", ...
    @arr_target_config_info = Array.new # V2C_Target_Config_Build_Info
    @arr_config_info = Array.new # V2C_Project_Config_Info
    @file_lists = V2C_File_Lists_Container.new
    @filters = V2C_Filters_Container.new
    @main_files = nil # FIXME get rid of this VS7 crap, rework file list/filters handling there!
    # semi-HACK: we need this variable, since we need to be able
    # to tell whether we're able to build a target
    # (i.e. whether we have any build units i.e.
    # implementation files / non-header files),
    # otherwise we should not add a target since CMake will
    # complain with "Cannot determine link language for target "xxx"".
    # Well, for such cases, in CMake we now fixed the generator
    # to be able to generate "project(SomeProj NONE)",
    # thus it should be ok now (and then add custom build commands/targets
    # _other_ than source-file-based executable targets).
    @have_build_units = false
  end

  attr_accessor :type
  attr_accessor :name
  attr_accessor :orig_environment_shortname
  attr_accessor :arr_p_original_project_files 
  attr_accessor :creator
  attr_accessor :guid
  attr_accessor :root_namespace
  attr_accessor :version
  attr_accessor :vs_keyword
  attr_accessor :scc_info
  attr_accessor :build_platform_configs
  attr_accessor :arr_config_info
  attr_accessor :arr_target_config_info
  attr_accessor :file_lists
  attr_accessor :filters
  attr_accessor :main_files
  attr_accessor :have_build_units
end

class V2C_CMakeProjectLanguageDetector < V2C_LoggerBase
  def initialize(project_info)
    @project_info = project_info
    @arr_languages = Array.new
  end
  attr_accessor :arr_languages
  def detect
    # ok, let's try some initial Q&D handling...
    # Perhaps one should have a language enum in the project info
    # (with a "string-type" setting and a string member -
    # in case of custom languages...).
    if true == @project_info.have_build_units
      if not @project_info.type.nil?
        case @project_info.type
        when 'Visual C++'
          # FIXME: how to configure C vs. CXX?
          # Even a C-only project I have is registered as 'Visual C++'.
          # I guess one is supposed to make this setting depend
          # on availability of .c/.cpp file extensions...
          # Hmm, and for .vcxproj, the language is perhaps encoded in the
          # <Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />
          # line only (i.e. the .props file).
          # Or is it this line?:
          # <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
          #
          # .vcproj can have FileConfiguration element with VCCLCompilerTool
          # CompileAs attribute to indicate specific language of a file.
          @arr_languages.push('C', 'CXX')
        else
          logger.fixme("unknown project type #{@project_info.type}, cannot determine programming language!")
        end
      end
      if not @project_info.creator.nil?
        if @project_info.creator.include?('Fortran')
          @arr_languages.push('Fortran')
        end
      end
      # For further language string possibilities, see also
      # CMake cmGlobalXCodeGenerator.cxx GetSourcecodeValueFromFileExtension().
      # Known values so far:
      # ASM C CXX Fortran Java RC
      # There seem to be *NO* ObjectiveC specifics here...
      # (simply implicitly compiler-detected via file extension?)
      if @arr_languages.empty?
        logger.error 'Could not figure out any pre-set programming language types (FIXME?) - will let auto-detection do its thing...'
        # We'll explicitly keep the array _empty_ (rather than specifying 'NONE'),
        # to give it another chance via CMake's language auto-detection mechanism.
      end
    else
      # This *can* be problematic - if our list fails to contain other yet-unknown language file extensions, then we'd need CMake-side auto-detection,
      # which is disabled when explicitly specifying NONE.
      # OK, this is important enough - we'll better NEVER specify NONE,
      # since our language setup currently is way too weak to be pretending
      # that we know what we're doing...
      logger.info 'project seems to have no build units. Still keeping CMake-side auto-detection active anyway.'
      #logger.info 'project seems to have no build units --> language set to NONE'
      #@arr_languages.push('NONE')
    end
    return @arr_languages
  end
end

# See "Format of a .vcproj File" http://msdn.microsoft.com/en-us/library/2208a1f2%28v=vs.71%29.aspx

VS7_PROP_VAR_SCAN_REGEX_OBJ = %r{\$\(([[:alnum:]_]+)\)}
VS7_PROP_VAR_MATCH_REGEX_OBJ = %r{\$\([[:alnum:]_]+\)}

class V2C_Info_Filter
  def initialize
    @name = nil
    @arr_scfilter = nil # "cpp;c;cc;cxx;..."
    @val_scmfiles = true # VS7: SourceControlFiles
    @guid = nil
    # While these type flags are being directly derived from magic guid values on VS7/VS10
    # and thus could be considered redundant in these cases,
    # we'll keep them separate since this implementation is supposed to support
    # parsers other than VSx, too.
    @parse_files = true # whether this filter should be parsed (touched) by IntelliSense (or related mechanisms) or not. Probably VS10-only property. Default value true, obviously.
  end
  attr_accessor :name
  attr_accessor :arr_scfilter
  attr_accessor :val_scmfiles
  attr_accessor :guid
end

Files_str = Struct.new(:filter_info, :arr_sub_filters, :arr_file_infos)

def is_known_environment_variable_convention(config_var, config_var_type_descr)
  # Side note: need to use String.replace() to properly export the output param's new value.
  is_wellknown = false
  case config_var
  when 'BOOSTROOT'
    config_var_type_descr.replace "well-known Boost installation's root dir environment variable"
    is_wellknown = true
  # Hrmm... SRCROOT seems to be used to indicate the main source root,
  # thus perhaps it should actually be replaced
  # by CMAKE_SOURCE_DIR or V2C_MASTER_PROJECT_SOURCE_DIR.
  # One thing is for certain though: we should actually export our own
  # replacement string from this function, too...
  when 'SRCROOT'
    config_var_type_descr.replace "well-known Apple environment variable"
    is_wellknown = true
  when 'DSTROOT'
    config_var_type_descr.replace "well-known Apple environment variable"
    is_wellknown = true
  when 'QTDIR'
    config_var_type_descr.replace "well-known Qt environment variable"
    is_wellknown = true
  else
    is_wellknown = false
  end
  return is_wellknown
end

# See also
# "How to: Use Environment Variables in a Build"
#   http://msdn.microsoft.com/en-us/library/ms171459.aspx
# "Macros for Build Commands and Properties"
#   http://msdn.microsoft.com/en-us/library/c02as0cs%28v=vs.71%29.aspx
# To examine real-life values of such MSVS configuration/environment variables,
# open a Visual Studio project's additional library directories dialog,
# then press its "macros" button for a nice list.
# Well, the terminus technicus for such custom $(ZZZZ) variables
# appears to be "User Macros" (at least in VS10), thus we should
# probably rename all handling here to reflect that proper name.
def vs7_create_config_variable_translation(str, arr_config_var_handling)
  # http://langref.org/all-languages/pattern-matching/searching/loop-through-a-string-matching-a-regex-and-performing-an-action-for-each-match
  str_scan_copy = str.dup # create a deep copy of string, to avoid "`scan': string modified (RuntimeError)"
  str_scan_copy.scan(VS7_PROP_VAR_SCAN_REGEX_OBJ) {
    config_var = $1
    config_var_type_descr = "MSVS configuration variable"
    # MSVS Property / Environment variables are documented to be case-insensitive,
    # thus implement insensitive match:
    config_var_upcase = config_var.upcase
    config_var_replacement = ''
    #TODO_OPTIMIZE: could replace this huge case switch
    # with a hash lookup on a result struct,
    # at least in cases where a hard-coded (i.e., non-flexible)
    # result handling is sufficient.
    case config_var_upcase
    # Hmm, $(Configuration) / $(ConfigurationName) seem to be
    # very similar but not fully, and it's not obvious what the difference is.
    # See http://msdn.microsoft.com/en-us/library/community/history/c02as0cs.aspx?id=3
    # (or better locate the original "$(Configuration) vs $(ConfigurationName)"
    # discussion page content since - ONCE AGAIN! Like with CodePlex, TFS Web etc. -
    # Microsoft is unable to provide an even barely suitable interface </rant>)
    #
    # Thus both should map to the special ${CMAKE_CFG_INTDIR} mechanism.
    when 'CONFIGURATION', 'CONFIGURATIONNAME'
      config_var_replacement = '${CMAKE_CFG_INTDIR}'
    when 'PLATFORMNAME'
      config_var_emulation_code = <<EOF
  if(NOT v2c_VS_PlatformName)
    if(CMAKE_CL_64)
      set(v2c_VS_PlatformName "x64")
    else(CMAKE_CL_64)
      if(WIN32)
        set(v2c_VS_PlatformName "Win32")
      endif(WIN32)
    endif(CMAKE_CL_64)
  endif(NOT v2c_VS_PlatformName)
EOF
      arr_config_var_handling.push(config_var_emulation_code)
      config_var_replacement = '${v2c_VS_PlatformName}'
      # InputName is said to be same as ProjectName in case input is the project.
    when 'INPUTNAME', 'PROJECTNAME'
      config_var_replacement = '${PROJECT_NAME}'
      # See ProjectPath reasoning below.
    when 'INPUTFILENAME', 'PROJECTFILENAME'
      # config_var_replacement = '${PROJECT_NAME}.vcproj'
      config_var_replacement = "${v2c_VS_#{config_var}}"
    when 'INTDIR'
      config_var_replacement = '${CMAKE_CFG_INTDIR}'
    when 'OUTDIR'
      # FIXME: should extend code to do executable/library/... checks
      # and assign CMAKE_LIBRARY_OUTPUT_DIRECTORY / CMAKE_RUNTIME_OUTPUT_DIRECTORY
      # depending on this.
      config_var_emulation_code = <<EOF
  set(v2c_CS_OutDir "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
EOF
      config_var_replacement = '${v2c_VS_OutDir}'
    when 'PROJECTDIR'
      config_var_replacement = '${PROJECT_SOURCE_DIR}'
    when 'PROJECTPATH'
      # ProjectPath emulation probably doesn't make much sense,
      # since it's a direct path to the MSVS-specific .vcproj file
      # (redirecting to CMakeLists.txt file likely isn't correct/useful).
      config_var_replacement = '${v2c_VS_ProjectPath}'
    when 'SOLUTIONDIR'
      # We used to replace SolutionDir with CMAKE_SOURCE_DIR,
      # but since one global CMake build repository might possibly even
      # end up containing multiple solution-converted V2C environments,
      # specifying V2C_MASTER_PROJECT_SOURCE_DIR is much more suitable/precise
      # (BTW, this variable can of course end up with different values -
      # depending on which of the possibly *multiple* solution sub dir hierarchies
      # it's being defined by).
      config_var_replacement = '${V2C_MASTER_PROJECT_SOURCE_DIR}'
    when 'TARGETNAME'
      # NOTE: $(TargetName) is available in both VS7/VS10,
      # however it changed its content (see
      # "Visual Studio 2010 - $(TargetName) macro" http://social.msdn.microsoft.com/Forums/en/vcprerelease/thread/3c03e730-6a0e-4ee4-a0d6-6a5c3ce4343c )
      # Might want to have a switch depending on whether input was
      # .vcproj or .vcxproj.
      config_var_replacement = '${PROJECT_NAME}'
    when 'TARGETPATH'
      config_var_emulation_code = ''
      arr_config_var_handling.push(config_var_emulation_code)
      config_var_replacement = '${v2c_VS_TargetPath}'
    else
      # FIXME: for unknown variables, we need to provide CMake code which derives the
      # value from the environment ($ENV{VAR}), since AFAIR these MSVS Config Variables will
      # get defined via environment variable, via a certain ordering (project setting overrides
      # env var, or some such).
      # TODO: In fact we should probably provide support for a property_var_mappings.txt file -
      # a variable that's relevant here would e.g. be QTDIR (an entry in that file should map
      # it to QT_INCLUDE_DIR or some such, for ready perusal by a find_package(Qt4) done by a hook script).
      # WARNING: note that _all_ existing variable syntax elements need to be sanitized into
      # CMake-compatible syntax, otherwise they'll end up verbatim in generated build files,
      # which may confuse build systems (make doesn't care, but Ninja goes kerB00M).
      is_env_var = false
      if is_known_environment_variable_convention(config_var, config_var_type_descr)
        is_env_var = true
      else
        log_warn "Unknown/user-custom config variable name #{config_var} encountered in line '#{str}' --> TODO?"
        config_var_type_descr = "unknown configuration variable"
        #str.gsub!(/\$\(#{config_var}\)/, "${v2c_VS_#{config_var}}")
        # For now, at least better directly reroute from environment variables as well:
        is_env_var = true
      end
      if true == is_env_var
        config_var_replacement = "$ENV{#{config_var}}"
      end
    end
    if config_var_replacement != ''
      log_info "Replacing $(#{config_var}) [#{config_var_type_descr}] by #{config_var_replacement}."
      str.gsub!(/\$\(#{config_var}\)/, config_var_replacement)
    end
  }

  #log_info "str is now #{str}, was #{str_scan_copy}"
  return str
end

class V2C_ParserBase < V2C_LoggerBase
  # Hmm, we might want to keep @info_elem in this class,
  # to be able to reference it for logging.
  def initialize(info_elem_out)
    @info_elem = info_elem_out
  end
  attr_accessor :info_elem

  def log_call; logger.error 'CALLED' end
  def log_found(found, label); logger.debug "FOUND: #{found} #{label}" end
  def parser_error(str_description, critical)
    do_raise = false
    if true == critical
      # TODO: should check a user-side config setting on whether to actually abort.
      do_raise = true
    end
    if true == do_raise
      raise V2C_ParserError, str_description
    else
      logger.error(str_description)
    end
  end
  def parser_error_logic(str_description); parser_error("logic: #{str_description}", false) end
  def parser_error_syntax(str_description); parser_error("syntax: #{str_description}", false) end
  def parser_error_todo(str_description); parser_error("todo: #{str_description}", false) end
  def error_unknown_case_value(description, val)
    parser_error("unknown/unsupported/corrupt #{description} case value! (#{val})", true)
  end
end

# XML support as required by VS7+/VS10 parsers:
require 'rexml/document'

class V2C_XmlParserBase < V2C_ParserBase
  FOUND_FALSE = 0
  FOUND_TRUE = 1
  FOUND_SKIP = 2

  def unknown_attribute(key, value); unknown_something_key_value('attribute', key, value) end
  def unknown_element_key(name); unknown_something('element', name) end
  def unknown_element(key, value); unknown_something_key_value('element', key, value) end
  def unknown_element_text(name); unknown_something('element text', name) end
  def unknown_setting(name); unknown_something('VS7/10 setting', name) end
  def unknown_value(name); unknown_something('value', name) end
  def skipped_attribute_warn(elem_name)
    logger.todo "#{self.class.name}: unhandled less important XML attribute (#{elem_name})!"
  end
  def skipped_element_warn(elem_name)
    logger.todo "#{self.class.name}: unhandled less important XML element (#{elem_name})!"
  end

  # @brief Descriptively named helper, to save a ton of useless comments :) ("be optimistic :)")
  def be_optimistic; FOUND_TRUE end

  def parse_attributes
    @elem_xml.attributes.each_attribute { |attr_xml|
      logger.debug "ATTR: #{attr_xml.name}"
      if not call_parse_attribute(attr_xml)
        if not call_parse_setting(attr_xml.name, attr_xml.value)
          unknown_attribute(attr_xml.name, attr_xml.value)
        end
      end
    }
  end
  def parse_elements
    @elem_xml.elements.each { |subelem_xml|
      logger.debug "ELEM: #{subelem_xml.name}"
      if not call_parse_element(subelem_xml)
        logger.debug "call_parse_element #{subelem_xml.name} failed"
        if not call_parse_setting(subelem_xml.name, subelem_xml.text)
          unknown_element(subelem_xml.name, subelem_xml.text)
        end
      end
    }
  end
  def call_parse_attribute(attr_xml)
    @called_base_parse_attribute = false
    success = false
    found = parse_attribute(attr_xml.name, attr_xml.value)
    case found
    when FOUND_TRUE
      success = true
    when FOUND_FALSE
      if not @called_base_parse_attribute
        announce_missing_base_call('parse_attribute')
      end
    when FOUND_SKIP
      skipped_attribute_warn(attr_xml.name)
      success = true
    else
      error_unknown_case_value('call_parse_attribute', found)
    end
    return success
  end
  def call_parse_element(subelem_xml)
    @called_base_parse_element = false
    success = false
    found = parse_element(subelem_xml)
    case found
    when FOUND_TRUE
      success = true
    when FOUND_FALSE
      if not @called_base_parse_element
        announce_missing_base_call('parse_element')
      end
    when FOUND_SKIP
      skipped_element_warn(subelem_xml.name)
      success = true
    else
      error_unknown_case_value(found)
    end
    return success
  end
  def call_parse_setting(setting_key, setting_value)
    @called_base_parse_setting = false
    success = false
    begin
      found = parse_setting(setting_key, setting_value)
      case found
      when FOUND_TRUE
        success = true
      when FOUND_FALSE
        if not @called_base_parse_setting
          announce_missing_base_call('parse_setting')
        end
      when FOUND_SKIP
        skipped_element_warn(setting_key)
        success = true
      else
        error_unknown_case_value(found)
      end
    rescue ArgumentError => e
      # Ruby's ArgumentError, unfortunately, may happen for BOTH syntax errors in arguments
      # to certain Ruby functions (integer parsing)
      # AND for function argument count errors in Ruby methods.
      # I.e. for both implementation-time AND run-time issues.
      # And then of course telling things apart properly is impossible.
      # This looks like a collossal design issue. "Ruby, bad doggie, no bone!"
      # Oh well, seems it's possible to check .message for the specific error string.
      if e.message.start_with?('invalid value for Integer')
        parser_error("encountered ArgumentError #{e.message} - probably integer parsing of #{setting_key} --> #{setting_value} failed", true)
      else
        raise
      end
    end
    return success
  end

  # @brief the virtual method for parsing an _entire_
  # recursive element structure.
  def parse_element(subelem_xml)
    @called_base_parse_element = true
    found = FOUND_FALSE # this base method will almost never "find" anything...
    return found
  end

  # @brief parses various attributes of an XML element.
  def parse_attribute(setting_key, setting_value)
    @called_base_parse_attribute = true
    found = FOUND_FALSE # this base method will almost never "find" anything...
    return found
  end

  # @brief Parses "settings", which are _either_ XML attributes (in VS7)
  # _or_ XML element simple name/text pairs (in VS10).
  # This method is intended for _both_ since VS7 <-> VS10 have identical
  # content for certain attributes <-> elements.
  def parse_setting(setting_key, setting_value)
    @called_base_parse_setting = true
    found = FOUND_FALSE # this base method will almost never "find" anything...
    return found
  end
  def parse_post_hook
    @called_base_parse_post_hook = true
  end
  def announce_missing_base_call(str_method)
    parser_error_logic("one of its classes forgot to service the #{str_method} base handler!")
  end
  def verify_calls
    missing_call = nil
    if not @called_base_parse_element
      missing_call = 'parse_element'
    else
      if not @called_base_parse_attribute
        missing_call = 'parse_attribute'
      else
        if not @called_base_parse_post_hook
        missing_call = 'parse_post_hook'
        end
      end
    end
    if not missing_call.nil?
      # Should not forget to call super, unless not wanted,
      # in which case at least set the bool flag to not fail this check
    end
  end
  def unknown_something(something_name, name)
    logger.todo "#{self.class.name}: unknown/incorrect XML #{something_name} (#{name})!"
  end
  def unknown_something_key_value(something_name, key, value)
    logger.todo "#{self.class.name}: unknown/incorrect XML #{something_name} (#{key}: #{value})!"
  end
end

class V2C_VSXmlParserBase < V2C_XmlParserBase
  # FIXME: very rough handling - what to do with those VS10 %(XXX) variables?
  # (terminus technicus appears to be: "item metadata macro")
  # Well, one idea would be to append entries (include directories, dependencies etc.)
  # to individual list vars that are being scoped within a
  # CMake parent directory chain. But these lists should be implementation details
  # hidden behind v2c_xxx(_target _build_type _entries) funcs, of course.
  # Known %(YYY) variable names are:
  # - Filename (e.g. written by CMake VS10 generator)
  # See also old VS7 $(Inherit) / $(NoInherit)
  # "<PropertyGroup Label="UserMacros" />" might be related, too.
  # For details, see
  #   http://stackoverflow.com/questions/8626333/what-is-additionaldependencies-macro
  #   http://stackoverflow.com/questions/3058111/how-do-i-set-environment-variables-in-visual-studio-2010
  #   http://connect.microsoft.com/VisualStudio/feedback/details/606484/property-sheets-upgraded
  #   http://blogs.msdn.com/b/vcblog/archive/2010/02/16/project-settings-changes-with-vs2010.aspx
  VS10_ITEM_METADATA_MACRO_MATCH_REGEX_OBJ = %r{%([^\s]*)}

  # Hmm, \n at least appears in VS10 (DisableSpecificWarnings element), but in VS7 as well?
  # WS_VALUE is for entries containing (and preserving!) whitespace (no split on whitespace!).
  VS_VALUE_SEPARATOR_REGEX_OBJ    = %r{[;,\s]} # (\s char set includes \n)
  VS_WS_VALUE_SEPARATOR_REGEX_OBJ = %r{[;,\n]}
  VS_SCC_ATTR_REGEX_OBJ = %r{^Scc}
  def initialize(elem_xml, info_elem_out)
    super(info_elem_out)
    @elem_xml = elem_xml
    @called_base_parse_element = false
    @called_base_parse_attribute = false
    @called_base_parse_setting = false
    @called_base_parse_post_hook = false
    @arr_config_var_dummy = Array.new
  end
  # THE MAIN PARSER ENTRY POINT.
  # Will invoke all methods of derived parser classes, whenever available.
  def parse
    logger.debug('parse')
    # Do strict traversal over _all_ elements, parse what's supported by us,
    # and yell loudly for any element which we don't know about!
    parse_attributes
    parse_elements
    parse_post_hook
    verify_calls
    return FOUND_TRUE # FIXME don't assume success - add some missing checks...
  end
  def get_boolean_value(str_value)
    parse_boolean_property_value(str_value)
  end
  def skip_vs10_percent_sign_var(str_var)
    # shortcut :)
    return false if not str_var.include?('%')
  
    return false if not VS10_ITEM_METADATA_MACRO_MATCH_REGEX_OBJ.match(str_var)
    logger.fixme("skipping unhandled VS10 variable (#{str_var})")
    return true
  end
  def get_filesystem_location(path)
    # TODO: rather ad-hoc handling of VS7 vars, should get improved eventually.
    path_translated = vs7_create_config_variable_translation(path, @arr_config_var_dummy)

    # TODO: should think of a way to do central verification
    # of existence of the file system paths found here near this helper.
    path_cooked = normalize_path(path_translated).strip
    return path_cooked.empty? ? nil : path_cooked
  end
  def split_values_list(str_value)
    arr_str = str_value.split(VS_VALUE_SEPARATOR_REGEX_OBJ)
    #arr_str.each { |str| logger.debug "SPLIT #{str}" }
    return arr_str
  end
  def split_values_list_preserve_ws(str_value)
    arr_str = str_value.split(VS_WS_VALUE_SEPARATOR_REGEX_OBJ)
    #arr_str.each { |str| logger.debug "SPLIT #{str}" }
    return arr_str
  end
  def array_discard_empty(arr_values); arr_values.delete_if { |elem| elem.empty? } end
  def split_values_list_discard_empty(str_value)
    arr_values = split_values_list(str_value)
    #logger.debug "arr_values #{arr_values.class.name}"
    return array_discard_empty(arr_values)
  end
  def split_values_list_preserve_ws_discard_empty(str_value)
    arr_values = split_values_list_preserve_ws(str_value)
    #logger.debug "arr_values #{arr_values.class.name}"
    return array_discard_empty(arr_values)
  end

  def parse_integer(setting_value)
    # Integer(x) (rather than .to_i) may throw an ArgumentError,
    # which we'll cleanly handle externally
    # (parsing failed --> no value assigned --> default value kept).
    return Integer(setting_value)
  end
  def string_to_index(arr_settings, str_setting, default_val)
    val = default_val
    n = arr_settings.index(str_setting)
    if not n.nil?
      val = n
    else
      unknown_value(str_setting)
    end
    return val
  end

  private

  def parse_boolean_text(str_value)
    bool_out = false
    success = true # be optimistic :)
    if not str_value.nil?
      case str_value.downcase
      when 'true'
        bool_out = true
      when 'false'
        bool_out = false
      else
        # Seems empty (whitespace-only) string is VS equivalent to false, right?
        # http://stackoverflow.com/a/1634814/1541578
        str_value_cooked = str_value.gsub(/\s+/, "")
        if str_value_cooked.empty?
          bool_out = false
          success = true
        else
	  # Unknown syntax (caller should probably log an error).
          success = false
        end
      end
    end
    [success, bool_out]
  end
end

class V2C_VSProjectFileXmlParserBase < V2C_VSXmlParserBase
  def get_arr_projects_out; @info_elem end
end

module V2C_VS7Syntax
  # In VS7, a boolean property appears to be representable
  # by "0", "1" values as well. FIXME: perhaps we're being imprecise here:
  # we should make sure to implement precise handling for specific VS7/VS10 element/attribute types.
  def parse_boolean_property_value(str_value)
    success, value = parse_boolean_text(str_value)
    if true != success
      value = parse_integer(str_value)
    end
    return value
  end
end

class V2C_VS7ParserBase < V2C_VSXmlParserBase
  include V2C_VS7Syntax
end

class V2C_VSProjectParserBase < V2C_VSXmlParserBase
  def initialize(elem_xml, info_elem_out)
    super(elem_xml, info_elem_out)
    set_vs_specific_default_values(get_project())
  end
  private

  def get_project; @info_elem end

  # TODO: perhaps this "default values" initializer
  # should be spread throughout all parser sub classes.
  # But since they're instantiated on-demand
  # that's currently not possible in several cases.
  def set_vs_specific_default_values(project_info)
     # nothing to do yet.
  end
end

class V2C_VS7ProjectParserBase < V2C_VSProjectParserBase
  include V2C_VS7Syntax
end

module V2C_VSToolDefines
  TEXT_ADDITIONALOPTIONS = 'AdditionalOptions'
  TEXT_SHOWPROGRESS = 'ShowProgress' # Houston... differing VS7/10 elements don't fit into our class hierarchy all too well...
  VS_DEFAULT_SETTING_SHOWPROGRESS = false # VS10 default: "not set"
  TEXT_SUPPRESSSTARTUPBANNER = 'SuppressStartupBanner'
end

class V2C_VSToolParserBase < V2C_VSXmlParserBase
  VS_ADDOPT_VALUE_SEPARATOR_REGEX_OBJ = %r{[;\s]}
  private

  include V2C_VSToolDefines
  def get_tool_info; @info_elem end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    tool_info = get_tool_info()
    case setting_key
    when TEXT_SUPPRESSSTARTUPBANNER
      tool_info.suppress_startup_banner_enable = get_boolean_value(setting_value)
    else
      found = super
    end
    return found
  end
  def parse_additional_options(arr_flags, attr_options)
    # Oh well, we might eventually want to provide a full-scale
    # translation of various compiler switches to their
    # counterparts on compilers of various platforms, but for
    # now, let's simply directly pass them on to the compiler when on
    # Win32 platform.

    # TODO: add translation table for specific compiler flag settings such as MinimalRebuild:
    # simply make reverse use of existing translation table in CMake source.
    # FIXME: can we use the full set of VS_VALUE_SEPARATOR_REGEX_OBJ
    # for AdditionalOptions content, too?
    arr_flags = attr_options.split(VS_ADDOPT_VALUE_SEPARATOR_REGEX_OBJ).collect { |opt|
      next if skip_vs10_percent_sign_var(opt)
      opt
    }
  end
  def parse_fs_item_list(attr_fs_items, arr_fs_items)
    return if attr_fs_items.empty?
    split_values_list_preserve_ws_discard_empty(attr_fs_items).each { |elem|
      next if skip_vs10_percent_sign_var(elem)
      elem_fs = get_filesystem_location(elem)
      next if elem_fs.nil?
      #logger.info "fs item is '#{elem_fs}'"
      arr_fs_items.push(elem_fs)
    }
  end
end

module V2C_VSToolDefineDefines
  TEXT_PREPROCESSORDEFINITIONS = 'PreprocessorDefinitions'
end

class V2C_VSToolDefineParserBase < V2C_VSToolParserBase
  private
  include V2C_VSToolDefineDefines
  def get_define_tool_info; @info_elem end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    tool_info = get_define_tool_info()
    case setting_key
    when TEXT_PREPROCESSORDEFINITIONS
      parse_preprocessor_definitions(tool_info.hash_defines, setting_value)
    else
      found = super
    end
    return found
  end
  def parse_preprocessor_definitions(hash_defines, attr_defines)
    split_values_list_discard_empty(attr_defines).each { |elem_define|
      str_define_key, str_define_value = elem_define.strip.split('=')
      next if skip_vs10_percent_sign_var(str_define_key)
      # Since a Hash will indicate nil for any non-existing key,
      # we do need to fill in _empty_ value for our _existing_ key.
      str_define_value ||= ''
      hash_defines[str_define_key] = str_define_value
    }
  end
end

module V2C_VSToolCompilerDefines
  include V2C_Compiler_Defines
  include V2C_VSToolDefineDefines
  TEXT_ADDITIONALINCLUDEDIRECTORIES = 'AdditionalIncludeDirectories'
  TEXT_ASSEMBLERLISTINGLOCATION = 'AssemblerListingLocation'
  TEXT_BASICRUNTIMECHECKS = 'BasicRuntimeChecks'
  TEXT_COMPILEAS = 'CompileAs'
  TEXT_DEBUGINFORMATIONFORMAT = 'DebugInformationFormat'
  TEXT_DISABLESPECIFICWARNINGS = 'DisableSpecificWarnings'
  TEXT_ENABLEFUNCTIONLEVELLINKING = 'EnableFunctionLevelLinking'
  TEXT_ENABLEINTRINSICFUNCTIONS = 'EnableIntrinsicFunctions'
  VS_DEFAULT_SETTING_ENABLEINTRINSICFUNCTIONS = false # VS10 default: "No"
  TEXT_ENABLEPREFAST = 'EnablePREfast'
  TEXT_EXCEPTIONHANDLING = 'ExceptionHandling'
  VS_DEFAULT_SETTING_EXCEPTIONHANDLING = true # VS10 "Enable C++ Exceptions" default: "Yes (/EHsc)"
  TEXT_INLINEFUNCTIONEXPANSION = 'InlineFunctionExpansion'
  TEXT_MINIMALREBUILD = 'MinimalRebuild'
  VS_DEFAULT_SETTING_MINIMALREBUILD = false # VS10 default: "No (/Gm-)"
  TEXT_OPTIMIZATION = 'Optimization'
  TEXT_PROGRAMDATABASEFILENAME = 'ProgramDatabaseFileName'
  TEXT_RUNTIMELIBRARY = 'RuntimeLibrary'
  VS_DEFAULT_SETTING_RUNTIMELIBRARY = V2C_Compiler_Defines::CRT_MULTITHREADED
  TEXT_RUNTIMETYPEINFO = 'RuntimeTypeInfo'
  TEXT_SHOWINCLUDES = 'ShowIncludes'
  VS_DEFAULT_SETTING_SHOWINCLUDES = false # VS10 default: "No"
  TEXT_STRINGPOOLING = 'StringPooling'
  TEXT_TREAT_WCHAR_T_AS_BUILTIN_TYPE = 'TreatWChar_tAsBuiltInType'
  VS_DEFAULT_SETTING_TREAT_WCHAR_T_AS_BUILTIN_TYPE = true # VS10 default: "Yes"
  TEXT_WARNINGLEVEL = 'WarningLevel'
  VS_DEFAULT_SETTING_WARNINGLEVEL = 3 # VS10 default: 3 (right!?)
end

class V2C_VSToolCompilerParser < V2C_VSToolDefineParserBase
  private

  include V2C_VSToolCompilerDefines
  def get_compiler_info; @info_elem end
  def allocate_precompiled_header_info(compiler_info)
    return if not get_compiler_info().precompiled_header_info.nil?
    get_compiler_info().precompiled_header_info = V2C_Precompiled_Header_Info.new
  end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when TEXT_ADDITIONALINCLUDEDIRECTORIES
      arr_include_dirs = Array.new
      parse_additional_include_directories(arr_include_dirs, setting_value)
      get_compiler_info().arr_info_include_dirs.concat(arr_include_dirs)
    when TEXT_ADDITIONALOPTIONS
      parse_additional_options(get_compiler_info().arr_tool_variant_specific_info[0].arr_flags, setting_value)
    when TEXT_ASSEMBLERLISTINGLOCATION
      get_compiler_info().asm_listing_location = get_filesystem_location(setting_value)
    when TEXT_BASICRUNTIMECHECKS
      get_compiler_info().basic_runtime_checks = parse_basic_runtime_checks(setting_value)
    when TEXT_COMPILEAS
      get_compiler_info().compile_as = parse_compile_as(setting_value)
    when TEXT_DEBUGINFORMATIONFORMAT
      get_compiler_info().debug_information_format = parse_debug_information_format(setting_value)
    when TEXT_DISABLESPECIFICWARNINGS
      parse_disable_specific_warnings(get_compiler_info().arr_tool_variant_specific_info[0].arr_disable_warnings, setting_value)
    when TEXT_ENABLEFUNCTIONLEVELLINKING
      get_compiler_info().function_level_linking_enable = get_boolean_value(setting_value)
    when TEXT_ENABLEINTRINSICFUNCTIONS
      get_compiler_info().intrinsic_functions_enable = get_boolean_value(setting_value)
    when TEXT_ENABLEPREFAST
      get_compiler_info().static_code_analysis_enable = get_boolean_value(setting_value)
    when TEXT_EXCEPTIONHANDLING
      get_compiler_info().exception_handling = parse_exception_handling(setting_value)
    when TEXT_INLINEFUNCTIONEXPANSION
      get_compiler_info().inline_function_expansion = parse_inline_function_expansion(setting_value)
    when TEXT_MINIMALREBUILD
      get_compiler_info().minimal_rebuild_enable = get_boolean_value(setting_value)
    when TEXT_OPTIMIZATION
      get_compiler_info().optimization = parse_optimization(setting_value)
    when TEXT_PROGRAMDATABASEFILENAME
      get_compiler_info().pdb_filename = get_filesystem_location(setting_value)
    when TEXT_RUNTIMELIBRARY
      get_compiler_info().runtime_library_variant = parse_runtime_library(setting_value)
    when TEXT_RUNTIMETYPEINFO
      get_compiler_info().rtti = get_boolean_value(setting_value)
    when TEXT_SHOWINCLUDES
      get_compiler_info().show_includes_enable = get_boolean_value(setting_value)
    when TEXT_STRINGPOOLING
      get_compiler_info().string_pooling_enable = get_boolean_value(setting_value)
    when TEXT_TREAT_WCHAR_T_AS_BUILTIN_TYPE
      get_compiler_info().treat_wchar_t_as_builtin_type_enable = get_boolean_value(setting_value)
    when TEXT_WARNINGLEVEL
      get_compiler_info().arr_tool_variant_specific_info[0].warning_level = parse_warning_level(setting_value)
    else
      found = super
    end
    return found
  end

  private

  def parse_additional_include_directories(arr_include_dirs_out, attr_incdir)
    split_values_list_preserve_ws_discard_empty(attr_incdir).each { |elem_inc_dir|
      next if skip_vs10_percent_sign_var(elem_inc_dir)
      elem_inc_dir = get_filesystem_location(elem_inc_dir)
      next if elem_inc_dir.nil?
      #logger.info "include is '#{elem_inc_dir}'"
      info_inc_dir = V2C_Info_Include_Dir.new
      info_inc_dir.dir = elem_inc_dir
      arr_include_dirs_out.push(info_inc_dir)
    }
  end
  def parse_disable_specific_warnings(arr_disable_warnings, attr_disable_warnings)
    arr_disable_warnings.replace(split_values_list_discard_empty(attr_disable_warnings))
  end
end

module V2C_VS7ToolSyntax
  include V2C_VS7Syntax
  include V2C_VSToolDefines
  TEXT_NAME = 'Name'
  TEXT_VCCLCOMPILERTOOL = 'VCCLCompilerTool'
  TEXT_VCLINKERTOOL = 'VCLinkerTool'
end

module V2C_VS7ToolCompilerSyntax
  include V2C_VS7ToolSyntax
  include V2C_VSToolCompilerDefines
  # pch names are _different_ (_swapped_) from their VS10 meanings...
  TEXT_PRECOMPILEDHEADERFILE_BINARY = 'PrecompiledHeaderFile'
  TEXT_PRECOMPILEDHEADERFILE_SOURCE = 'PrecompiledHeaderThrough'
  TEXT_USEPRECOMPILEDHEADER = 'UsePrecompiledHeader'
  TEXT_WARNASERROR = 'WarnAsError'
end

class V2C_VS7ToolCompilerParser < V2C_VSToolCompilerParser
  include V2C_VS7ToolCompilerSyntax

  private

  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    compiler_info = get_compiler_info()
    case setting_key
    when 'Detect64BitPortabilityProblems'
      # TODO: add /Wp64 to flags of an MSVC compiler info...
      compiler_info.detect_64bit_porting_problems_enable = get_boolean_value(setting_value)
    when TEXT_NAME
      compiler_info.name = setting_value
    when TEXT_PRECOMPILEDHEADERFILE_BINARY
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.header_binary_name = get_filesystem_location(setting_value)
    when TEXT_PRECOMPILEDHEADERFILE_SOURCE
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.header_source_name = get_filesystem_location(setting_value)
    when TEXT_USEPRECOMPILEDHEADER
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.use_mode = parse_use_precompiled_header(setting_value)
    when TEXT_WARNASERROR
      compiler_info.warnings_are_errors_enable = get_boolean_value(setting_value)
    else
      found = super
    end
    return found
  end
  def parse_basic_runtime_checks(str_basic_runtime_checks)
    return parse_integer(str_basic_runtime_checks)
  end
  def parse_compile_as(str_compile_as)
    parse_integer(str_compile_as)
  end
  def parse_debug_information_format(str_debug_information_format)
    return parse_integer(str_debug_information_format)
  end
  def parse_exception_handling(setting_value); parse_integer(setting_value) end
  def parse_inline_function_expansion(setting_value); parse_integer(setting_value) end
  def parse_optimization(setting_value); parse_integer(setting_value) end
  def parse_runtime_library(setting_value); parse_integer(setting_value) end
  def parse_use_precompiled_header(value_use_precompiled_header)
    use_val = parse_integer(value_use_precompiled_header)
    if use_val == 3; use_val = 2 end # VS7 --> VS8 migration change: all values of 3 have been replaced by 2, it seems...
    return use_val
  end
  def parse_warning_level(setting_value); parse_integer(setting_value) end
end

module V2C_VSToolLinkerDefines
  include V2C_VSToolDefines
  TEXT_ADDITIONALDEPENDENCIES = 'AdditionalDependencies'
  TEXT_ADDITIONALLIBRARYDIRECTORIES = 'AdditionalLibraryDirectories'
  TEXT_BASEADDRESS = 'BaseAddress'
  TEXT_DATAEXECUTIONPREVENTION = 'DataExecutionPrevention'
  TEXT_DELAYLOADDLLS = 'DelayLoadDLLs'
  TEXT_ENABLECOMDATFOLDING = 'EnableCOMDATFolding'
  TEXT_GENERATEDEBUGINFORMATION = 'GenerateDebugInformation'
  TEXT_GENERATEMAPFILE = 'GenerateMapFile'
  TEXT_IGNORESPECIFICDEFAULTLIBRARIES = 'IgnoreSpecificDefaultLibraries'
  TEXT_LINKINCREMENTAL = 'LinkIncremental'
  TEXT_MAPFILENAME = 'MapFileName'
  TEXT_MODULEDEFINITIONFILE = 'ModuleDefinitionFile'
  TEXT_OPTIMIZEREFERENCES = 'OptimizeReferences'
  TEXT_PERUSERREDIRECTION = 'PerUserRedirection'
  TEXT_PROGRAMDATABASEFILE = 'ProgramDatabaseFile'
  TEXT_RANDOMIZEDBASEADDRESS = 'RandomizedBaseAddress'
  TEXT_REGISTEROUTPUT = 'RegisterOutput'
  TEXT_STRIPPRIVATESYMBOLS = 'StripPrivateSymbols'
  TEXT_SUBSYSTEM = 'SubSystem'
  TEXT_TARGETMACHINE = 'TargetMachine'
  TEXT_ENABLEUAC = 'EnableUAC'
  VS_DEFAULT_SETTING_SUBSYSTEM = V2C_Linker_Defines::SUBSYSTEM_WINDOWS
  VS_DEFAULT_SETTING_TARGET_MACHINE = V2C_Linker_Defines::MACHINE_NOT_SET
end

class V2C_VSToolLinkerParser < V2C_VSToolParserBase
  private
  include V2C_VSToolLinkerDefines

  def get_linker_info; @info_elem end
  def get_linker_specific_info; return @info_elem.arr_tool_variant_specific_info[0] end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    linker_info = get_linker_info()
    case setting_key
    when TEXT_ADDITIONALDEPENDENCIES
      parse_additional_dependencies(setting_value, linker_info.arr_dependencies)
    when TEXT_ADDITIONALLIBRARYDIRECTORIES
      parse_additional_library_directories(setting_value, linker_info.arr_lib_dirs)
    when TEXT_ADDITIONALOPTIONS
      parse_additional_options(get_linker_specific_info().arr_flags, setting_value)
    when TEXT_BASEADDRESS
      linker_info.base_address = setting_value.hex
    when TEXT_DATAEXECUTIONPREVENTION
      linker_info.data_execution_prevention_enable = parse_data_execution_prevention_enable(setting_value)
    when TEXT_DELAYLOADDLLS
      parse_delay_load_dlls(setting_value, linker_info.arr_delay_load_dlls)
    when TEXT_ENABLECOMDATFOLDING
      linker_info.comdat_folding = parse_comdat_folding(setting_value)
    when TEXT_GENERATEDEBUGINFORMATION
      linker_info.generate_debug_information_enable = get_boolean_value(setting_value)
    when TEXT_GENERATEMAPFILE
      linker_info.generate_map_file_enable = parse_generate_map_file_enable(setting_value)
    when TEXT_IGNORESPECIFICDEFAULTLIBRARIES
      linker_info.arr_ignore_specific_default_libraries = parse_ignore_specific_default_libraries(setting_value)
    when TEXT_MAPFILENAME
      linker_info.map_file_name = parse_map_file_name(setting_value)
    when TEXT_MODULEDEFINITIONFILE
      linker_info.module_definition_file = parse_module_definition_file(setting_value)
    when TEXT_OPTIMIZEREFERENCES
      linker_info.optimize_references_enable = parse_optimize_references(setting_value)
    when TEXT_PERUSERREDIRECTION
      linker_info.per_user_redirection_enable = parse_per_user_redirection_enable(setting_value)
    when TEXT_PROGRAMDATABASEFILE
      linker_info.pdb_file = parse_pdb_file(setting_value)
    when TEXT_RANDOMIZEDBASEADDRESS
      linker_info.randomized_base_address_enable = parse_randomized_base_address_enable(setting_value)
    when TEXT_REGISTEROUTPUT
      linker_info.register_output_enable = parse_register_output_enable(setting_value)
    when TEXT_STRIPPRIVATESYMBOLS
      linker_info.strip_private_symbols_file = get_filesystem_location(setting_value)
    when TEXT_SUBSYSTEM
      linker_info.subsystem = parse_subsystem(setting_value)
    when TEXT_TARGETMACHINE
      linker_info.target_machine = parse_target_machine(setting_value)
    when TEXT_ENABLEUAC
      linker_info.uac_manifest_enable = parse_uac_manifest_enable(setting_value)
    else
      found = super
    end
    return found
  end

  def parse_additional_dependencies(attr_deps, arr_dependencies)
    return if attr_deps.empty?
    split_values_list_discard_empty(attr_deps).each { |elem_lib_dep|
      logger.debug "!!!!! elem_lib_dep #{elem_lib_dep}"
      next if skip_vs10_percent_sign_var(elem_lib_dep)
      elem_lib_dep = get_filesystem_location(elem_lib_dep)
      next if elem_lib_dep.nil?
      dependency_name = File.basename(elem_lib_dep, '.lib')
      arr_dependencies.push(V2C_Dependency_Info.new(dependency_name))
    }
  end
  def parse_data_execution_prevention_enable(str_data_execution_prevention_enable)
    get_boolean_value(str_data_execution_prevention_enable)
  end
  def parse_delay_load_dlls(str_delay_load_dlls, arr_delay_load_dlls)
    parse_fs_item_list(str_delay_load_dlls, arr_delay_load_dlls)
  end
  def parse_additional_library_directories(attr_lib_dirs, arr_lib_dirs)
    parse_fs_item_list(attr_lib_dirs, arr_lib_dirs)
  end
  # See comment at compiler-side method counterpart
  # It seems VS7 linker arguments are separated by whitespace --> empty split() argument.
  # UPDATE: now commented out since the common base method probably
  # can handle it correctly.
  #def parse_additional_options(arr_flags, attr_options); arr_flags.replace(attr_options.split()) end
  def parse_generate_map_file_enable(str_generate_map_file_enable)
    get_boolean_value(str_generate_map_file_enable)
  end
  def parse_ignore_specific_default_libraries(str_ignore_specific_default_libraries)
    str_ignore_specific_default_libraries.split()
  end
  def parse_map_file_name(str_map_file_name)
    get_filesystem_location(str_map_file_name)
  end
  def parse_module_definition_file(attr_module_definition_file)
    get_filesystem_location(attr_module_definition_file)
  end
  def parse_pdb_file(attr_pdb_file); get_filesystem_location(attr_pdb_file) end
  def parse_randomized_base_address_enable(str_randomized_base_address_enable)
    get_boolean_value(str_randomized_base_address_enable)
  end
  def parse_register_output_enable(str_parse_register_output_enable)
    get_boolean_value(str_parse_register_output_enable)
  end
  def parse_uac_manifest_enable(str_uac_manifest_enable)
    get_boolean_value(str_uac_manifest_enable)
  end
end

module V2C_VS7ToolLinkerDefines
  include V2C_VSToolLinkerDefines
  include V2C_VS7ToolSyntax
end

class V2C_VS7ToolLinkerParser < V2C_VSToolLinkerParser
  def initialize(linker_xml, linker_info_out)
    super(linker_xml, linker_info_out)
  end

  private
  include V2C_VS7ToolLinkerDefines

  def parse_attribute(setting_key, setting_value)
    found = be_optimistic()
    linker_info = get_linker_info()
    case setting_key
    when TEXT_LINKINCREMENTAL
      linker_info.link_incremental = parse_link_incremental(setting_value)
    when TEXT_NAME
      linker_info.name = setting_value
    else
      found = super
    end
    return found
  end
  def parse_comdat_folding(str_comdat_folding); parse_integer(str_comdat_folding) end
  def parse_link_incremental(str_link_incremental); parse_integer(str_link_incremental) end
  def parse_optimize_references(setting_value); parse_integer(setting_value) end
  def parse_subsystem(setting_value); parse_integer(setting_value) end
  def parse_target_machine(setting_value)
     machine = VS_DEFAULT_SETTING_TARGET_MACHINE
     case parse_integer(setting_value)
     when 0
       machine = V2C_Linker_Defines::MACHINE_NOT_SET
     when 1
       machine = V2C_Linker_Defines::MACHINE_X86
     when 17
       machine = V2C_Linker_Defines::MACHINE_X64
     else
       parser_error_todo("unknown target machine #{setting_value}")
     end
     return machine
  end
end

module V2C_VSToolMIDLDefines
  include V2C_VSToolDefineDefines
  TEXT_HEADERFILENAME = 'HeaderFileName'
  TEXT_INTERFACEIDENTIFIERFILENAME = 'InterfaceIdentifierFileName'
  TEXT_MKTYPLIBCOMPATIBLE = 'MkTypLibCompatible'
  TEXT_TYPELIBRARYNAME = 'TypeLibraryName'
end

class V2C_VSToolMIDLParser < V2C_VSToolDefineParserBase
  private
  include V2C_VSToolMIDLDefines

  def get_midl_info; @info_elem end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when TEXT_HEADERFILENAME
      get_midl_info().header_file_name = get_filesystem_location(setting_value)
    when TEXT_INTERFACEIDENTIFIERFILENAME
      get_midl_info().iface_id_file_name = get_filesystem_location(setting_value)
    when TEXT_MKTYPLIBCOMPATIBLE
      get_midl_info().mktyplib_compatible = get_boolean_value(setting_value)
    when TEXT_TYPELIBRARYNAME
      get_midl_info().type_library_name = get_filesystem_location(setting_value)
    else
      found = super
    end
    return found
  end
end

# Simple forwarder class. Creates specific parsers and invokes them.
class V2C_VS7ToolParser < V2C_VS7ParserBase
  def parse
    found = be_optimistic()
    toolname = @elem_xml.attributes[TEXT_NAME]
    arr_info = nil
    info = nil
    elem_parser = nil
    case toolname
    when TEXT_VCCLCOMPILERTOOL
      arr_info = get_tools_info().arr_compiler_info
      info = V2C_Tool_Compiler_Info.new(V2C_Tool_Compiler_Specific_Info_MSVC7.new)
      elem_parser = V2C_VS7ToolCompilerParser.new(@elem_xml, info)
    when TEXT_VCLINKERTOOL
      arr_info = get_tools_info().arr_linker_info
      info = V2C_Tool_Linker_Info.new(V2C_Tool_Linker_Specific_Info_MSVC7.new)
      elem_parser = V2C_VS7ToolLinkerParser.new(@elem_xml, info)
    else
      found = FOUND_FALSE
    end
    if not elem_parser.nil?
      elem_parser.parse
      arr_info.push(info)
    end
    return found
  end
  private
  include V2C_VS7ToolSyntax

  def get_tools_info; @info_elem end
end

# Default entries below indicate the setting used by VS7/10
# when no custom setting chosen
# (i.e. when remaining marked as non-bold in Configuration Dialog).
# TODO: further defaults (VS10):
#  IgnoreImportLibrary no
#  RegisterOutput no
#  Per-user redirection no
#  Use Library Dependent Inputs no

#  C++ Optimization:
#    Inline Function Expansion default
#    Enable Intrinsic Functions No
#    Favor Size Or Speed neither
#    Omit Frame Pointers No (/Oy-)
#    Enable Fiber-Safe Opts No
#    Whole Program Optimization No
#
#  C++ Code Generation:
#    Enable Minimal Rebuild No (/Gm-)
#    Smaller Type Check no
#    struct member alignment default
#    Buffer Security Check Yes (/GS)
#    Enable Enhanced Instruction Set not set
#    Floating Point Model Precise (/fp:precise)
#
#  Language:
#    Disable Language Extensions no
#    Force Conformance in for loop scope yes
#
#  Resources, XML Document Generator Suppress Startup Banner yes (/nologo)

module V2C_VSConfigurationDefines
  TEXT_ATLMINIMIZESCRUNTIMELIBRARYUSAGE = 'ATLMinimizesCRunTimeLibraryUsage'
  TEXT_CHARACTERSET = 'CharacterSet'
  TEXT_CONFIGURATIONTYPE = 'ConfigurationType'
  TEXT_WHOLEPROGRAMOPTIMIZATION = 'WholeProgramOptimization'
  VS_DEFAULT_SETTING_WHOLEPROGRAMOPTIMIZATION = false # VS10 default: "No"
  VS_DEFAULT_SETTING_CHARSET = V2C_TargetConfig_Defines::CHARSET_UNICODE # FIXME proper default??
  VS_DEFAULT_SETTING_CONFIGURATIONTYPE = V2C_TargetConfig_Defines::CFG_TYPE_APP # VS10: Application
  VS_DEFAULT_SETTING_MFC = V2C_TargetConfig_Defines::MFC_FALSE
end

module V2C_VS7ConfigurationDefines
  include V2C_VSConfigurationDefines
  TEXT_VS7_USEOFATL = 'UseOfATL'
  TEXT_VS7_USEOFMFC = 'UseOfMFC'
end

class V2C_VS7ConfigurationBaseParser < V2C_VS7ParserBase
  # VS10 has added a separation of these structs,
  # thus we need to pass _two_ distinct params even in VS7...
  def initialize(elem_xml, target_config_info_out, config_info_out)
    super(elem_xml, target_config_info_out)
    @config_info = config_info_out
  end
  private
  include V2C_VS7ConfigurationDefines

  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when TEXT_ATLMINIMIZESCRUNTIMELIBRARYUSAGE
      get_target_config_info().atl_minimizes_crt_lib_usage_enable = get_boolean_value(setting_value)
    when TEXT_CHARACTERSET
      get_target_config_info().charset = parse_charset(setting_value)
    when TEXT_CONFIGURATIONTYPE
      get_target_config_info().cfg_type = parse_configuration_type(setting_value)
    when 'Name'
      condition = V2C_Info_Condition.new
      arr_name = setting_value.split('|')
      condition.set_build_type(arr_name[0])
      condition.set_platform(arr_name[1])
      get_target_config_info().condition = condition
    when TEXT_VS7_USEOFATL
      get_target_config_info().use_of_atl = parse_integer(setting_value)
    when TEXT_VS7_USEOFMFC
      # VS7 does not seem to use string values (only 0/1/2 integers), while VS10 additionally does.
      # NOTE SPELLING DIFFERENCE: MSVS7 has UseOfMFC, MSVS10 has UseOfMfc (see CMake MSVS generators)
      get_target_config_info().use_of_mfc = parse_integer(setting_value)
    when TEXT_WHOLEPROGRAMOPTIMIZATION
      get_target_config_info().whole_program_optimization = parse_wp_optimization(setting_value)
    else
      found = super
    end
    return found
  end
  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'Tool'
      elem_parser = V2C_VS7ToolParser.new(subelem_xml, get_tools_info())
    else
      elem_parser = nil
    end
    if not elem_parser.nil?
      elem_parser.parse
    else
      found = super
    end
    return found
  end
  def parse_post_hook
    # While the conditional-related information is only available (parsed) once,
    # it needs to be passed to _both_ V2C_Target_Config_Build_Info _and_
    # V2C_Config_Base_Info:
    get_config_info().condition = get_target_config_info().condition
  end
  def get_target_config_info; @info_elem end
  def get_config_info; @config_info end
  def get_tools_info; get_config_info().tools end
  def parse_charset(str_charset); parse_integer(str_charset) end
  def parse_configuration_type(str_configuration_type); parse_integer(str_configuration_type) end
  def parse_wp_optimization(str_opt); parse_integer(str_opt) end
end

class V2C_VS7ProjectConfigurationParser < V2C_VS7ConfigurationBaseParser

  private

end

class V2C_VS7FileConfigurationParser < V2C_VS7ConfigurationBaseParser

  private

  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'ExcludedFromBuild'
      get_config_info().excluded_from_build = get_boolean_value(setting_value)
    else
      found = super
    end
    return found
  end
end

class V2C_VS7ConfigurationsParser < V2C_VS7ParserBase
  def initialize(elem_xml, info_elem_out, arr_target_config_info_out, build_platform_configs_out)
    super(elem_xml, info_elem_out)
    @arr_target_config_info = arr_target_config_info_out
    @build_platform_configs = build_platform_configs_out
  end
  private
  def get_arr_config_info(); @info_elem end
  def get_arr_target_config_info(); @arr_target_config_info end
  def get_build_platform_configs(); @build_platform_configs end

  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'Configuration'
      target_config_info_curr = V2C_Target_Config_Build_Info.new
      config_info_curr = V2C_Project_Config_Info.new
      elem_parser = V2C_VS7ProjectConfigurationParser.new(subelem_xml, target_config_info_curr, config_info_curr)
      if elem_parser.parse
        get_arr_target_config_info().push(target_config_info_curr)
        get_arr_config_info().push(config_info_curr)
        # And additionally add a platform config entry:
        add_platform_config(target_config_info_curr.condition)
      end
    else
      found = super
    end
    return found
  end
  def add_platform_config(condition)
    config_entry = V2C_BuildConfigurationEntry.new
    build_type = condition.get_build_type()
    build_platform = condition.get_build_platform()
    config_entry.description = "#{build_platform}|#{build_type}"
    config_entry.build_type = build_type
    config_entry.platform = build_platform
    get_build_platform_configs().add(config_entry)
  end
end

class V2C_Info_File
  ATTR_GENERATED = 1 # Whether it's an existing file or to be generated by build
  ATTR_SOURCE_CONTROL_FILE = 2
  def initialize
    @target_config_info = nil
    @config_info = nil
    @path_relative = ''
    @attr = 0
  end
  attr_accessor :target_config_info
  attr_accessor :config_info
  attr_accessor :path_relative

  def enable_attribute(attr); @attr |= attr end
  def disable_attribute(attr); @attr &= ~attr end
  def is_generated; return (@attr & ATTR_GENERATED) > 0 end
end

class V2C_VS7FileParser < V2C_VS7ParserBase
  VS7_IDL_FILE_TYPES_REGEX_OBJ = %r{_(i|p).c$}
  def initialize(file_xml, arr_file_infos_out)
    super(file_xml, arr_file_infos_out)
    @info_file = V2C_Info_File.new
    @add_to_build = false
  end
  def get_arr_file_infos; @info_elem end
  def parse
    logger.debug('parse')

    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_attribute(attr_xml.name, attr_xml.value)
    }
    @elem_xml.elements.each { |subelem_xml|
      parse_element(subelem_xml)
    }

    # FIXME: move these file skipping parts to _generator_ side,
    # don't skip adding file array entries here!!

    config_info_curr = @info_file.config_info
    excluded_from_build = false
    if not config_info_curr.nil? and config_info_curr.excluded_from_build
      excluded_from_build = true
    end

    # Ignore files which have the ExcludedFromBuild attribute set to TRUE
    if excluded_from_build
      return # no complex handling, just return
    end
    # Ignore files with custom build steps
    included_in_build = true
    @elem_xml.elements.each('FileConfiguration/Tool') { |subelem_xml|
      if subelem_xml.attributes['Name'] == 'VCCustomBuildTool'
        included_in_build = false
        return # no complex handling, just return
      end
    }

    if not excluded_from_build and included_in_build
      @add_to_build = true
    end
    parse_post_hook
  end

  private

  def parse_element(subelem_xml)
    found = be_optimistic()
    case subelem_xml.name
    when 'FileConfiguration'
      target_config_info_curr = V2C_Target_Config_Build_Info.new
      config_info_curr = V2C_File_Config_Info.new
      elem_parser = V2C_VS7FileConfigurationParser.new(subelem_xml, target_config_info_curr, config_info_curr)
      elem_parser.parse
      @info_file.target_config_info = target_config_info_curr
      @info_file.config_info = config_info_curr
    else
      found = super
    end
    return found
  end
  def parse_attribute(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'RelativePath'
      @info_file.path_relative = get_filesystem_location(setting_value)
      # Verbosely catch IDL generated files
      if VS7_IDL_FILE_TYPES_REGEX_OBJ.match(@info_file.path_relative)
        # see file_mappings.txt comment above
        logger.info "#{@info_file.path_relative} is an IDL file! FIXME: handling should be platform-dependent."
        @info_file.enable_attribute(V2C_Info_File::ATTR_GENERATED)
      end
    else
      found = super
    end
    return found
  end
  def parse_post_hook
    if true == @add_to_build
      get_arr_file_infos().push(@info_file)
    end
  end
end

# Tries to list all relevant source file language extensions
# (C/C++/ObjectiveC etc.):
BUILD_UNIT_FILE_TYPES_REGEX_OBJ = %r{\.(c|C|m|M)}
# VERY DIRTY interim helper, not sure at all where it will finally end up at
def check_have_build_units_in_file_list(arr_file_infos)
  have_build_units = false
  arr_file_infos.each { |file|
    if BUILD_UNIT_FILE_TYPES_REGEX_OBJ.match(file.path_relative)
      have_build_units = true
      break
    end
  }
  return have_build_units
end

module V2C_VSFilterDefines
  TEXT_UNIQUEIDENTIFIER = 'UniqueIdentifier'
end

class V2C_VS7FilterParser < V2C_VS7ParserBase
  def initialize(files_xml, project_out, files_str_out)
    super(files_xml, project_out)
    @files_str = files_str_out
  end
  def parse
    res = parse_file_list(@elem_xml, @files_str)
    return res
  end
  private
  include V2C_VSFilterDefines
  def get_project; @info_elem end
  def parse_file_list(vcproj_filter_xml, files_str)
    parse_file_list_attributes(vcproj_filter_xml, files_str)

    filter_info = files_str[:filter_info]
    if not filter_info.nil?
      # skip file filters that have a SourceControlFiles property
      # that's set to false, i.e. files which aren't under version
      # control (such as IDL generated files).
      # This experimental check might be a little rough after all...
      # yes, FIXME: on Win32, these files likely _should_ get listed
      # after all. We should probably do a platform check in such
      # cases, i.e. add support for a file_mappings.txt
      if false == filter_info.val_scmfiles
        logger.info "#{filter_info.name}: SourceControlFiles set to false, listing generated files? --> skipping!"
        return false
      end
      if not filter_info.name.nil?
        # Hrmm, this string match implementation is very open-coded ad-hoc imprecise.
        if filter_info.name == 'Generated Files' or filter_info.name == 'Generierte Dateien'
          # Hmm, how are we supposed to handle Generated Files?
          # Most likely we _are_ supposed to add such files
          # and set_property(SOURCE ... GENERATED) on it.
          logger.info "#{filter_info.name}: encountered a filter named Generated Files --> skipping! (FIXME)"
          return false
        end
      end
    end

    arr_file_infos = Array.new
    vcproj_filter_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'File'
        logger.debug('FOUND File')
        elem_parser = V2C_VS7FileParser.new(subelem_xml, arr_file_infos)
	elem_parser.parse
      when 'Filter'
        logger.debug('FOUND Filter')
        subfiles_str = Files_str.new
        elem_parser = V2C_VS7FilterParser.new(subelem_xml, get_project(), subfiles_str)
        if elem_parser.parse
          files_str[:arr_sub_filters] ||= Array.new
          files_str[:arr_sub_filters].push(subfiles_str)
        end
      else
        unknown_element_key(subelem_xml.name)
      end
    } # |subelem_xml|

    if not arr_file_infos.empty?
      files_str[:arr_file_infos] = arr_file_infos

      if true != get_project().have_build_units
        get_project().have_build_units = check_have_build_units_in_file_list(arr_file_infos)
      end
    end
    return true
  end

  private

  def parse_file_list_attributes(vcproj_filter_xml, files_str)
    filter_info = nil
    if vcproj_filter_xml.attributes.length
      filter_info = V2C_Info_Filter.new
    end
    vcproj_filter_xml.attributes.each_attribute { |attr_xml|
      parse_file_list_attribute(filter_info, attr_xml.name, attr_xml.value)
    }
    filter_info.name ||= 'COMMON'
    #logger.debug("parsed files group #{filter_info.name}, type #{filter_info.get_group_type()}")
    files_str[:filter_info] = filter_info
  end
  def parse_file_list_attribute(filter_info, setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'Filter'
      filter_info.arr_scfilter = split_values_list_discard_empty(setting_value)
    when 'Name'
      filter_info.name = setting_value
    when 'SourceControlFiles'
      filter_info.val_scmfiles = get_boolean_value(setting_value)
    when TEXT_UNIQUEIDENTIFIER
      filter_info.guid = setting_value
      setting_value_upper = setting_value.clone.upcase
	# TODO: these GUIDs actually seem to be identical between VS7 and VS10,
	# thus they should be made constants in a common base class...
      case setting_value_upper
      when '{4FC737F1-C7A5-4376-A066-2A32D752A2FF}'
	  #filter_info.is_compiles = true
      when '{93995380-89BD-4B04-88EB-625FBE52EBFB}'
	  #filter_info.is_includes = true
      when '{67DA6AB6-F800-4C08-8B7A-83BB121AAD01}'
        #filter_info.is_resources = true
      else
        unknown_value("unknown/custom UniqueIdentifier #{setting_value_upper}")
      end
    else
      unknown_attribute(setting_key, setting_value)
    end
    return found
  end
end

class V2C_VS7PlatformParser < V2C_VS7ParserBase
  def initialize(elem_xml, info_elem_out)
    super(elem_xml, info_elem_out)
  end
  private

  def parse_attribute(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'Name'
      @info_elem = setting_value
    else
      found = super
    end
    return found
  end
end

class V2C_VS7PlatformsParser < V2C_VS7ParserBase
  def initialize(elem_xml, info_elem_out)
    super(elem_xml, info_elem_out)
  end
  private
  def get_build_platform_configs(); @info_elem end

  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'Platform'
      platform_name = ''
      elem_parser = V2C_VS7PlatformParser.new(subelem_xml, platform_name)
      if elem_parser.parse
        # Hrmm... while Ruby does pass string parameters by reference,
	# once, in this case we do it _twice_ (into class member)
	# and this seems to mess it up since the internal assignment
	# doesn't make it back out here. There's no explanation about that
	# that I could find easily...
	# Thus resort to elem_parser.info_elem. Ugh.
        get_build_platform_configs().register_platform(elem_parser.info_elem)
      end
    else
      found = super
    end
    return found
  end
end

class V2C_VS7ToolFilesParser < V2C_VS7ParserBase
  def initialize(elem_xml, info_elem_out)
    super(elem_xml, info_elem_out)
  end
  def parse_element(subelem_xml)
    found = be_optimistic()
    log_debug "TOOLFILES: #{subelem_xml.name}, #{subelem_xml.value}"
    return found
  end
end

module V2C_VSProjectDefines
  TEXT_KEYWORD = 'Keyword'
  TEXT_ROOTNAMESPACE = 'RootNamespace'
end

class V2C_VS7ProjectParser < V2C_VS7ProjectParserBase
  private
  include V2C_VSProjectDefines
  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'Configurations'
      elem_parser = V2C_VS7ConfigurationsParser.new(
        subelem_xml,
        get_project().arr_config_info,
        get_project().arr_target_config_info,
        get_project().build_platform_configs
      )
    when 'Files' # "Files" simply appears to be a special "Filter" element without any filter conditions.
      # FIXME: we most likely shouldn't pass a rather global "project target" object here! (pass a file info object)
      get_project().main_files = Files_str.new
      elem_parser = V2C_VS7FilterParser.new(subelem_xml, get_project(), get_project().main_files)
    when 'Platforms'
      elem_parser = V2C_VS7PlatformsParser.new(subelem_xml, get_project().build_platform_configs)
    when 'ToolFiles'
      elem_parser = V2C_VS7ToolFilesParser.new(subelem_xml, nil)
    else
      elem_parser = nil
    end
    if not elem_parser.nil?
      elem_parser.parse
    else
      found = super
    end
    return found
  end

  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when TEXT_KEYWORD
      get_project().vs_keyword = setting_value
    when 'Name'
      get_project().name = setting_value
    when 'ProjectCreator' # used by Fortran .vfproj ("Intel Fortran")
      get_project().creator = setting_value
    when 'ProjectGUID', 'ProjectIdGuid' # used by Visual C++ .vcproj, Fortran .vfproj
      get_project().guid = setting_value
    when 'ProjectType'
      get_project().type = setting_value
    when TEXT_ROOTNAMESPACE
      get_project().root_namespace = setting_value
    when 'Version'
      get_project().version = setting_value

    when VS_SCC_ATTR_REGEX_OBJ
      found = parse_attributes_scc(setting_key, setting_value, get_project().scc_info)
    else
      found = super
    end
    return found
  end
  def parse_attributes_scc(setting_key, setting_value, scc_info_out)
    found = be_optimistic()
    case setting_key
    # Hrmm, turns out having SccProjectName is no guarantee that both SccLocalPath and SccProvider
    # exist, too... (one project had SccProvider missing). HOWEVER,
    # CMake generator does expect all three to exist when available! Hmm.
    when 'SccProjectName'
      scc_info_out.project_name = setting_value
    # There's a special SAK (Should Already Know) entry marker
    # (see e.g. http://stackoverflow.com/a/6356615 ).
    # Currently I don't believe we need to handle "SAK" in special ways
    # (such as filling it in in case of missing entries),
    # transparent handling ought to be sufficient.
    when 'SccLocalPath'
      scc_info_out.local_path = setting_value
    when 'SccProvider'
      scc_info_out.provider = setting_value
    when 'SccAuxPath'
      scc_info_out.aux_path = setting_value
    else
      found = FOUND_FALSE
    end
    return found
  end
end

class V2C_VSProjectFilesBundleParserBase < V2C_LoggerBase
  def initialize(p_parser_proj_file, str_orig_environment_shortname, arr_projects_out)
    @p_parser_proj_file = p_parser_proj_file
    @proj_filename = p_parser_proj_file.to_s # FIXME: do we want to keep the string-based filename? We should probably change several sub classes to be Pathname-based...
    @str_orig_environment_shortname = str_orig_environment_shortname
    @arr_projects_out_all = arr_projects_out # We'll keep a project _array_ as member since it's conceivable that both VS7 and VS10 might have several project elements in their XML files.
    @arr_projects_out = Array.new # the specific projects parsed within this run
  end
  def parse
    parse_project_files
    check_unhandled_file_types
    mark_projects_postprocessing
    @arr_projects_out_all.concat(@arr_projects_out)
  end

  # Hrmm, that function does not really belong
  # in this somewhat too specific class...
  def check_unhandled_file_type(str_ext)
    str_file = "#{@proj_filename}.#{str_ext}"
    if File.exists?(str_file)
      logger.unhandled_functionality("parser does not handle type of file #{str_file} yet!")
    end
  end

  private

  def get_default_project_name;
    return (@p_parser_proj_file.basename.to_s).split('.')[0]
  end
  def mark_projects_postprocessing
    mark_projects_orig_environment_shortname(@str_orig_environment_shortname)
    project_name_default = get_default_project_name
    mark_projects_default_project_name(project_name_default)
    @arr_projects_out.each { |project_new|
      # FIXME: lists main project file only - should probably also
      # add some peripheral original project files (.filters, .user, ...).
      project_new.arr_p_original_project_files = [ @p_parser_proj_file ]
    }
  end
  def mark_projects_orig_environment_shortname(str_orig_environment_shortname)
    @arr_projects_out.each { |project_new|
      project_new.orig_environment_shortname = str_orig_environment_shortname
    }
  end
  def mark_projects_default_project_name(project_name_default)
    @arr_projects_out.each { |project_new|
      project_new.name ||= project_name_default
    }
  end
end

# Project parser variant which works on XML-stream-based input
class V2C_VS7ProjectFileXmlParser < V2C_VSProjectFileXmlParserBase
  def parse_element(subelem_xml)
    setting_key = subelem_xml.name
    found = be_optimistic()
    case setting_key
    when 'VisualStudioProject'
      project = V2C_Project_Info.new
      project_parser = V2C_VS7ProjectParser.new(subelem_xml, project)
      project_parser.parse

      get_arr_projects_out().push(project)
    else
      found = super
    end
    return found
  end
end

# Project parser variant which works on file-based input
class V2C_VSProjectFileParserBase < V2C_ParserBase
  def initialize(p_parser_proj_file, arr_projects_out)
    @p_parser_proj_file = p_parser_proj_file
    @proj_filename = p_parser_proj_file.to_s
    @arr_projects_out = arr_projects_out
    @proj_xml_parser = nil
  end
end

class V2C_VS7ProjectFileParser < V2C_VSProjectFileParserBase
  def parse_file
    File.open(@proj_filename) { |io|
      doc_proj = REXML::Document.new io

      @proj_xml_parser = V2C_VS7ProjectFileXmlParser.new(doc_proj, @arr_projects_out)
      #super.parse
      @proj_xml_parser.parse
    }
  end
end

class V2C_VS7ProjectFilesBundleParser < V2C_VSProjectFilesBundleParserBase
  def initialize(p_parser_proj_file, arr_projects_out)
    super(p_parser_proj_file, 'MSVS7', arr_projects_out)
  end
  def parse_project_files
    proj_file_parser = V2C_VS7ProjectFileParser.new(@p_parser_proj_file, @arr_projects_out)
    proj_file_parser.parse_file
  end
  def check_unhandled_file_types
    # FIXME: we don't handle now externally specified (.rules, .vsprops) custom build parts yet!
    check_unhandled_file_type('rules')
    check_unhandled_file_type('vsprops')
    # Well, .user files are called .vcproj.[USERNAME].user,
    # thus we'd have to do more elaborate lookup...
    ## Not sure whether we want to evaluate the settings in .user files...
    #check_unhandled_file_type('user')
  end
end

module V2C_VS10Defines
  TEXT_CONDITION = 'Condition'
  TEXT_DEFAULT = 'Default'
  TEXT_DISABLED = 'Disabled'
end

module V2C_VS10Syntax
  include V2C_VS10Defines

  def parse_boolean_property_value(str_value)
    success, value = parse_boolean_text(str_value)
    if true != success
      # Hrmm, did we hit a totally unexpected (new) element value!?
      parser_error_syntax("unknown boolean value text \"#{str_value}\"")
    end
    return value
  end
end

# NOTE: VS10 == MSBuild == somewhat Ant-based.
# Thus it would probably be useful to create an Ant syntax parser base class
# and derive MSBuild-specific behaviour from it.
# For a list of XML file element names (i.e. schema info), see
#   http://stackoverflow.com/questions/7899043/getting-lots-of-warnings-when-building-with-targets-in-visual-studio-2010
class V2C_VS10ParserBase < V2C_VSXmlParserBase
  include V2C_VS10Syntax
end

# Parses elements with optional conditional information (Condition=xxx).
class V2C_VS10BaseElemParser < V2C_VS10ParserBase
  def initialize(elem_xml, info_elem_out)
    super(elem_xml, info_elem_out)
    @have_condition = false
  end
  private
  include V2C_VS10Defines

  def get_base_elem; @info_elem end
  def parse_attribute(setting_key, setting_value)
    found = be_optimistic()
    log_debug(setting_key)
    case setting_key
    when TEXT_CONDITION
      # set have_condition bool to true,
      # then verify further below that the element that was filled in
      # actually had its condition parsed properly (V2C_Info_Elem_Base.@condition != nil),
      # since conditions need to be parsed separately by each property item class type's base class
      # (upon "Condition" attribute parsing the exact property item class often is not known yet i.e. nil!!).
      # Or is there a better way to achieve common, reliable parsing of that condition information?
      @have_condition = true
      if not get_base_elem().condition.nil?
        parser_error_logic('huh, pre-existing condition!?')
      else
        get_base_elem().condition = V2C_Info_Condition.new(setting_value)
      end
    else
      found = super
    end
    return found
  end

  private

  def verify_execution
    if not check_condition
      parser_error_logic('unhandled condition element!?')
    end
  end
  def check_condition
    success = true
    if not @have_condition
      # check whether there really was no condition
      # (derived classes might have failed to call into base class handling!!)
      if not @elem_xml.attributes[TEXT_CONDITION].nil?
        @have_condition = true
      end
    end
    if @have_condition
      if get_base_elem().condition.nil?
        success = false
      end
    end
    return success
  end
end

class V2C_VS10ItemGroupProjectConfigurationDescriptionParser < V2C_VS10ParserBase
  private
  def get_config_entry; @info_elem end

  def parse_attribute(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'Include'
      get_config_entry().description = setting_value
    else
      found = super
    end
    return found
  end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'Configuration'
      get_config_entry().build_type = setting_value
    when 'Platform'
      get_config_entry().platform = setting_value
    else
      found = super
    end
    return found
  end
  def parse_post_hook
    super
    logger.debug("build type #{get_config_entry().build_type}, platform #{get_config_entry().platform}")
  end
end

class V2C_VS10ItemGroupProjectConfigurationsParser < V2C_VS10ParserBase
  private

  def get_project_configs; @info_elem end
  def parse_element(itemgroup_elem_xml)
    found = be_optimistic()
    case itemgroup_elem_xml.name
    when 'ProjectConfiguration'
      config_entry = V2C_BuildConfigurationEntry.new
      projconf_parser = V2C_VS10ItemGroupProjectConfigurationDescriptionParser.new(itemgroup_elem_xml, config_entry)
      projconf_parser.parse
      # VS10 does not separately list the platforms that it will provide
      # configuration for, thus we need to manually register it prior to
      # adding the full entry.
      get_project_configs().register_platform(config_entry.platform)
      get_project_configs().add(config_entry)
    else
      found = super
    end
    return found
  end
end

module V2C_VS10FilterDefines
  include V2C_VSFilterDefines
  TEXT_VS10_EXTENSIONS = 'Extensions'
end

class V2C_VS10ItemGroupElemFilterParser < V2C_VS10ParserBase
  private
  include V2C_VS10FilterDefines
  def parse_attribute(setting_value, setting_key)
    found = be_optimistic()
    case setting_key
    when 'Include'
       get_filter().name = setting_value
    else
      found = super
    end
    return found
  end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when TEXT_VS10_EXTENSIONS
      get_filter().arr_scfilter = split_values_list_discard_empty(setting_value)
    when TEXT_UNIQUEIDENTIFIER
      get_filter().guid = setting_value
    else
      found = super
    end
    return found
  end
  def get_filter; @info_elem end
end

class V2C_VS10ItemGroupFiltersParser
  def parse
    logger.fixme "FIXME!!!"
  end
end

class V2C_VS10ItemGroupFileElemParser < V2C_VS10ParserBase
  private

  def get_file_elem; @info_elem end # V2C_Info_File

  def parse_attribute(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when 'Include'
      get_file_elem().path_relative = get_filesystem_location(setting_value)
    else
      found = super
    end
    return found
  end
end

class V2C_VS10ItemGroupFilesParser < V2C_VS10ParserBase
  def initialize(elem_xml, file_list_out)
    super(elem_xml, file_list_out)
    @list_name = file_list_out.name
  end
  def get_file_list; @info_elem end
  def parse_element(subelem_xml)
    if not subelem_xml.name == @list_name
      parser_error_syntax("ItemGroup element mismatch! list name #{@list_name} vs. element name #{subelem_xml.name}!")
    end
    file_info = V2C_Info_File.new
    file_parser = V2C_VS10ItemGroupFileElemParser.new(subelem_xml, file_info)
    found = file_parser.parse
    if FOUND_TRUE == found
      get_file_list().append_file(file_info)
    else
      found = super
    end
    return found
  end
  #def parse_post_hook
  #  log_fatal "file list: #{get_file_list().inspect}"
  #end
end

class V2C_VS10ItemGroupAnonymousParser < V2C_VS10ParserBase
  def parse
    found = FOUND_FALSE
    elem_first = @elem_xml.elements[1] # 1-based index!!
    if not elem_first.nil?
      found = be_optimistic()
      elem_name = elem_first.name
      elem_parser = nil
      case elem_name
      when 'Filter'
        elem_parser = V2C_VS10ItemGroupFiltersParser.new(@elem_xml, get_project().filters)
      when 'ClCompile', 'ClInclude', 'Midl', 'None', 'ResourceCompile'
        file_list_new = V2C_File_List_Info.new(elem_name, get_file_list_type(elem_name))
        elem_parser = V2C_VS10ItemGroupFilesParser.new(@elem_xml, file_list_new)
        elem_parser.parse
        get_project().file_lists.append(file_list_new)
      else
        # We should NOT call base method, right? This is an _override_ of the
        # standard method, and we expect to be able to parse it fully,
        # thus signal failure.
        found = FOUND_FALSE
      end
    end
    return found
  end

  private

  def get_project; @info_elem end
  def parse_element_DEPRECATED(subelem_xml)
    found = be_optimistic()
    setting_key = subelem_xml.name
    filter = V2C_Info_Filter.new
    elem_parser = V2C_VS10ItemGroupElemFilterParser.new(subelem_xml, filter)
    elem_parser.parse
    get_project().filters.append(filter)
    # Due to split between .vcxproj and .vcxproj.filters,
    # need to possibly _enhance_ an _existing_ (added by the prior file)
    # item group info, thus make sure to do lookup first.
    file_list_name = setting_key
    #file_list_type = get_file_list_type(file_list_name)
    #file_list = get_project().file_lists.lookup_from_name(file_list_name)
    file_list_new = V2C_File_List_Info.new(file_list_name, get_file_list_type(file_list_name))
    elem_parser = V2C_VS10ItemGroupElemFileListParser.new(subelem_xml, file_list_new)
    elem_parser.parse
    get_project().file_lists.append(file_list_new)
    # TODO:
    #if not @itemgroup.label.nil?
    #  if not setting_key == @itemgroup.label
    #    parser_error_syntax("item label #{setting_key} does not match group's label #{@itemgroup.label}!?")
    #  end
    #end
    return found
  end
  def get_file_list_type(file_list_name)
    type = V2C_File_List_Types::TYPE_NONE
    case file_list_name
    when 'None'
      type = V2C_File_List_Types::TYPE_NONE
    when 'ClCompile'
      type = V2C_File_List_Types::TYPE_COMPILES
    when 'ClInclude'
      type = V2C_File_List_Types::TYPE_INCLUDES
    when 'ResourceCompile'
      type = V2C_File_List_Types::TYPE_RESOURCES
    when 'Midl'
      type = V2C_File_List_Types::TYPE_MIDL
    else
      logger.unhandled_functionality("file list name #{file_list_name}")
      type = V2C_File_List_Types::TYPE_NONE
    end
    return type
  end
end

# Simple forwarder class. Creates specific property group parsers
# and invokes them.
# V2C_VS10PropertyGroupParser / V2C_VS10ItemGroupParser are pretty much identical.
class V2C_VS10ItemGroupParser < V2C_VS10ParserBase
  def parse
    found = be_optimistic()
    itemgroup_label = @elem_xml.attributes['Label']
    logger.debug("Label #{itemgroup_label}!")
    item_group_parser = nil
    case itemgroup_label
    when 'ProjectConfigurations'
      item_group_parser =
      V2C_VS10ItemGroupProjectConfigurationsParser.new(@elem_xml, get_project().build_platform_configs)
    when nil
      item_group_parser = V2C_VS10ItemGroupAnonymousParser.new(@elem_xml, get_project())
    else
      item_group_parser = nil
    end
    if not item_group_parser.nil?
      item_group_parser.parse
    end
    log_found(found, itemgroup_label)
    return found
  end

  private

  def get_project; @info_elem end
end

module V2C_VS10ToolSyntax
  include V2C_VSToolDefines
  include V2C_VS10Syntax
end

module V2C_VS10ToolCompilerSyntax
  include V2C_VS10ToolSyntax
  include V2C_VSToolCompilerDefines
  TEXT_PRECOMPILEDHEADER = 'PrecompiledHeader'
  TEXT_PRECOMPILEDHEADERFILE = 'PrecompiledHeaderFile'
  TEXT_PRECOMPILEDHEADEROUTPUTFILE = 'PrecompiledHeaderOutputFile'
  TEXT_TREATWARNINGASERROR = 'TreatWarningAsError'
end

class V2C_VS10ToolCompilerParser < V2C_VSToolCompilerParser
  private
  include V2C_VS10ToolCompilerSyntax

  def parse_element(subelem_xml)
    found = be_optimistic()
    setting_key = subelem_xml.name
    setting_value = subelem_xml.text
    case setting_key
    when 'MultiProcessorCompilation'
      get_compiler_info().multi_core_compilation_enable = get_boolean_value(setting_value)
    when 'ObjectFileName'
       # TODO: support it - but with a CMake out-of-tree build this setting is very unimportant methinks.
       skipped_element_warn(setting_key)
    when TEXT_PRECOMPILEDHEADER
      allocate_precompiled_header_info(get_compiler_info())
      get_compiler_info().precompiled_header_info.use_mode = parse_use_precompiled_header(setting_value)
    when TEXT_PRECOMPILEDHEADERFILE
      allocate_precompiled_header_info(get_compiler_info())
      get_compiler_info().precompiled_header_info.header_source_name = get_filesystem_location(setting_value)
    when TEXT_PRECOMPILEDHEADEROUTPUTFILE
      allocate_precompiled_header_info(get_compiler_info())
      get_compiler_info().precompiled_header_info.header_binary_name = get_filesystem_location(setting_value)
    when TEXT_TREATWARNINGASERROR
      get_compiler_info().warnings_are_errors_enable = get_boolean_value(setting_value)
    else
      found = super
    end
    return found
  end

  private

  def parse_basic_runtime_checks(str_basic_runtime_checks)
    arr_basic_runtime_checks = [
      TEXT_DEFAULT, # 0
      'StackFrameRuntimeCheck', # 1, /RTCs
      'UninitializedLocalUsageCheck', # 2, /RTCu
      'EnableFastChecks' # 3, /RTC1
    ]
    return string_to_index(arr_basic_runtime_checks, str_basic_runtime_checks, 0)
  end
  def parse_compile_as(str_compile_as)
    arr_compile_as = [
      TEXT_DEFAULT, # 0
      'C', # 1 (FIXME: might be incorrect)
      'CPlusPlus' # 2 (FIXME: might be incorrect)
    ]
    return string_to_index(arr_compile_as, str_compile_as, 0)
  end
  def parse_debug_information_format(str_debug_information_format)
    arr_debug_information_format = [
      '', # Disabled
      'OldStyle', # 1, /Z7
      'None', # 2
      'ProgramDatabase', # 3, /Zi
      'EditAndContinue' # 4, /ZI
    ]
    return string_to_index(arr_debug_information_format, str_debug_information_format, 0)
  end
  def parse_exception_handling(str_exception_handling)
    arr_except = [
      'false', # 0, false
      'Sync', # 1, Sync, /EHsc
      'Async', # 2, Async, /EHa
      'SyncCThrow' # 3, SyncCThrow, /EHs
    ]
    return string_to_index(arr_except, str_exception_handling, 0)
  end
  def parse_inline_function_expansion(str_inline_func_expand)
    arr_inline_func = [
      TEXT_DISABLED, # 0, /Ob0
      'OnlyExplicitInline', # 1, /Ob1
      'AnySuitable' # 2, /Ob2
    ]
    return string_to_index(arr_inline_func, str_inline_func_expand, INLINE_FUNCTION_EXPANSION_DEFAULT)
  end
  def parse_optimization(str_optimization)
    arr_optimization = [
      TEXT_DISABLED, # 0, /Od
      'MinSpace', # 1, /O1
      'MaxSpeed', # 2, /O2
      'Full' # 3, /Ox
    ]
    return string_to_index(arr_optimization, str_optimization, 0)
  end
  def parse_runtime_library(str_crt)
    arr_crt = [
      '', # 0, None (?)
      'MultiThreaded', # 1, /MT
      'MultiThreadedDebug', # 2, /MTd
      'MultiThreadedDLL', # 3, /MD
      'MultiThreadedDebugDLL', # 4, /MDd
    ]
    return string_to_index(arr_crt, str_crt, 1)
  end
  def parse_use_precompiled_header(str_use_precompiled_header)
    return string_to_index([ 'NotUsing', 'Create', 'Use' ], str_use_precompiled_header.strip, 0)
  end
  def parse_warning_level(str_warning_level)
    arr_warn_level = [
      'TurnOffAllWarnings', # /W0
      'Level1', # /W1
      'Level2', # /W2
      'Level3', # /W3
      'Level4', # /W4
      'EnableAllWarnings' # /Wall
    ]
    return string_to_index(arr_warn_level, str_warning_level, VS_DEFAULT_SETTING_WARNINGLEVEL)
  end
end

module V2C_VS10ToolLinkerSyntax
  include V2C_VS10ToolSyntax
  include V2C_VSToolLinkerDefines
  include V2C_Linker_Defines
end

class V2C_VS10ToolLinkerParser < V2C_VSToolLinkerParser
  include V2C_VS10ToolLinkerSyntax
  private

  #def parse_setting(setting_key, setting_value)
  #  found = be_optimistic()
  #  case setting_key
  #  when TEXT_OPTIMIZEREFERENCES
  #    get_linker_info().optimize_references_enable = get_boolean_value(setting_value)
  #  else
  #    found = super
  #  end
  #  return found
  #end
  def parse_comdat_folding(str_comdat_folding); get_boolean_value(str_comdat_folding) end
  def parse_optimize_references(setting_value); get_boolean_value(setting_value) end
  def parse_per_user_redirection_enable(str_per_user_redirection_enable)
    get_boolean_value(str_per_user_redirection_enable)
  end
  def parse_target_machine(str_machine)
     machine = VS_DEFAULT_SETTING_TARGET_MACHINE
     case str_machine
     when TEXT_VS10_NOTSET
       machine = V2C_Linker_Defines::MACHINE_NOT_SET
     when 'MachineX86'
       machine = V2C_Linker_Defines::MACHINE_X86
     when 'MachineX64'
       machine = V2C_Linker_Defines::MACHINE_X64
     else
       parser_todo_error("unknown target machine #{str_machine}")
     end
     return machine
  end
  def parse_subsystem(str_subsystem)
    arr_subsystem = [
      TEXT_VS10_NOTSET, # VS7: 0
      'Console', # VS7: 1
      'Windows', # VS7: 2
      'Native', # VS7: 3
      'EFIApplication', # VS7: 4
      'EFIBootService', # VS7: 5
      'EFIROM', # VS7: 6
      'EFIRuntime', # VS7: 7
      'Posix', # VS7: 8
      'WindowsCE' # VS7: 9
    ]
    return string_to_index(arr_subsystem, str_subsystem, VS_DEFAULT_SETTING_SUBSYSTEM)
  end
end

class V2C_VS10ToolMIDLParser < V2C_VSToolMIDLParser
  include V2C_VS10Syntax
end

class V2C_VS10ItemDefinitionGroupParser < V2C_VS10BaseElemParser
  private

  def get_config_info; @info_elem end
  def get_tools_info; return get_config_info().tools end
  def parse_element(subelem_xml)
    found = be_optimistic()
    setting_key = subelem_xml.name
    item_def_group_parser = nil # IMPORTANT: reset it!
    arr_info = nil
    info = nil
    log_debug(setting_key)
    case setting_key
    when 'ClCompile'
      arr_info = get_tools_info().arr_compiler_info
      info = V2C_Tool_Compiler_Info.new(V2C_Tool_Compiler_Specific_Info_MSVC10.new)
      item_def_group_parser = V2C_VS10ToolCompilerParser.new(subelem_xml, info)
    #when 'ResourceCompile'
    when 'Link'
      arr_info = get_tools_info().arr_linker_info
      info = V2C_Tool_Linker_Info.new(V2C_Tool_Linker_Specific_Info_MSVC10.new)
      item_def_group_parser = V2C_VS10ToolLinkerParser.new(subelem_xml, info)
    when 'Midl'
      arr_info = get_tools_info().arr_midl_info
      info = V2C_Tool_MIDL_Info.new(V2C_Tool_MIDL_Specific_Info_MSVC10.new)
      item_def_group_parser = V2C_VS10ToolMIDLParser.new(subelem_xml, info)
    else
      found = super
    end
    if not item_def_group_parser.nil?
      item_def_group_parser.parse
      arr_info.push(info)
    end
    return found
  end
end

module V2C_VS10Defines
  TEXT_VS10_NOTSET = 'NotSet'
end

module V2C_VS10ConfigurationDefines
  include V2C_VSConfigurationDefines
  include V2C_VS10Defines
  TEXT_VS10_USEOFATL = 'UseOfAtl'
  TEXT_VS10_USEOFMFC = 'UseOfMfc'
end

class V2C_VS10PropertyGroupConfigurationParser < V2C_VS10BaseElemParser
  def initialize(elem_xml, info_elem_out)
    super(elem_xml, info_elem_out)
    set_vs_specific_default_values(info_elem_out)
  end
private
  include V2C_VS10ConfigurationDefines
  include V2C_TargetConfig_Defines
  def get_configuration; @info_elem end

  def set_vs_specific_default_values(target_config_info)
    target_config_info.cfg_type = CFG_TYPE_APP
  end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    config_info_curr = get_configuration()
    case setting_key
    when TEXT_CHARACTERSET
      config_info_curr.charset = parse_charset(setting_value)
    when TEXT_CONFIGURATIONTYPE
      config_info_curr.cfg_type = parse_configuration_type(setting_value)
    when TEXT_VS10_USEOFATL
      config_info_curr.use_of_atl = parse_use_of_atl_mfc(setting_value)
    when TEXT_VS10_USEOFMFC
      config_info_curr.use_of_mfc = parse_use_of_atl_mfc(setting_value)
    when TEXT_WHOLEPROGRAMOPTIMIZATION
      config_info_curr.whole_program_optimization = parse_wp_optimization(setting_value)
    else
      found = super
    end
    return found
  end

  def parse_charset(str_charset)
    # Possibly useful related link: "[CMake] Bug #12189"
    #   http://www.cmake.org/pipermail/cmake/2011-June/045002.html
    arr_charset = [
      TEXT_VS10_NOTSET,  # 0 (ASCII i.e. SBCS)
      'Unicode', # 1 (The Healthy Choice)
      'MultiByte' # 2 (MBCS)
    ]
    return string_to_index(arr_charset, str_charset, VS_DEFAULT_SETTING_CHARSET)
  end
  def parse_configuration_type(str_configuration_type)
    arr_config_type = [
      'Unknown', # 0, typeUnknown (utility)
      'Application', # 1, typeApplication (.exe)
      'DynamicLibrary', # 2, typeDynamicLibrary (.dll)
      'UNKNOWN_FIXME', # 3
      'StaticLibrary' # 4, typeStaticLibrary
    ]
    return string_to_index(arr_config_type, str_configuration_type, VS_DEFAULT_SETTING_CONFIGURATIONTYPE)
  end
  def parse_use_of_atl_mfc(str_use_of_atl_mfc)
    return string_to_index([ 'false', 'Static', 'Dynamic' ], str_use_of_atl_mfc, VS_DEFAULT_SETTING_MFC)
  end
  def parse_wp_optimization(str_opt); get_boolean_value(str_opt) end
end

class V2C_VS10PropertyGroupGlobalsParser < V2C_VS10BaseElemParser
  private
  include V2C_VSProjectDefines

  def get_project; @info_elem end
  def parse_setting(setting_key, setting_value)
    found = be_optimistic()
    case setting_key
    when TEXT_KEYWORD
      get_project().vs_keyword = setting_value
    when 'ProjectGuid'
      get_project().guid = setting_value
    when 'ProjectName'
      get_project().name = setting_value
    when TEXT_ROOTNAMESPACE
      get_project().root_namespace = setting_value
    when VS_SCC_ATTR_REGEX_OBJ
      found = parse_elements_scc(setting_key, setting_value, get_project().scc_info)
    else
      found = FOUND_FALSE
    end
    if FOUND_FALSE == found; found = super end
    return found
  end
  def parse_elements_scc(setting_key, setting_value, scc_info_out)
    found = be_optimistic()
    case setting_key
    # Hrmm, turns out having SccProjectName is no guarantee that both SccLocalPath and SccProvider
    # exist, too... (one project had SccProvider missing). HOWEVER,
    # CMake generator does expect all three to exist when available! Hmm.
    when 'SccProjectName'
      scc_info_out.project_name = setting_value
    # There's a special SAK (Should Already Know) entry marker
    # (see e.g. http://stackoverflow.com/a/6356615 ).
    # Currently I don't believe we need to handle "SAK" in special ways
    # (such as filling it in in case of missing entries),
    # transparent handling ought to be sufficient.
    when 'SccLocalPath'
      scc_info_out.local_path = setting_value
    when 'SccProvider'
      scc_info_out.provider = setting_value
    when 'SccAuxPath'
      scc_info_out.aux_path = setting_value
    else
      found = FOUND_FALSE
    end
    return found
  end
  def parse_post_hook
    super
    if get_project().name.nil?
      # This can be seen e.g. with sbnc.vcxproj
      # (contains RootNamespace and NOT ProjectName),
      # despite sbnc.vcproj containing Name and NOT RootNamespace. WEIRD.
      # Couldn't find any hint how this case should be handled,
      # which setting to adopt then. FIXME check on MSVS.
      parser_error_syntax('missing project name? Adopting root namespace...')
      get_project().name = get_project().root_namespace
    end
  end
end

# Simple forwarder class. Creates specific property group parsers
# and invokes them.
# V2C_VS10PropertyGroupParser / V2C_VS10ItemGroupParser are pretty much identical.
class V2C_VS10PropertyGroupParser < V2C_VS10BaseElemParser
  def parse
    found = be_optimistic()
    propgroup_label = @elem_xml.attributes['Label']
    logger.debug("Label #{propgroup_label}!")
    case propgroup_label
    when 'Configuration'
      target_config_info = V2C_Target_Config_Build_Info.new
      propgroup_parser = V2C_VS10PropertyGroupConfigurationParser.new(@elem_xml, target_config_info)
      propgroup_parser.parse
      get_project().arr_target_config_info.push(target_config_info)
    when 'Globals'
      propgroup_parser = V2C_VS10PropertyGroupGlobalsParser.new(@elem_xml, get_project())
      propgroup_parser.parse
    else
      found = FOUND_FALSE
    end
    # we're a simple forwarder class, thus EVERYTHING is supposed to be "successful" for us
    log_found(found, propgroup_label)
    return found
  end

  private

  def get_project; @info_elem end
end

class V2C_VS10ProjectParser < V2C_VSProjectParserBase

  private

  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'ItemGroup'
      elem_parser = V2C_VS10ItemGroupParser.new(subelem_xml, get_project())
      elem_parser.parse
    when 'ItemDefinitionGroup'
      config_info_curr = V2C_Project_Config_Info.new
      elem_parser = V2C_VS10ItemDefinitionGroupParser.new(subelem_xml, config_info_curr)
      if elem_parser.parse
        get_project().arr_config_info.push(config_info_curr)
      end
    when 'PropertyGroup'
      elem_parser = V2C_VS10PropertyGroupParser.new(subelem_xml, get_project())
      elem_parser.parse
    else
      found = super
    end
    log_found(found, subelem_xml.name)
    return found
  end
end

# Project parser variant which works on XML-stream-based input
class V2C_VS10ProjectFileXmlParser < V2C_VSProjectFileXmlParserBase
  def initialize(doc_proj, arr_projects_out, filters_only)
    super(doc_proj, arr_projects_out)
    @filters_only = filters_only
  end
  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'Project'
      project_info = V2C_Project_Info.new
      elem_parser = V2C_VS10ProjectParser.new(subelem_xml, project_info)
      elem_parser.parse
      get_arr_projects_out().push(project_info)
    else
      found = super
    end
    return found
  end
end

# Project parser variant which works on file-based input
class V2C_VS10ProjectFileParser < V2C_VSProjectFileParserBase
  def initialize(p_parser_proj_file, arr_projects_out, filters_only)
    super(p_parser_proj_file, arr_projects_out)
    @filters_only = filters_only # are we parsing main file or extension file (.filters) only?
  end
  def parse_file
    success = false
    # Parse the project-related file if it exists (_separate_ .filters file in VS10!):
    begin
      File.open(@proj_filename) { |io|
        doc_proj = REXML::Document.new io

        arr_projects_new = Array.new
        @proj_xml_parser = V2C_VS10ProjectFileXmlParser.new(doc_proj, arr_projects_new, @filters_only)
        #super.parse
        @proj_xml_parser.parse
        # Everything ok? Append to output...
        @arr_projects_out.concat(arr_projects_new)
        success = true
      }
    rescue Exception => e
      # File probably does not exist...
      logger.unhandled_exception(e, 'project file parsing')
      raise
    end
    return success
  end
end

class V2C_VS10ProjectFiltersParser < V2C_VS10ParserBase

  private

  def get_project; @info_elem end
  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'ItemGroup'
      # FIXME: _perhaps_ we should pass a boolean to V2C_VS10ItemGroupParser
      # indicating whether we're .vcxproj or .filters.
      # But then VS handling of file elements in .vcxproj and .filters
      # might actually be completely identical, so a boolean split would be
      # counterproductive (TODO verify!).
      elem_parser = V2C_VS10ItemGroupParser.new(subelem_xml, get_project())
    #when 'PropertyGroup'
    #  proj_filters_elem_parser = V2C_VS10PropertyGroupParser.new(subelem_xml, get_project())
    else
      elem_parser = nil
    end
    if not elem_parser.nil?
      elem_parser.parse
    else
      found = super
    end
    return found
  end
end

# Project filters parser variant which works on XML-stream-based input
# The fact that the xmlns= attribute's value of a .filters file
# is _identical_ with the one of a .vcxproj file should be enough proof
# that a .filters file's content is simply a KISS extension of the
# (possibly same) content of a .vcxproj file. IOW, parsing should
# most likely be _identical_ (and thus enhance possibly already added structures!?).
class V2C_VS10ProjectFiltersXmlParser < V2C_VS10ParserBase
  def initialize(doc_proj_filters, arr_projects)
    super(doc_proj_filters, arr_projects)
    @idx_target = 0 # to count the number of <project> elems in the XML stream
    logger.fixme 'filters file exists, needs parsing!'
  end
  def parse_element(subelem_xml)
    found = be_optimistic()
    elem_parser = nil # IMPORTANT: reset it!
    case subelem_xml.name
    when 'Project'
      # FIXME handle fetch() exception - somewhere!
      project_info = get_arr_projects().fetch(@idx_target)
      @idx_target += 1
      elem_parser = V2C_VS10ProjectFiltersParser.new(subelem_xml, project_info)
      elem_parser.parse
    else
      found = super
    end
    return found
  end

  private
  def get_arr_projects; @info_elem end
end

# Project filters parser variant which works on file-based input
class V2C_VS10ProjectFiltersFileParser < V2C_ParserBase
  def initialize(proj_filters_filename, arr_projects_out)
    @proj_filters_filename = proj_filters_filename
    @arr_projects_out = arr_projects_out
  end
  def parse_file
    success = false
    # Parse the file filters file (_separate_ in VS10!)
    # if it exists:
    begin
      File.open(@proj_filters_filename) { |io|
        doc_proj_filters = REXML::Document.new io

        arr_projects_new = Array.new
        project_filters_parser = V2C_VS10ProjectFiltersXmlParser.new(doc_proj_filters, arr_projects_new)
        project_filters_parser.parse
        # Everything ok? Append to output...
        @arr_projects_out.concat(arr_projects_new)
        success = true
      }
    rescue Exception => e
      # File probably does not exist...
      logger.unhandled_exception(e, 'project file parsing')
      raise
    end
    return success
  end
end

# VS10 project files bundle explanation:
# For the relationship between .vcxproj and .vcxproj.filters, the following
# has been experimentally determined:
# The list of ItemGroup element items in a .filters file will be _merged_ with the list of items
# defined by the same ItemGroup of a .vcxproj file (i.e. the array of items may grow),
# however _payload_ of an ItemGroup _item_ in a .filters file
# will completely _destructively override_ a pre-existing ItemGroup item
# defined by the .vcxproj file (i.e. the pre-existing array item will be _replaced_).
# IOW, it seems VS10 parses .filters _after_ having parsed .vcxproj,
# with certain overriding taking place.
class V2C_VS10ProjectFilesBundleParser < V2C_VSProjectFilesBundleParserBase
  def initialize(p_parser_proj_file, arr_projects_out)
    super(p_parser_proj_file, 'MSVS10', arr_projects_out)
  end
  def parse_project_files
    proj_file_parser = V2C_VS10ProjectFileParser.new(@p_parser_proj_file, @arr_projects_out, false)
    proj_filters_file_parser = V2C_VS10ProjectFiltersFileParser.new("#{@proj_filename}.filters", @arr_projects_out)

    if proj_file_parser.parse_file
       puts "FILTERS FILE PARSING DISABLED, TODO!!"
#      proj_filters_file_parser.parse_file
    end
  end
  def check_unhandled_file_types
    # FIXME: we don't handle now externally specified (.props, .targets, .xml files) custom build parts yet!
    check_unhandled_file_type('props')
    check_unhandled_file_type('targets')
    check_unhandled_file_type('xml')
    # Not sure whether we want to evaluate the settings in .user files...
    # (.vcxproj.user in VS10)
    check_unhandled_file_type('user')
  end
end

class V2C_ValidationError < StandardError
end

class V2C_ProjectValidator
  def initialize(project_info)
    @project_info = project_info
  end
  def validate
    validate_project
  end
  private
  def validate_config(target_config_info)
    if target_config_info.cfg_type == V2C_TargetConfig_Defines::CFG_TYPE_INVALID
      validation_error('config type not set!?')
    end
  end
  def validate_target_configs(arr_target_config_info)
    arr_target_config_info.each { |target_config_info|
      validate_config(target_config_info)
    }
  end
  def validate_project
    validate_target_configs(@project_info.arr_target_config_info)
    #log_debug "project data: #{@project_info.inspect}"
    if @project_info.orig_environment_shortname.nil?; validation_error('original environment not set!?') end
    if @project_info.name.nil?; validation_error('name not set!?') end
    # FIXME: Disabled for TESTING only - should re-enable a fileset check once VS10 parsing is complete.
    #if @project_info.main_files.nil?; validation_error('no files!?') end
    arr_config_info = @project_info.arr_config_info
    if arr_config_info.nil? or arr_config_info.empty?
      validation_error('no config information!?')
    end
  end
  def validation_error(str_message)
    raise V2C_ValidationError, "Project #{@project_info.name}: #{str_message}; #{@project_info.inspect}"
  end
end

class Util_TempFilePermanentizer
  MOVE_RES_OK = 1
  MOVE_RES_SAMECONTENT = 3
  MOVE_RES_FAIL_ZEROSIZE = 2

  def initialize(input_file_location, output_file_fqpn, target_file_permissions)
    @input_file_location = input_file_location
    @output_file_fqpn = output_file_fqpn
    @target_file_permissions = target_file_permissions
  end

  def permanentize()
    if have_old_output_file()
      # Move away old file.
      # Usability trick:
      # rename to <file>.<ext>.previous and not <file>.previous.<ext>
      # since grepping for all *.<ext> files would then hit these outdated ones.
      V2C_Util_File.mv(@output_file_fqpn, @output_file_fqpn + '.previous')
    end
    # activate our version
    # We'll choose to chmod() the input rather than the output file,
    # since operations on the output file should better be atomic
    # (a single move, and NOT a subsequent permissions adjustment),
    # to obey potential build tool requirements.
    # [for chmod() comments, see our $v2c_generator_file_create_permissions settings variable]
    V2C_Util_File.chmod(@target_file_permissions, @input_file_location)
    V2C_Util_File.mv(@input_file_location, @output_file_fqpn)
    return MOVE_RES_OK
  end
  def have_old_output_file(); File.exists?(@output_file_fqpn) end
  def permanentize_if_ok_and_different
    configuration_changed = true
    if have_old_output_file()
      if V2C_Util_File.cmp(@input_file_location, @output_file_fqpn)
        configuration_changed = false
      end
    end

    if configuration_changed
      return permanentize()
    else
      return MOVE_RES_SAMECONTENT
    end
  end
  def permanentize_if_nonzero_ok_and_different
    # This can happen in case of ignored exceptions...
    if File.zero?(@input_file_location)
      return MOVE_RES_FAIL_ZEROSIZE
    end
    return permanentize_if_ok_and_different()
  end
end

# Logging-enhanced V2C-specific version.
class V2C_CMakeFilePermanentizer < Util_TempFilePermanentizer
  include Logging

  def initialize(description, input_file_location, output_file_fqpn, target_file_permissions)
    super(input_file_location, output_file_fqpn, target_file_permissions)
    @description = description
  end
  def process
    file_moved = false
    case permanentize_if_nonzero_ok_and_different()
    when Util_TempFilePermanentizer::MOVE_RES_OK
      logger.info "Wrote #{logger.escape_item(@output_file_fqpn)}."
      file_moved = true
    when Util_TempFilePermanentizer::MOVE_RES_SAMECONTENT
      logger.info "No settings changed, #{logger.escape_item(@output_file_fqpn)} not updated."
      # tmpfile will auto-delete when finalized...

      # Some make dependency mechanisms might require touching (timestamping)
      # the unchanged(!) file to indicate that it's up-to-date,
      # however we won't do this here since it's not such a good idea.
      # Any user who needs that should do a manual touch subsequently.
      file_moved = true
    when Util_TempFilePermanentizer::MOVE_RES_FAIL_ZEROSIZE
      logger.error "zero-size candidate file!?!? Skipping replace of output file #{logger.escape_item(@output_file_fqpn)}..."
      file_moved = false
    else
      file_moved = false
    end
  end
end

# Write into temporary file, to avoid corrupting previous
# CMakeLists.txt due to syntax error abort, disk space or failure
# issues. Implement as scoped block operation (ensure closing file,
# since Fileutils.mv on an open file will barf on Windows (XP)).
class V2C_GenerateIntoTempFile
  include Logging
  def initialize(file_description, tempfile_prefix, destination_file)
    @file_description = file_description
    @tempfile_prefix = tempfile_prefix
    @destination_file = destination_file
    textstream_attributes = V2C_TextStream_Attributes.new(
      $v2c_generator_indent_initial_num_spaces,
      $v2c_generator_indent_step,
      $v2c_generator_comments_level
    )
    @textstream_attributes = textstream_attributes
    @file_create_permissions = $v2c_generator_file_create_permissions
  end
  def generate
    tmpfile_path = nil
    Tempfile.open(@tempfile_prefix) { |tmpfile|
      begin
        textOut = V2C_TextStreamSyntaxGeneratorBase.new(tmpfile, @textstream_attributes)
        yield textOut
      rescue Exception => e
        logger.unhandled_exception(e, "while generating #{@file_description}")
        raise
      end
      tmpfile_path = tmpfile.path
    }
    # Since we're forced to fumble our source tree
    # (a definite no-no in all other cases!) by writing our files (CMakeLists.txt etc.) there,
    # use a write-back-when-updated approach to make sure
    # we only write back the live CMakeLists.txt in case anything did change.
    # This is especially important in case of multiple concurrent builds
    # on a shared source on NFS mount.
    mover = V2C_CMakeFilePermanentizer.new(@file_description, tmpfile_path, @destination_file, @file_create_permissions)
    mover.process
  end
end

class V2C_BaseGlobalGenerator
  def initialize(master_project_dir)
    @filename_map_inc = "#{$v2c_config_dir_local}/include_mappings.txt"
    @master_project_dir = master_project_dir
    @map_includes = Hash.new
    read_mappings_includes()
  end

  attr_accessor :map_includes

  private

  def read_mappings_includes
    # These mapping files may contain things such as mapping .vcproj "Vc7/atlmfc/src/mfc"
    # into CMake "SYSTEM ${MFC_INCLUDE}" information.
    read_mappings_combined(@filename_map_inc, @map_includes, @master_project_dir)
  end
end

V2C_TEXT_FILE_AUTO_GENERATED_MARKER = 'AUTO-GENERATED by'
V2C_TEXT_FILE_SKELETON_MARKER = 'source root skeleton file'

class V2C_TextStream_Attributes
  def initialize(indent_start, indent_step, comments_level)
    @indent_start = indent_start
    @indent_step = indent_step
    @comments_level = comments_level
  end
  attr_accessor :indent_start
  attr_accessor :indent_step
  attr_accessor :comments_level
end

# Contains functionality common to _any_ file-based generator
class V2C_TextStreamSyntaxGeneratorBase
  def initialize(out, textstream_attributes)
    @out = out
    @indent_now = textstream_attributes.indent_start
    @indent_step = textstream_attributes.indent_step
    @comments_level = textstream_attributes.comments_level
  end

  def generated_comments_level; @comments_level end

  def get_indent; @indent_now end

  def indent_more; @indent_now += @indent_step end
  def indent_less; @indent_now -= @indent_step end

  def write_data(data)
    @out.puts data
  end
  def write_block(block)
    block.split("\n").each { |line|
      write_line(line)
    }
  end
  def write_line(part)
    @out.print ' ' * get_indent()
    write_data(part)
  end

  def write_empty_line; @out.puts end
  def put_file_header_temporary_marker
    return if $v2c_generator_one_time_conversion_only
    # WARNING: since this comment header is meant to advertise
    # _generated_ vcproj2cmake files, user-side code _will_ check for this
    # particular wording to tell apart generated text files (e.g. CMakeLists.txt)
    # from custom-written ones, thus one should definitely avoid changing
    # this phrase.
    write_data %{\
#
# TEMPORARY Build file, #{V2C_TEXT_FILE_AUTO_GENERATED_MARKER} http://vcproj2cmake.sf.net
# DO NOT CHECK INTO VERSION CONTROL OR APPLY \"PERMANENT\" MODIFICATIONS!!
#

}
  end
end

def string_storage_contains(string_storage, regex)
  return string_storage.grep(regex).any?
end

CMAKELISTS_FILE_TYPE_NONE = 0
CMAKELISTS_FILE_TYPE_ZERO_SIZE = 1
CMAKELISTS_FILE_TYPE_CUSTOM = 2
CMAKELISTS_FILE_TYPE_V2C_ROOT = 3
CMAKELISTS_FILE_TYPE_V2C_LOCAL = 4

CMAKELISTS_AUTO_GENERATED_REGEX_OBJ = /#{V2C_TEXT_FILE_AUTO_GENERATED_MARKER}/
CMAKELISTS_SKELETON_REGEX_OBJ = /#{V2C_TEXT_FILE_SKELETON_MARKER}/
def check_cmakelists_txt_type(str_cmakelists_file_fqpn)

  return CMAKELISTS_FILE_TYPE_NONE if not File.exist?(str_cmakelists_file_fqpn)

  File.open(str_cmakelists_file_fqpn, 'r') { |f_cmakelists|
    lines = f_cmakelists.readlines()
    prior_file_was_generated_by_v2c = string_storage_contains(lines, CMAKELISTS_AUTO_GENERATED_REGEX_OBJ)
    if prior_file_was_generated_by_v2c
      is_skeleton_file = string_storage_contains(lines, CMAKELISTS_SKELETON_REGEX_OBJ)
      return is_skeleton_file ? CMAKELISTS_FILE_TYPE_V2C_ROOT : CMAKELISTS_FILE_TYPE_V2C_LOCAL
    else
      # For zero-size files, the auto-generation marker check above is obviously
      # not delivering a useful result...
      if File.zero?(str_cmakelists_file_fqpn)
        return CMAKELISTS_FILE_TYPE_ZERO_SIZE
      else
        return CMAKELISTS_FILE_TYPE_CUSTOM
      end
    end
  }
end

class V2C_GeneratorError < StandardError
end

class V2C_GeneratorBase < V2C_LoggerBase
  def generator_error(str_description); logger.error(str_description) end
end

class V2C_SyntaxGeneratorBase < V2C_GeneratorBase
  COMMENT_LEVEL_OFF = 0 # no comments generated
  COMMENT_LEVEL_MINIMUM = 1 # minimum amount of comments
  COMMENT_LEVEL_STANDARD = 2 # standard setting
  COMMENT_LEVEL_VERBOSE = 3 # verbose mode - even more comments
  COMMENT_LEVEL_ALL = 4 # highly verbose, many comments
  def initialize(textOut)
    @textOut = textOut
  end
  def ensure_string_nonempty(str_test)
    if str_test.nil? or str_test.empty?
      raise V2C_GeneratorError, 'detected invalid string'
    end
  end
  def error_unknown_case_value(description, val)
    raise V2C_GeneratorError, "unknown/unsupported/corrupt #{description} case value! (#{val})"
  end
end

# @brief CMake syntax generator base class.
#        Strictly about converting requests into specific CMake syntax,
#        no build-specific generator knowledge at this level!
class V2C_CMakeSyntaxGenerator < V2C_SyntaxGeneratorBase
  CMAKE_IS_LIST_VAR_CONTENT_REGEX_OBJ = %r{^".*;.*"$}
  CMAKE_VAR_MATCH_REGEX_STR = '\\$\\{[[:alnum:]_]+\\}'
  CMAKE_ENV_VAR_MATCH_REGEX_STR = '\\$ENV\\{[[:alnum:]_]+\\}'
  WHITESPACE_REGEX_OBJ = %r{\s}

  def next_paragraph()
    @textOut.write_empty_line()
  end
  # debug helper, to help figuring out
  # which part within the generator is generating which lines.
  def print_marker_line(line)
    # write_comment_line(line) # UNCOMMENT THIS CALL IF NEEDED
  end
  def write_comment_line(line); @textOut.write_line("# #{line}") end
  def write_comment_at_level(level, block)
    return if @textOut.generated_comments_level() < level
    # Since we'd like the start of a comment paragraph to start with
    # an upper-case char, perhaps we should check against that and warn.
    block.split("\n").each { |line|
      write_comment_line(line)
    }
  end
  # TODO: ideally we would do single-line/multi-line splitting operation _automatically_
  # (and bonus points for configurable line length...)
  def write_command_list(cmake_command, cmake_command_arg, arr_elems)
    if cmake_command_arg.nil?; cmake_command_arg = '' end
    @textOut.write_line("#{cmake_command}(#{cmake_command_arg}")
    @textOut.indent_more()
      arr_elems.each do |curr_elem|
        @textOut.write_line(curr_elem)
      end
    @textOut.indent_less()
    @textOut.write_line(')')
  end
  def write_command_list_quoted(cmake_command, cmake_command_arg, arr_elems)
    cmake_command_arg_quoted = element_handle_quoting(cmake_command_arg) if not cmake_command_arg.nil?
    arr_elems_quoted = Array.new
    arr_elems.each do |curr_elem|
      # HACK for nil input of SCC info.
      if curr_elem.nil?; curr_elem = '' end
      arr_elems_quoted.push(element_handle_quoting(curr_elem))
    end
    write_command_list(cmake_command, cmake_command_arg_quoted, arr_elems_quoted)
  end
  def write_command_single_line(cmake_command, str_cmake_command_args)
    @textOut.write_line("#{cmake_command}(#{str_cmake_command_args})")
  end
  def write_command_list_single_line(cmake_command, arr_args_cmd)
    str_cmake_command_args = arr_args_cmd.join(' ')
    write_command_single_line(cmake_command, str_cmake_command_args)
  end
  def write_list(list_var_name, arr_elems)
    write_command_list('set', list_var_name, arr_elems)
  end
  def write_list_quoted(list_var_name, arr_elems)
    write_command_list_quoted('set', list_var_name, arr_elems)
  end
  # Special helper to invoke functions which act on a specific object
  # (e.g. target) given as first param.
  def write_invoke_config_object_function_quoted(str_function, str_object, arr_args_func)
    write_command_list_quoted(str_function, str_object, arr_args_func)
  end
  # Special helper to invoke custom user-defined functions.
  def write_invoke_function_quoted(str_function, arr_args_func)
    write_command_list_quoted(str_function, nil, arr_args_func)
  end
  def get_dereferenced_variable_name(str_var); "${#{str_var}}" end
  def add_subdirectory(str_subdir)
    # quote strings containing spaces!!
    str_subdir_quoted = element_handle_quoting(str_subdir)
    write_command_single_line('add_subdirectory', str_subdir_quoted)
  end

  def get_var_conditional_command(command_name); "COMMAND #{command_name}" end

  def get_conditional_inverted(str_conditional); "NOT #{str_conditional}" end
  # WIN32, MSVC, ...
  def write_conditional_if(str_conditional)
    return if str_conditional.nil?
    write_command_single_line('if', str_conditional)
    @textOut.indent_more()
  end
  def write_conditional_else(str_conditional)
    return if str_conditional.nil?
    @textOut.indent_less()
    write_command_single_line('else', str_conditional)
    @textOut.indent_more()
  end
  def write_conditional_end(str_conditional)
    return if str_conditional.nil?
    @textOut.indent_less()
    write_command_single_line('endif', str_conditional)
  end
  # http://www.cmake.org/Wiki/CMake/Language_Syntax says
  # one can use any of TRUE/FALSE, ON/OFF, YES/NO,
  # thus we'll obviously choose the shortest solution.
  def get_keyword_bool(setting); setting ? 'ON' : 'OFF' end
  def write_set_var(var_name, setting)
    write_command_list('set', var_name, [ setting ])
  end
  def write_set_var_bool(var_name, setting)
    write_set_var(var_name, get_keyword_bool(setting))
  end
  def write_set_var_bool_conditional(var_name, str_condition)
    write_conditional_if(str_condition)
      write_set_var_bool(var_name, true)
    write_conditional_else(str_condition)
      write_set_var_bool(var_name, false)
    write_conditional_end(str_condition)
  end
  def write_set_var_if_unset(var_name, setting)
    str_conditional = get_conditional_inverted(var_name)
    write_conditional_if(str_conditional)
      write_set_var(var_name, setting)
    write_conditional_end(str_conditional)
  end
  # Hrmm, I'm currently unsure whether there _should_ in fact
  # be any difference between write_set_var() and write_set_var_quoted()...
  def write_set_var_quoted(var_name, setting)
    write_command_list_quoted('set', var_name, [ setting ])
  end
  def write_include(include_file, optional = false)
    arr_args_include_file = [ element_handle_quoting(include_file) ]
    arr_args_include_file.push('OPTIONAL') if optional
    write_command_list('include', nil, arr_args_include_file)
  end
  def write_include_from_cmake_var(include_file_var, optional = false)
    write_include(get_dereferenced_variable_name(include_file_var), optional)
  end
  def write_cmake_minimum_version(str_cmake_minimum_version)
    ensure_string_nonempty(str_cmake_minimum_version)
    write_command_single_line('cmake_minimum_required', "VERSION #{str_cmake_minimum_version}")
  end
  def write_cmake_policy(policy_num, set_to_new, comment) # comment parm better not default-nil (enforce commenting)
    str_policy = '%s%04d' % [ 'CMP', policy_num ]
    str_conditional = "POLICY #{str_policy}"
    write_conditional_if(str_conditional)
      if not comment.nil?
        write_comment_at_level(COMMENT_LEVEL_VERBOSE, comment)
      end
      str_OLD_NEW = set_to_new ? 'NEW' : 'OLD'
      arr_args_set_policy = [ 'SET', str_policy, str_OLD_NEW ]
      write_command_list_single_line('cmake_policy', arr_args_set_policy)
    write_conditional_end(str_conditional)
  end
  def put_source_group(source_group_name, arr_filters, source_files_variable)
    arr_elems = Array.new
    if not arr_filters.nil?
      # WARNING: need to keep as separate array elements (whitespace separator would lead to bogus quoting!)
      # And _need_ to keep manually quoted,
      # since we receive this as a ;-separated list and need to pass it on unmodified.
      str_regex_list = array_to_cmake_list(arr_filters)
      arr_elems.push('REGULAR_EXPRESSION', str_regex_list)
    end
    arr_elems.push('FILES', get_dereferenced_variable_name(source_files_variable))
    # Use multi-line method since source_group() arguments can be very long.
    write_command_list_quoted('source_group', source_group_name, arr_elems)
  end
  def put_include_directories(target_name, arr_directories, flags)
    arr_args = Array.new
    arr_args.push('SYSTEM') if (flags & V2C_Include_Dir_Defines::SYSTEM > 0)
    arr_args.push('BEFORE') if (flags & V2C_Include_Dir_Defines::BEFORE > 0)
    arr_args.concat(arr_directories)
    gen_put_include_directories(target_name, arr_args)
  end
  # analogous to CMake separate_arguments() command
  def separate_arguments(array_in); array_in.join(';') end

  # Hrmm, I'm not quite happy about this helper's location and
  # purpose. Probably some hierarchy is not really clean.
  def prepare_string_literal(str_in)
    return element_handle_quoting(str_in)
  end
  private

  def element_manual_quoting(elem)
    return "\"#{elem}\""
  end
  def array_to_cmake_list(arr_elems)
    return element_manual_quoting(arr_elems.join(';'))
  end
  # (un)quote strings as needed
  #
  # Once we added a variable in the string,
  # we definitely _need_ to have the resulting full string quoted
  # in the generated file, otherwise we won't obey
  # CMake filesystem whitespace requirements! (string _variables_ _need_ quoting)
  # However, there is a strong argument to be made for applying the quotes
  # on the _generator_ and not _parser_ side, since it's a CMake syntax attribute
  # that such strings need quoting.
  CMAKE_STRING_NEEDS_QUOTING_REGEX_OBJ = %r{[^\}\s]\s|\s[^\s\$]|^$}
  CMAKE_STRING_HAS_QUOTES_REGEX_OBJ = %r{".*"}
  CMAKE_STRING_QUOTED_CONTENT_MATCH_REGEX_OBJ = %r{"(.*)"}
  def element_handle_quoting(elem)
    # Determine whether quoting needed
    # (in case of whitespace or variable content):
    #if elem.match(/\s|#{CMAKE_VAR_MATCH_REGEX_STR}|#{CMAKE_ENV_VAR_MATCH_REGEX_STR}/)
    # Hrmm, turns out that variables better should _not_ be quoted.
    # But what we _do_ need to quote is regular strings which include
    # whitespace characters, i.e. check for alphanumeric char following
    # whitespace or the other way around.
    # Quoting rules seem terribly confusing, will need to revisit things
    # to get it all precisely correct.
    # For details, see REF_QUOTING: "Quoting" http://www.itk.org/Wiki/CMake/Language_Syntax#Quoting
    content_needs_quoting = false
    has_quotes = false
    # "contains at least one whitespace character,
    # and then prefixed or followed by any non-whitespace char value"
    # Well, that's not enough - consider a concatenation of variables
    # such as
    # ${v1} ${v2}
    # which should NOT be quoted (whereas ${v1} ascii ${v2} should!).
    # As a bandaid to detect variable syntax, make sure to skip
    # closing bracket/dollar sign as well.
    # And an empty string needs quoting, too!!
    # (this empty content might be a counted parameter of a function invocation,
    # in which case unquoted syntax would implicitly throw away that empty parameter!
    if CMAKE_STRING_NEEDS_QUOTING_REGEX_OBJ.match(elem)
      content_needs_quoting = true
    end
    if CMAKE_STRING_HAS_QUOTES_REGEX_OBJ.match(elem)
      has_quotes = true
    end
    needs_quoting = (content_needs_quoting and not has_quotes)
    #puts "QUOTING: elem #{elem} content_needs_quoting #{content_needs_quoting} has_quotes #{has_quotes} needs_quoting #{needs_quoting}"
    if needs_quoting
      #puts 'QUOTING: do quote!'
      return element_manual_quoting(elem)
    end
    if has_quotes
      if not content_needs_quoting
        is_list = elem_is_cmake_list(elem)
        needs_unquoting = (not is_list)
        if needs_unquoting
          #puts 'QUOTING: do UNquoting!'
          return elem.sub(CMAKE_STRING_QUOTED_CONTENT_MATCH_REGEX_OBJ, '\1')
        end
      end
    end
    #puts 'QUOTING: do no changes!'
    return elem
  end
  # Do we have a string such as "aaa;bbb" ?
  def elem_is_cmake_list(str_elem)
    # Warning: String.start_with?/end_with? cannot be used (new API)
    # And using index() etc. for checking of start/end '"' and ';'
    # is not very useful either, thus use a combined match().
    #return (not (str_elem.match(CMAKE_IS_LIST_VAR_CONTENT_REGEX_OBJ) == nil))
    return CMAKE_IS_LIST_VAR_CONTENT_REGEX_OBJ.match(str_elem)
  end
  def util_flatten_string(in_string)
    return in_string.gsub(WHITESPACE_REGEX_OBJ, '_')
  end
  def get_config_name_upcase(config_name)
    # need to also convert config names with spaces into underscore variants, right?
    config_name.clone.upcase.tr(' ','_')
  end
  def get_name_of_per_config_type_property(property_name, config_name)
    if config_name.nil?
      res = property_name
    else
      config_name_upper = get_config_name_upcase(config_name)
      res = "#{property_name}_#{config_name_upper}"
    end
    return res
  end
  COMPILE_DEF_NEEDS_CMAKE_ESCAPING_REGEX_OBJ = %r{[\(\)]+}
  def cmake_escape_compile_definitions(arr_compile_defn)
    arr_compile_defn.collect do |compile_defn|
      # Need to escape the value part of the key=value definition:
      if COMPILE_DEF_NEEDS_CMAKE_ESCAPING_REGEX_OBJ.match(compile_defn)
        escape_char(compile_defn, '\\(')
        escape_char(compile_defn, '\\)')
      end
      compile_defn
    end
  end
end

# @brief V2C_CMakeV2CSyntaxGenerator isn't supposed to be a base class
# of other CMake generator classes, but rather a _member_ of those classes only.
# Reasoning: that class implements the border crossing towards specific CMake syntax,
# i.e. it is the _only one_ to know specific CMake syntax (well, "ideally", I have to say, currently).
# If it was the base class of the various CMake generators,
# then it would be _hard-coded_ i.e. not configurable (which would be the case
# when having ctor parameterisation from the outside).
# This class derived from base contains extended functions
# that aren't strictly about CMake syntax generation any more
# (i.e., some build-specific configuration content).
class V2C_CMakeV2CSyntaxGeneratorBase < V2C_CMakeSyntaxGenerator
  VCPROJ2CMAKE_FUNC_CMAKE = 'vcproj2cmake_func.cmake'
  V2C_ATTRIBUTE_NOT_PROVIDED_MARKER = 'V2C_NOT_PROVIDED' # WARNING KEEP IN SYNC: that exact string literal is being checked by vcproj2cmake_func.cmake!
  V2C_ALL_PLATFORMS_MARKER = 'ALL'
  def write_vcproj2cmake_func_comment()
    write_comment_at_level(COMMENT_LEVEL_STANDARD, "See function implementation/docs in #{$v2c_module_path_root}/#{VCPROJ2CMAKE_FUNC_CMAKE}")
  end
  def put_converter_script_location(script_location_relative_to_master)
    return if $v2c_generator_one_time_conversion_only

    if script_location_relative_to_master.nil?
      generator_error('converter script location missing!?')
    end

    # For the CMakeLists.txt rebuilder (automatic rebuild on file changes),
    # add handling of a script file location variable, to enable users
    # to override the script location if needed.
    next_paragraph()
    # NOTE: we'll make V2C_SCRIPT_LOCATION express its path via
    # relative argument to global V2C_MASTER_PROJECT_SOURCE_DIR (i.e. CMAKE_SOURCE_DIR)
    # and _not_ CMAKE_CURRENT_SOURCE_DIR,
    # (this provision should even enable people to manually relocate
    # an entire sub project within the source tree).
    v2c_converter_script_location = "${V2C_MASTER_PROJECT_SOURCE_DIR}/#{script_location_relative_to_master}"
    gen_put_converter_script_location(v2c_converter_script_location)
  end
  def put_include_dir_project_source_dir(target_name)
    # AFAIK .vcproj implicitly adds the project root to standard include path
    # (for automatic stdafx.h resolution etc.), thus add this
    # (and make sure to add it with high priority, i.e. use BEFORE).
    # For now sitting in LocalGenerator and not per-target handling since this setting is valid for the entire directory.
    next_paragraph()
    arr_directories = [ get_dereferenced_variable_name('PROJECT_SOURCE_DIR') ]
    put_include_directories(target_name, arr_directories, V2C_Include_Dir_Defines::BEFORE)
  end
  def write_invoke_config_object_v2c_function_quoted(str_function, str_object, arr_args_func)
    write_vcproj2cmake_func_comment()
    write_invoke_config_object_function_quoted(str_function, str_object, arr_args_func)
  end
  def write_invoke_v2c_function_quoted(str_function, arr_args_func)
    write_vcproj2cmake_func_comment()
    write_invoke_function_quoted(str_function, arr_args_func)
  end
  def put_v2c_hook_invoke(str_filename)
      write_invoke_v2c_function_quoted('v2c_hook_invoke', [ str_filename ])
  end
  def put_customization_hook(include_file)
    return if $v2c_generator_one_time_conversion_only
    gen_put_customization_hook(include_file)
  end
  def put_customization_hook_from_cmake_var(include_file_var)
    return if $v2c_generator_one_time_conversion_only
    gen_put_customization_hook_from_cmake_var(include_file_var)
  end
  def put_customization_hook_commented_from_cmake_var(include_file_var, comment_level, comment)
    return if $v2c_generator_one_time_conversion_only
    write_comment_at_level(comment_level, comment)
    put_customization_hook_from_cmake_var(include_file_var)
  end
  # Hrmm, I'm not quite sure yet where to aggregate this function...
  #
  # In most cases this function will be called internally within methods
  # which generate calls to our vcproj2cmake_func.cmake helpers,
  # so that these helpers can switch fully internally between
  # either generating CMake calls
  # (passing platform / build type parameters as gathered from condition)
  # or (in self-contained mode) instead using the result of this function
  # to add an open-coded CMake "if(CONDITIONAL)".
  def get_buildcfg_var_name_of_condition(condition)
    # HACK: very Q&D handling, to make things work quickly.
    # Should think of implementing a proper abstraction for handling of conditions.
    # Probably we _at least_ need to create a _condition generator_ class.

    # Hrmm, for now we'll abuse a method at the V2C_Info_Condition class,
    # but I'm not convinced at all that this is how things should be structured.
    build_type = condition.get_build_type()
    platform_name = condition.get_build_platform()
    var_name = nil
    if not build_type.nil? and not platform_name.nil?
      # Name may contain spaces - need to handle them!
      build_type_flattened = util_flatten_string(build_type)
      platform_name_flattened = util_flatten_string(platform_name)
      var_name = "v2c_want_buildcfg_platform_#{platform_name_flattened}_build_type_#{build_type_flattened}"
    end
    return var_name
  end
  def parse_platform_conversions_internal(platform_defs, arr_defs, map_defs, skip_failed_lookups)
    arr_defs.each { |curr_defn|
      #log_debug map_defs[curr_defn]
      map_line = map_defs[curr_defn]
      if map_line.nil?
        # hmm, no direct match! Try to figure out whether any map entry
        # is a regex which would match our curr_defn
        hash_ensure_sorted_each(map_defs).each do |key_regex, value|
          if curr_defn =~ /^#{key_regex}$/
            log_debug "KEY: #{key_regex} curr_defn #{curr_defn}"
            map_line = value
            break
          end
        end
      end
      if map_line.nil?
        # no mapping? --> unconditionally use the original define
        if true != skip_failed_lookups
          push_platform_defn(platform_defs, V2C_ALL_PLATFORMS_MARKER, curr_defn)
        end
      else
        # Tech note: chomp on map_line should not be needed as long as
        # original _constant_ input has already been pre-treated (chomped).
        map_line.split('|').each do |platform_element|
          #log_debug "platform_element #{platform_element}"
          platform, replacement_defn = platform_element.split('=')
          if platform.empty?
            # specified a replacement without a specific platform?
            # ("tag:=REPLACEMENT")
            # --> unconditionally use it!
            platform = V2C_ALL_PLATFORMS_MARKER
          else
            replacement_defn ||= curr_defn
          end
          push_platform_defn(platform_defs, platform, replacement_defn)
        end
      end
    }
  end
  def parse_platform_conversions(platform_defs, arr_defs, map_defs, skip_failed_lookups)
    platform_defs_raw = Hash.new
    parse_platform_conversions_internal(platform_defs_raw, arr_defs, map_defs, skip_failed_lookups)
    platform_defs_raw.each do |key, arr_platdefs|
      #logger.info "arr_platdefs: #{arr_platdefs}"
      next if arr_platdefs.empty?
      arr_platdefs.uniq!
      platform_defs[key] = arr_platdefs
    end
    #hash_ensure_sorted(platform_defs)
  end

  V2C_COMPILER_MSVC_REGEX_OBJ = %r{^MSVC}
  def map_compiler_name_to_cmake_platform_conditional(compiler_name)
    str_conditional_compiler_platform = nil
    # For a number of platform indentifier variables,
    # see "CMake Useful Variables" http://www.cmake.org/Wiki/CMake_Useful_Variables
    case compiler_name
    when V2C_COMPILER_MSVC_REGEX_OBJ
      str_conditional_compiler_platform = 'MSVC'
    else
      logger.unhandled_functionality "unknown (unsupported) compiler name #{compiler_name}!"
    end
    return str_conditional_compiler_platform
  end
  def map_linker_name_to_cmake_platform_conditional(linker_name)
    # For now, let's assume that compiler / linker name mappings are the same:
    # BTW, we probably don't have much use for the CMAKE_LINKER variable anywhere, right?
    return map_compiler_name_to_cmake_platform_conditional(linker_name)
  end
  def do_configure_atl_mfc_flag(target_name, condition, use_of_atl, use_of_mfc)
    # CMAKE_MFC_FLAG setting is supposed to be done _before_
    # a target gets created (via add_executable() etc.).
    #
    # Hmm, do we need to actively _reset_ CMAKE_MFC_FLAG / CMAKE_ATL_FLAG
    # (i.e. _unconditionally_ set() it, even if it's 0),
    # since projects in subdirs shouldn't inherit?
    # Given the discussion at
    # "[CMake] CMAKE_MFC_FLAG is inherited in subdirectory ?"
    #   http://www.cmake.org/pipermail/cmake/2009-February/026896.html
    # I'd strongly assume yes...
    # See also "Re: [CMake] CMAKE_MFC_FLAG not working in functions"
    #   http://www.mail-archive.com/cmake@cmake.org/msg38677.html

    if 1 == $v2c_generate_self_contained_file
      var_v2c_want_buildcfg_curr = get_buildcfg_var_name_of_condition(condition)
      write_conditional_if(var_v2c_want_buildcfg_curr)
        #if use_of_mfc > V2C_TargetConfig_Defines::MFC_FALSE
          write_set_var('CMAKE_MFC_FLAG', use_of_mfc)
        #end
        # ok, there's no CMAKE_ATL_FLAG yet, AFAIK, but still prepare
        # for it (also to let people probe on this in hook includes)
        # FIXME: since this flag does not exist yet yet MFC sort-of
        # includes ATL configuration, perhaps as a workaround one should
        # set the MFC flag if use_of_atl is true?
        #if use_of_atl > 0
          # TODO: should also set the per-configuration-type variable variant
          write_set_var('CMAKE_ATL_FLAG', use_of_atl)
        #end
      write_conditional_end(var_v2c_want_buildcfg_curr)
    else
      arr_args_func = [ use_of_atl.to_s(), use_of_mfc.to_s() ]
      write_invoke_object_conditional_v2c_function('v2c_local_set_cmake_atl_mfc_flags', target_name, condition, arr_args_func)
    end
  end
  def write_invoke_object_conditional_v2c_function(str_function, object_name, condition, arr_args_func_other)
    arr_args_func = [
      prepare_string_literal(condition.get_build_platform()),
      prepare_string_literal(condition.get_build_type())
    ]
    arr_args_func.concat(arr_args_func_other)
    write_invoke_config_object_v2c_function_quoted(str_function, object_name, arr_args_func)
  end
end

class V2C_CMakeV2CSyntaxGeneratorV2CFunc < V2C_CMakeV2CSyntaxGeneratorBase
  private
  def gen_put_customization_hook(include_file)
    put_v2c_hook_invoke(include_file)
  end
  def gen_put_customization_hook_from_cmake_var(include_file_var)
    put_v2c_hook_invoke(get_dereferenced_variable_name(include_file_var))
  end
  def gen_put_include_directories(target_name, arr_args)
    write_command_list_quoted('v2c_target_include_directories', target_name, arr_args)
  end
  def gen_put_converter_script_location(script_location)
    write_invoke_v2c_function_quoted('v2c_converter_script_set_location', [ script_location ])
  end
end

# class variant which is supposed to create a self-contained file
# (i.e. one which does not rely on our V2C functions module).
# Currently this most certainly does not work fully.
class V2C_CMakeV2CSyntaxGeneratorSelfContained < V2C_CMakeV2CSyntaxGeneratorBase
  private
  def gen_put_customization_hook(include_file)
    write_include(include_file, true)
  end
  def gen_put_customization_hook_from_cmake_var(include_file_var)
    write_include_from_cmake_var(include_file_var, true)
  end
  def gen_put_include_directories(target_name, arr_args)
    write_command_list_quoted('include_directories', nil, arr_args)
  end
  def gen_put_converter_script_location(script_location)
    write_comment_at_level(COMMENT_LEVEL_MINIMUM,
      "User override mechanism (don't prevent specifying a custom location of this script)"
    )
    write_set_var_if_unset('V2C_SCRIPT_LOCATION', element_manual_quoting(script_location))
  end
end

if 1 == $v2c_generate_self_contained_file
  class V2C_CMakeV2CSyntaxGenerator < V2C_CMakeV2CSyntaxGeneratorSelfContained
  end
else
  class V2C_CMakeV2CSyntaxGenerator < V2C_CMakeV2CSyntaxGeneratorV2CFunc
  end
end

class V2C_CMakeFileListGeneratorBase < V2C_CMakeV2CSyntaxGenerator
  VS7_UNWANTED_FILE_TYPES_REGEX_OBJ = %r{\.(lex|y|ico|bmp|txt)$}
  VS7_LIB_FILE_TYPES_REGEX_OBJ = %r{\.lib$}
  def initialize(textOut, project_name, project_dir, arr_sub_sources_for_parent)
    super(textOut)
    @project_name = project_name
    @project_dir = project_dir
    @arr_sub_sources_for_parent = arr_sub_sources_for_parent
  end
  def filter_files(arr_file_infos)
    arr_local_sources = nil
    if not arr_file_infos.nil?
      arr_local_sources = Array.new
      arr_file_infos.each { |file|
        f = file.path_relative

	v2c_generator_check_file_accessible(@project_dir, f, 'file item in project', @project_name, ($v2c_validate_vcproj_abort_on_error > 0))

        # Ignore all generated files, for now.
        if true == file.is_generated
          logger.fixme "#{@info_file.path_relative} is a generated file - skipping!"
          next # no complex handling, just skip
        end

        ## Ignore header files
        #return if f =~ /\.(h|H|lex|y|ico|bmp|txt)$/
        # No we should NOT ignore header files: if they aren't added to the target,
        # then VS won't display them in the file tree.
        next if VS7_UNWANTED_FILE_TYPES_REGEX_OBJ.match(f)

        # Verbosely ignore .lib "sources"
        if VS7_LIB_FILE_TYPES_REGEX_OBJ.match(f)
          # probably these entries are supposed to serve as dependencies
          # (i.e., non-link header-only include dependency, to ensure
          # rebuilds in case of foreign-library header file changes).
          # Not sure whether these were added by users or
          # it's actually some standard MSVS mechanism... FIXME
          logger.info "#{@project_name}::#{f} registered as a \"source\" file!? Skipping!"
          next # no complex handling, just skip
        end

        arr_local_sources.push(f)
      }
    end
    return arr_local_sources
  end
  def write_sources_list(source_list_name, arr_sources, var_prefix = 'SOURCES_files_')
    source_files_variable = "#{var_prefix}#{source_list_name}"
    write_list_quoted(source_files_variable, arr_sources)
    return source_files_variable
  end
  # Side note: we will NOT prefix source variables within a newly
  # generated CMakeLists.txt with V2C_[TARGET NAME],
  # since they are re-created in each newly generated CMakeLists.txt,
  # so it's no problem, and hook script will need to precisely know
  # which variable to modify, which would be a problem.......
  def register_new_source_list_variable(sources_variable)
    @arr_sub_sources_for_parent.push(sources_variable)
  end
end

# FIXME: temporarily appended a _VS7 suffix since we're currently changing file list generation during our VS10 generator work.
class V2C_CMakeFileListsGenerator_VS7 < V2C_CMakeFileListGeneratorBase
  def initialize(textOut, project_name, project_dir, files_str, parent_source_group, arr_sub_sources_for_parent)
    super(textOut, project_name, project_dir, arr_sub_sources_for_parent)
    @files_str = files_str
    @parent_source_group = parent_source_group
  end
  def generate; put_file_list_recursive(@files_str, @parent_source_group, @arr_sub_sources_for_parent) end

  # Hrmm, I'm not quite sure yet where to aggregate this function...
  def get_filter_group_name(filter_info); return filter_info.nil? ? 'COMMON' : filter_info.name; end

  # Related TODO item: for .cpp files which happen to be listed as
  # include files in their native projects, we should likely
  # explicitly set the HEADER_FILE_ONLY property (note that for .h files,
  # man cmakeprops seems to say that CMake
  # will _implicitly_ configure these correctly).
  VS7_UNWANTED_GROUP_TAG_CHARS_MATCH_REGEX_OBJ = %r{( |\\)}
  def put_file_list_recursive(files_str, parent_source_group, arr_sub_sources_for_parent)
    filter_info = files_str[:filter_info]
    group_name = get_filter_group_name(filter_info)
      log_debug("#{self.class.name}: #{group_name}")
    if not files_str[:arr_sub_filters].nil?
      arr_sub_filters = files_str[:arr_sub_filters]
    end
    arr_file_infos = files_str[:arr_file_infos]

    arr_local_sources = filter_files(arr_file_infos)

    # TODO: CMake is said to have a weird bug in case of parent_source_group being "Source Files":
    # "Re: [CMake] SOURCE_GROUP does not function in Visual Studio 8"
    #   http://www.mail-archive.com/cmake@cmake.org/msg05002.html
    if parent_source_group.nil?
      this_source_group = ''
    else
      if parent_source_group == ''
        this_source_group = group_name
      else
        this_source_group = "#{parent_source_group}\\\\#{group_name}"
      end
    end

    # process sub-filters, have their main source variable added to arr_my_sub_sources
    arr_my_sub_sources = Array.new
    if not arr_sub_filters.nil?
      @textOut.indent_more()
        arr_sub_filters.each { |subfilter|
          #logger.info "writing: #{subfilter}"
          put_file_list_recursive(subfilter, this_source_group, arr_my_sub_sources)
        }
      @textOut.indent_less()
    end

    source_group_var_suffix = this_source_group.clone.gsub(VS7_UNWANTED_GROUP_TAG_CHARS_MATCH_REGEX_OBJ,'_')

    # process our hierarchy's own files
    if not arr_local_sources.nil?
      source_files_variable = write_sources_list(source_group_var_suffix, arr_local_sources)
      # create source_group() of our local files
      if not parent_source_group.nil?
        # use list of filters if available: have it generated as source_group(REGULAR_EXPRESSION "regex" ...).
        arr_filters = nil
        if not filter_info.nil?
          arr_filters = filter_info.arr_scfilter
        end
        put_source_group(this_source_group, arr_filters, source_files_variable)
      end
    end
    if not source_files_variable.nil? or not arr_my_sub_sources.empty?
      sources_variable = "SOURCES_#{source_group_var_suffix}"
      # dump sub filters...
      arr_source_vars = arr_my_sub_sources.collect { |sources_elem|
        get_dereferenced_variable_name(sources_elem)
      }
      # ...then our own files
      if not source_files_variable.nil?
        arr_source_vars.push(get_dereferenced_variable_name(source_files_variable))
      end
      next_paragraph()
      write_list_quoted(sources_variable, arr_source_vars)

      # add our source list variable to parent return
      # FIXME: cannot use register_new_source_list_variable()  (base class) yet -
      # we're doing our own inner recursion with _changing_ variables!
      arr_sub_sources_for_parent.push(sources_variable)
    end
  end
end

class V2C_CMakeFileListGenerator_VS10 < V2C_CMakeFileListGeneratorBase
  def initialize(textOut, project_name, project_dir, file_list, parent_source_group, arr_sub_sources_for_parent)
    super(textOut, project_name, project_dir, arr_sub_sources_for_parent)
    @file_list = file_list
    @parent_source_group = parent_source_group
  end
  def generate; put_file_list(@file_list) end

  private

  def put_file_list(file_list)
    arr_local_sources = filter_files(file_list.arr_files)
    source_files_variable = write_sources_list(file_list.name, arr_local_sources)
    register_new_source_list_variable(source_files_variable)
  end
end

class V2C_CMakeProjectTargetGenerator < V2C_CMakeV2CSyntaxGenerator
  def initialize(target, project_dir, localGenerator, textOut)
    super(textOut)
    @target = target
    @project_dir = project_dir
    @localGenerator = localGenerator
  end

  # These configuration types (Debug, Release) may be _different_
  # in each .vc[x]proj file, thus it's a target generator functionality
  # and _not_ a functionality of the local generator (which may generate
  # *multiple* project targets!).
  def generate_assignments_of_build_type_variables(arr_config_info)
    # ARGH, we have an issue with CMake not being fully up to speed with
    # multi-configuration generators (e.g. .vcproj/.vcxproj):
    # it should be able to declare _all_ configuration-dependent settings
    # in a .vcproj file as configuration-dependent variables
    # (just like set_property(... COMPILE_DEFINITIONS_DEBUG ...)),
    # but with configuration-specific(!) include directories on .vcproj side,
    # there's currently only a _generic_ include_directories() command :-(
    # (dito with target_link_libraries() - or are we supposed to create an imported
    # target for each dependency, for more precise configuration-specific library names??)
    # Thus we should specifically specify include_directories() where we can
    # discern the configuration type (in single-configuration generators using
    # CMAKE_BUILD_TYPE) and - in the case of multi-config generators - pray
    # that the authoritative configuration has an AdditionalIncludeDirectories setting
    # that matches that of all other configs, since we're unable to specify
    # it in a configuration-specific way :(
    # Well, in that case we should simply resort to generating
    # the _union_ of all include directories of all configurations...
    # "Re: [CMake] debug/optimized include directories"
    #   http://www.mail-archive.com/cmake@cmake.org/msg38940.html
    # is a long discussion of this severe issue.
    # Probably the best we can do is to add a function to add to vcproj2cmake_func.cmake which calls either raw include_directories() or sets the future
    # target property, depending on a pre-determined support flag
    # for proper include dirs setting.

    # HACK global var (multi-thread unsafety!)
    # Thus make sure to have a local copy, for internal modifications.
    config_multi_authoritative = $config_multi_authoritative
    if config_multi_authoritative.empty?
      # Hrmm, we used to fetch this via REXML next_element,
      # which returned the _second_ setting (index 1)
      # i.e. Release in a certain file,
      # while we now get the first config, Debug, in that file.
      config_multi_authoritative = arr_config_info[0].condition.get_build_type()
    end

    if 1 == $v2c_generate_self_contained_file
      arr_config_info.each { |config_info_curr|
        condition = config_info_curr.condition
        build_type = condition.get_build_type()
        build_type_cooked = prepare_string_literal(build_type)
        str_cmake_build_type_condition = ''
        if config_multi_authoritative == build_type
          str_cmake_build_type_condition = "CMAKE_CONFIGURATION_TYPES OR CMAKE_BUILD_TYPE STREQUAL #{build_type_cooked}"
        else
          # YES, this condition is supposed to NOT trigger in case of a multi-configuration generator
          str_cmake_build_type_condition = "CMAKE_BUILD_TYPE STREQUAL #{build_type_cooked}"
        end
        write_set_var_bool_conditional(get_buildcfg_var_name_of_condition(condition), str_cmake_build_type_condition)
      }
    #else... implicitly being done by v2c_platform_build_setting_configure() invoked during project leadin.
    end
  end
  # File-related TODO:
  # should definitely support the following CMake properties, as needed:
  # PUBLIC_HEADER (cmake --help-property PUBLIC_HEADER), PRIVATE_HEADER, HEADER_FILE_ONLY
  # and possibly the PUBLIC_HEADER option of the INSTALL(TARGETS) command.
  def put_file_list(project_info, arr_sub_source_list_var_names)
    put_file_list_source_group_recursive(project_info.name, project_info.main_files, nil, arr_sub_source_list_var_names)

    put_file_list_vs10(project_info.name, project_info.file_lists, nil, arr_sub_source_list_var_names)

    if not arr_sub_source_list_var_names.empty?
      # add a ${V2C_SOURCES} variable to the list, to be able to append
      # all sorts of (auto-generated, ...) files to this list within
      # hook includes.
      # - _right before_ creating the target with its sources
      # - and not earlier since earlier .vcproj-defined variables should be clean (not be made to contain V2C_SOURCES contents yet)
      arr_sub_source_list_var_names.push('V2C_SOURCES')
    else
      logger.warn "#{project_info.name}: no source files at all!? (header-based project?)"
    end
  end
  def put_file_list_source_group_recursive(project_name, files_str, parent_source_group, arr_sub_sources_for_parent)
    if files_str.nil?
      puts "ERROR: WHAT THE HELL, NO FILES!?"
      return
    end
    filelist_generator = V2C_CMakeFileListsGenerator_VS7.new(@textOut, project_name, @project_dir, files_str, parent_source_group, arr_sub_sources_for_parent)
    filelist_generator.generate
  end
  def put_file_list_vs10(project_name, file_lists, parent_source_group, arr_sub_sources_for_parent)
    if file_lists.nil?
      puts "ERROR: WHAT THE HELL, NO FILES!?"
      return
    end
    # FIXME: for resource files ('ResourceCompile' items),
    # we should be adding a custom target
    # (most likely within a new vcproj2cmake_func.cmake helper function)
    # making use of CMAKE_RC_COMPILER.
    # Also, for resource files we should ideally be setting the
    # LANGUAGE property of the file (to RC).
    # See also CMAKE_RC_SOURCE_FILE_EXTENSIONS, CMAKE_RC_OUTPUT_EXTENSION,
    # CMAKE_RC_COMPILER, CMAKE_RC_COMPILE_OBJECT and CMake modules
    # CMakeDetermineRCCompiler.cmake, CMakeRCInformation.cmake
    # We currently add resource (.rc) files to the project target as well...
    # While this doesn't lead to rogue rebuilds of the independent target,
    # in some environments this might happen. Thus we might want to skip adding
    # the resource files list (VS10: ResourceCompile list) to the target.
    file_lists.arr_file_lists.each { |file_list|
      filelist_generator = V2C_CMakeFileListGenerator_VS10.new(@textOut, project_name, @project_dir, file_list, parent_source_group, arr_sub_sources_for_parent)
      filelist_generator.generate
      #arr_generated = file_list.get_generated_files
      #puts "arr_generated #{arr_generated}"
    }
  end
  def put_source_vars(arr_sub_source_list_var_names)
    arr_source_vars = arr_sub_source_list_var_names.collect { |sources_elem|
	get_dereferenced_variable_name(sources_elem)
    }
    next_paragraph()
    write_list_quoted('SOURCES', arr_source_vars)
  end
  def put_hook_post_sources; @localGenerator.put_customization_hook_from_cmake_var('V2C_HOOK_POST_SOURCES') end
  def put_hook_post_definitions
    next_paragraph()
    @localGenerator.put_customization_hook_commented_from_cmake_var(
      'V2C_HOOK_POST_DEFINITIONS',
      COMMENT_LEVEL_MINIMUM,
      "Hook include after all definitions have been made\n" \
      "(but _before_ target is created using the source list!)"
    )
  end
  def put_v2c_target_midl_specify_files(target_name, condition, midl_info)
    # TODO: should use condition to alternatively open-code the conditional variable
    # here in case self-contained mode is requested.
    # ... = get_buildcfg_var_name_of_condition(condition)

    # For an MIDL discussion, see
    #   http://cmake.3232098.n2.nabble.com/CMake-with-IDL-file-generation-td7581589.html
    arr_args_midl = [ midl_info.header_file_name, midl_info.iface_id_file_name, midl_info.type_library_name ]
    write_invoke_object_conditional_v2c_function('v2c_target_midl_specify_files', target_name, condition, arr_args_midl)
  end
  def hook_up_midl_files(file_lists, config_info)
    # VERY Q&D way to mark MIDL-related files as GENERATED,
    # to keep CMake from erroring out when adding these source files to a target.
    # Well, even marking these files as GENERATED does not help,
    # since they simply won't be available for the target --> error.
    # Instead, we do need to have an add_custom_command()
    # which generates them (or suitable dummy files if needed).
    arr_midl_info = config_info.tools.arr_midl_info
    if not arr_midl_info.empty?
      midl_info = arr_midl_info[0]
      #put_v2c_target_midl_preprocessor_definitions(...)
      #put_v2c_target_midl_options(GENERATESTUBLESSPROXIES ... MKTYPLIBCOMPATIBLE ... VALIDATEALLPARAMETERS ...)
      # put_v2c_target_midl_specify_files() will be the last line to be generated - the invoked function
      # will then implement the MIDL custom command using all previously configured MIDL target properties settings.
      # FIXME: the .idl file is currently missing (contained within the file list called "Midl")
      # - possibly we'd need it here, too (at least if we _can_ do something useful with MIDL information
      # on Non-Win32 platforms...).
      put_v2c_target_midl_specify_files(@target.name, config_info.condition, midl_info)
    end
  end
  # Currently UNUSED!
  def mark_files_as_generated(arr_generated_files)
    if not arr_generated_files.empty?
      # FIXME: doing correct handling of quoting for these files!?
      str_cmake_command_args = "SOURCE #{arr_generated_files.join(' ')} PROPERTY GENERATED"
      @localGenerator.write_command_single_line('set_property', str_cmake_command_args)
    end
  end
  def put_atl_mfc_config(target_config_info)
    # FIXME: should check whether CMAKE_MFC_FLAG is ok with specifying
    # it anywhere within CMakeLists.txt at our local directory scope -
    # if so, then we could place this function call _after_ having
    # established the target, thus we could already pretend this configuration
    # item to always have proper target property scope...
    do_configure_atl_mfc_flag(@target.name, target_config_info.condition, target_config_info.use_of_atl, target_config_info.use_of_mfc)
  end
  #def evaluate_precompiled_header_config(target, files_str)
  #end
  #
  def write_conditional_target_valid_begin
    write_conditional_if(get_target_syntax_expression(@target.name))
  end
  def write_conditional_target_valid_end
    write_conditional_end(get_target_syntax_expression(@target.name))
  end

  def get_target_syntax_expression(target_name); "TARGET #{target_name}" end

  # FIXME: not sure whether map_lib_dirs etc. should be passed in in such a raw way -
  # probably mapping should already have been done at that stage...
  def put_target(target, arr_sub_source_list_var_names, map_lib_dirs, map_lib_dirs_dep, map_dependencies, config_info_curr, target_config_info_curr)
    target_is_valid = false

    # first add source reference, then do linker setup, then create target

    put_source_vars(arr_sub_source_list_var_names)

    # write link_directories() (BEFORE establishing a target!)
    config_info_curr.tools.arr_linker_info.each { |linker_info_curr|
      @localGenerator.write_link_directories(linker_info_curr.arr_lib_dirs, map_lib_dirs)
    }

    target_is_valid = put_target_type(target, map_dependencies, config_info_curr, target_config_info_curr)

    # Add a special collection of those library dependencies
    # which we successfully translated from a bare link directory auto-link dependency
    # (AFTER establishing a target!):
    config_info_curr.tools.arr_linker_info.each { |linker_info_curr|
      @localGenerator.write_build_attributes('target_link_libraries', linker_info_curr.arr_lib_dirs, map_lib_dirs_dep, @target.name, true)
    }

    put_hook_post_target()
    return target_is_valid
  end
  def put_target_type(target, map_dependencies, target_info_curr, target_config_info_curr)
    target_is_valid = false

    str_condition_no_target = get_conditional_inverted(get_target_syntax_expression(target.name))
    write_conditional_if(str_condition_no_target)
          # FIXME: should use a macro like rosbuild_add_executable(),
          # http://www.ros.org/wiki/rosbuild/CMakeLists ,
          # https://kermit.cse.wustl.edu/project/robotics/browser/trunk/vendor/ros/core/rosbuild/rosbuild.cmake?rev=3
          # to be able to detect non-C++ file types within a source file list
          # and add a hook to handle them specially.

          # see VCProjectEngine ConfigurationTypes enumeration
    case target_config_info_curr.cfg_type
    when V2C_TargetConfig_Defines::CFG_TYPE_APP
      target_is_valid = true
      #syntax_generator.write_line("add_executable_vcproj2cmake( #{target.name} WIN32 ${SOURCES} )")
      # TODO: perhaps for real cross-platform binaries (i.e.
      # console apps not needing a WinMain()), we should detect
      # this and not use WIN32 in this case...
      # Well, this toggle probably is related to the .vcproj Keyword attribute...
      write_target_executable()
    when V2C_TargetConfig_Defines::CFG_TYPE_DLL
      target_is_valid = true
      #syntax_generator.write_line("add_library_vcproj2cmake( #{target.name} SHARED ${SOURCES} )")
      # add_library() docs: "If no type is given explicitly the type is STATIC or  SHARED
      #                      based on whether the current value of the variable
      #                      BUILD_SHARED_LIBS is true."
      # --> Thus we would like to leave it unspecified for typeDynamicLibrary,
      #     and do specify STATIC for explicitly typeStaticLibrary targets.
      # However, since then the global BUILD_SHARED_LIBS variable comes into play,
      # this is a backwards-incompatible change, thus leave it for now.
      # Or perhaps make use of new V2C_TARGET_LINKAGE_{SHARED|STATIC}_LIB
      # variables here, to be able to define "SHARED"/"STATIC" externally?
      write_target_library_dynamic()
    when V2C_TargetConfig_Defines::CFG_TYPE_STATIC_LIB
      target_is_valid = true
      write_target_library_static()
    when V2C_TargetConfig_Defines::CFG_TYPE_UNKNOWN
      logger.warn "Project type 0 (typeUnknown - utility, configured for target #{target.name}) is a _custom command_ type and thus probably cannot be supported easily. We will not abort and thus do write out a file, but it probably needs fixup (hook scripts?) to work properly. If this project type happens to use VCNMakeTool tool, then I would suggest to examine BuildCommandLine/ReBuildCommandLine/CleanCommandLine attributes for clues on how to proceed."
    when V2C_TargetConfig_Defines::CFG_TYPE_GENERIC
      logger.unhandled_functionality "#{@target.name}: project type #{target_config_info_curr.cfg_type} almost non-supported."
      # Certain .vcproj:s do contain a list of source/header files,
      # thus do try to establish a normal library/executable target - maybe we're in luck.
      write_target_library_dynamic()
    else
    #when 10    # typeGeneric (Makefile) [and possibly other things...]
      # TODO: we _should_ somehow support these project types...
      # In fact this is likely to be equivalent to cmTarget::UTILITY,
      # which is a direct translation of an add_custom_command().
      # Thus such things should most likely end up generated as an
      # add_custom_command() / add_custom_target() combo.
      # The most challenging part will be achieving
      # flexible cross-platform translation of any system-specific commands
      # that are executed by the command.
      log_debug "#{@target.inspect}"
      raise V2C_GeneratorError, "#{@target.name}: project type #{target_config_info_curr.cfg_type} not supported."
    end
    write_conditional_end(str_condition_no_target)

    # write target_link_libraries() in case there's a valid target
    if target_is_valid
      target_info_curr.tools.arr_linker_info.each { |linker_info_curr|
        arr_dependencies = linker_info_curr.arr_dependencies.collect { |dep| dep.dependency }
        write_link_libraries(arr_dependencies, map_dependencies)
      }
    end # target_is_valid
    return target_is_valid
  end
  def write_target_executable
    write_command_single_line('add_executable', "#{@target.name} WIN32 ${SOURCES}")
  end

  def write_target_library_dynamic
    next_paragraph()
    write_command_single_line('add_library', "#{@target.name} SHARED ${SOURCES}")
  end

  def write_target_library_static
    next_paragraph()
    write_command_single_line('add_library', "#{@target.name} STATIC ${SOURCES}")
  end
  def put_hook_post_target
    next_paragraph()
    @localGenerator.put_customization_hook_commented_from_cmake_var(
      'V2C_HOOK_POST_TARGET',
      COMMENT_LEVEL_MINIMUM,
      "E.g. to be used for tweaking target properties etc."
    )
  end
  def put_property_compile_definitions(config_name, arr_compile_defn)
    arr_compile_defn_cooked = cmake_escape_compile_definitions(arr_compile_defn)
    property_name = get_name_of_per_config_type_property('COMPILE_DEFINITIONS', config_name)
    # make sure to specify APPEND for greater flexibility (hooks etc.)
    cmake_command_arg = "TARGET #{@target.name} APPEND PROPERTY #{property_name}"
    write_command_list('set_property', cmake_command_arg, arr_compile_defn_cooked)
  end
  def generate_property_compile_definitions_per_platform(config_name, arr_platdefs, str_platform)
    write_conditional_if(str_platform)
      put_property_compile_definitions(config_name, arr_platdefs)
    write_conditional_end(str_platform)
  end
  def put_precompiled_header(target_name, condition, pch_use_mode, pch_source_name, pch_binary_name)
    # FIXME: empty filename may happen in case of precompiled file
    # indicated via VS7 FileConfiguration UsePrecompiledHeader
    # (however this is an entry of the .cpp file: not sure whether we can
    # and should derive the header from that - but we could grep the
    # .cpp file for the similarly named include......).
    return if pch_source_name.nil? or pch_source_name.empty?
    str_pch_use_mode = "#{pch_use_mode}" # stringify integer
    arr_args_precomp_header = [ str_pch_use_mode, pch_source_name, pch_binary_name ]
    write_invoke_object_conditional_v2c_function('v2c_target_add_precompiled_header',
    target_name, condition, arr_args_precomp_header)
  end
  def write_precompiled_header(condition, precompiled_header_info)
    return if not $v2c_target_precompiled_header_enable
    return if precompiled_header_info.nil?
    return if precompiled_header_info.header_source_name.nil?
    ## FIXME: this filesystem validation should be carried out by a non-parser/non-generator validator class...
    #header_file_is_existing = v2c_generator_check_file_accessible(@project_dir, precompiled_header_info.header_source_name, 'header file to be precompiled', @target.name, false)
    logger.info "#{@target.name}: generating PCH functionality (use mode #{precompiled_header_info.use_mode}, header file #{precompiled_header_info.header_source_name}, PCH output binary #{precompiled_header_info.header_binary_name})"
    put_precompiled_header(
      @target.name,
      condition,
      precompiled_header_info.use_mode,
      precompiled_header_info.header_source_name,
      precompiled_header_info.header_binary_name
    )
  end
  def write_property_compile_definitions(condition, arr_defs_assignments, map_defs)
    return if arr_defs_assignments.empty?
    # the container for the list of _actual_ dependencies as stated by the project
    all_platform_defs = Hash.new
    parse_platform_conversions(all_platform_defs, arr_defs_assignments, map_defs, false)
    var_v2c_want_buildcfg_curr = get_buildcfg_var_name_of_condition(condition)
    write_conditional_if(var_v2c_want_buildcfg_curr)
      build_type = condition.get_build_type()
      hash_ensure_sorted_each(all_platform_defs).each { |key, arr_platdefs|
        #logger.info "arr_platdefs: #{arr_platdefs}"
        next_paragraph()
        str_platform = key if not key.eql?(V2C_ALL_PLATFORMS_MARKER)
        generate_property_compile_definitions_per_platform(build_type, arr_platdefs, str_platform)
      }
    write_conditional_end(var_v2c_want_buildcfg_curr)
  end
  def write_property_compile_flags(condition, arr_flags, str_conditional)
    return if arr_flags.empty?
    next_paragraph()
    var_v2c_want_buildcfg_curr = get_buildcfg_var_name_of_condition(condition)
    write_conditional_if(var_v2c_want_buildcfg_curr)
      write_conditional_if(str_conditional)
        # FIXME!!! It appears that while CMake source has COMPILE_DEFINITIONS_<CONFIG>,
        # it does NOT provide a per-config COMPILE_FLAGS property! Need to verify ASAP
        # whether compile flags do get passed properly in debug / release.
        # Strangely enough it _does_ have LINK_FLAGS_<CONFIG>, though!
        str_target_expr = get_target_syntax_expression(@target.name)
        build_type = condition.get_build_type()
        property_name = get_name_of_per_config_type_property('COMPILE_FLAGS', build_type)
        cmake_command_arg = "#{str_target_expr} APPEND PROPERTY #{property_name}"
        write_command_list('set_property', cmake_command_arg, arr_flags)
      write_conditional_end(str_conditional)
    write_conditional_end(var_v2c_want_buildcfg_curr)
  end
  def write_property_link_flags(condition, arr_flags, str_conditional)
    return if arr_flags.empty?
    next_paragraph()
    var_v2c_want_buildcfg_curr = get_buildcfg_var_name_of_condition(condition)
    write_conditional_if(var_v2c_want_buildcfg_curr)
      write_conditional_if(str_conditional)
        str_target_expr = get_target_syntax_expression(@target.name)
        build_type = condition.get_build_type()
        property_name = get_name_of_per_config_type_property('LINK_FLAGS', build_type)
        cmake_command_arg = "#{str_target_expr} APPEND PROPERTY #{property_name}"
        write_command_list('set_property', cmake_command_arg, arr_flags)
      write_conditional_end(str_conditional)
    write_conditional_end(var_v2c_want_buildcfg_curr)
  end
  def write_link_libraries(arr_dependencies, map_dependencies)
    arr_dependencies_augmented = arr_dependencies.clone
    arr_dependencies_augmented.push(get_dereferenced_variable_name('V2C_LIBS'))
    @localGenerator.write_build_attributes('target_link_libraries', arr_dependencies_augmented, map_dependencies, @target.name)
  end
  def write_func_v2c_target_post_setup(project_name, project_keyword)
    # Rationale: keep count of generated lines of CMakeLists.txt to a bare minimum -
    # call v2c_project_post_setup(), by simply passing all parameters that are _custom_ data
    # of the current generated CMakeLists.txt file - all boilerplate handling functionality
    # that's identical for each project should be implemented by the v2c_project_post_setup() function
    # _internally_.
    if project_keyword.nil?; project_keyword = V2C_ATTRIBUTE_NOT_PROVIDED_MARKER end
    arr_args_func = [ project_name, project_keyword ]
    write_invoke_config_object_v2c_function_quoted('v2c_target_post_setup', @target.name, arr_args_func)
  end
  def set_properties_vs_scc(target_name, scc_info_in)
    # Keep source control integration in our conversion!
    # FIXME: does it really work? Then reply to
    # http://www.itk.org/Bug/view.php?id=10237 !!

    # If even scc_info.project_name is unavailable,
    # then we can bail out right away...
    return if scc_info_in.project_name.nil?

    scc_info_cmake = scc_info_in.clone

    # Hmm, perhaps need to use CGI.escape since chars other than just '"' might need to be escaped?
    # NOTE: needed to clone() this string above since otherwise modifying (same) source object!!
    # We used to escape_char('"') below, but this was problematic
    # on VS7 .vcproj generator since that one is BUGGY (GIT trunk
    # 201007xx): it should escape quotes into XMLed "&quot;" yet
    # it doesn't. Thus it's us who has to do that and pray that it
    # won't fail on us... (but this bogus escaping within
    # CMakeLists.txt space might lead to severe trouble
    # with _other_ IDE generators which cannot deal with a raw "&quot;").
    # If so, one would need to extend v2c_target_set_properties_vs_scc()
    # to have a CMAKE_GENERATOR branch check, to support all cases.
    # Or one could argue that the escaping should better be done on
    # CMake-side code (i.e. in v2c_target_set_properties_vs_scc()).
    # Note that perhaps we should also escape all other chars
    # as in CMake's EscapeForXML() method.
    scc_info_cmake.project_name.gsub!(/"/, '&quot;')
    if scc_info_cmake.local_path
      escape_backslash(scc_info_cmake.local_path)
      escape_char(scc_info_cmake.local_path, '"')
    end
    if scc_info_cmake.provider
      escape_char(scc_info_cmake.provider, '"')
    end
    if scc_info_cmake.aux_path
      escape_backslash(scc_info_cmake.aux_path)
      escape_char(scc_info_cmake.aux_path, '"')
    end

    next_paragraph()
    arr_args_func = [ scc_info_cmake.project_name, scc_info_cmake.local_path, scc_info_cmake.provider, scc_info_cmake.aux_path ]
    write_invoke_config_object_v2c_function_quoted('v2c_target_set_properties_vs_scc', target_name, arr_args_func)
  end

  def add_target_config_specific_definitions(condition, target_config_info, hash_defines)
    # Hrmm, are we even supposed to be doing this?
    # On Windows I guess UseOfMfc in generated VS project files
    # would automatically cater for it, and all other platforms
    # would have to handle it some way or another anyway.
    # But then I guess there are other build environments on Windows
    # which would need us handling it here manually, so let's just keep it for now.
    # Plus, defining _AFXEXT already includes the _AFXDLL setting
    # (MFC will define it implicitly),
    # thus it's quite likely that our current handling is somewhat incorrect.
    if target_config_info.use_of_mfc == V2C_TargetConfig_Defines::MFC_DYNAMIC
      # FIXME: need to add a compiler flag lookup entry
      # to compiler-specific info as well!
      # (in case of MSVC it would yield: /MD [dynamic] or /MT [static])
      hash_defines['_AFXEXT'] = ''
      hash_defines['_AFXDLL'] = ''
    end
    charset_type = 'SBCS'
    case target_config_info.charset
    when V2C_TargetConfig_Defines::CHARSET_SBCS
      charset_type = 'SBCS'
    when V2C_TargetConfig_Defines::CHARSET_UNICODE
      charset_type = 'UNICODE'
    when V2C_TargetConfig_Defines::CHARSET_MBCS
      charset_type = 'MBCS'
    else
      log_implementation_bug('unknown charset type!?')
    end
    arr_args_func_other = [ charset_type ]
    write_invoke_object_conditional_v2c_function('v2c_target_config_charset_set', @target.name, condition, arr_args_func_other)
  end

  def generate_it(generator_base, map_lib_dirs, map_lib_dirs_dep, map_dependencies, map_defines)

    project_info = @target # HACK

    generate_project_leadin(project_info)

    # arr_sub_source_list_var_names will receive the names of the individual source list variables:
    arr_sub_source_list_var_names = Array.new

    put_file_list(project_info, arr_sub_source_list_var_names)

    put_include_dir_project_source_dir(project_info.name)

    put_hook_post_sources()

    arr_config_info = project_info.arr_config_info

    generate_assignments_of_build_type_variables(arr_config_info)

    arr_target_config_info = project_info.arr_target_config_info

    target_is_valid = false

    arr_config_info.each { |config_info_curr|
      next_paragraph()

      # Generate all functions which already have their own conditional
      # platform / build type handling here, prior to generating the
      # var_v2c_want_buildcfg_curr below...
      hook_up_midl_files(project_info.file_lists, config_info_curr)

      condition = config_info_curr.condition
      var_v2c_want_buildcfg_curr = get_buildcfg_var_name_of_condition(condition)
      write_conditional_if(var_v2c_want_buildcfg_curr)

      config_info_curr.tools.arr_compiler_info.each { |compiler_info_curr|
        arr_includes = compiler_info_curr.get_include_dirs(false, false)
        @localGenerator.write_include_directories(arr_includes, generator_base.map_includes)
      }

      # At this point (before target creation - much earlier than we
      # would want to), we'll have to iterate through target configs
      # for all settings which are target related but are (stupidly)
      # NOT being applied as target properties (i.e. post-target-setup).
      arr_target_config_info.each { |target_config_info_curr|
	next if not condition.entails(target_config_info_curr.condition)
	# FIXME: put_atl_mfc_config() does not need
	# var_v2c_want_buildcfg_curr i.e. should be outside of it
	# (already does own condition handling) - how to resolve this?
        put_atl_mfc_config(target_config_info_curr)
      }

      # FIXME: hohumm, the position of this hook include is outdated, need to update it
      # Well, there's a distinction between
      # ("dirty") global settings (defined _prior_ to adding a target)
      # and target-aggregated settings (properties),
      # thus maybe we need different hooks for these two mechanisms.
      # Well, but for now at least MAKE SURE TO ALWAYS KEEP IT RIGHT BEFORE
      # adding the target! (to be able to manipulate _all_ prior settings
      # if needed).
      put_hook_post_definitions()

      # Technical note: target type (library, executable, ...) in .vcproj can be configured per-config
      # (or, in other words, different configs are capable of generating _different_ target _types_
      # for the _same_ target), but in CMake this isn't possible since _one_ target name
      # maps to _one_ target type and we _need_ to restrict ourselves to using the project name
      # as the exact target name (we are unable to define separate PROJ_lib and PROJ_exe target names,
      # since other .vcproj file contents always link to our target via the main project name only!!).
      # Thus we need to declare the target _outside_ the scope of per-config handling :(

      # create a target only in case we do have any meat at all
      if project_info.have_build_units
        arr_target_config_info.each { |target_config_info_curr|
          next if not condition.entails(target_config_info_curr.condition)
          target_is_valid = put_target(project_info, arr_sub_source_list_var_names, map_lib_dirs, map_lib_dirs_dep, map_dependencies, config_info_curr, target_config_info_curr)
        }
      end # target.have_build_units

      write_conditional_end(var_v2c_want_buildcfg_curr)
    } # [END per-config handling]

    # Now that we likely _do_ have a valid target
    # (created by at least one of the Debug/Release/... build configs),
    # _iterate through the configs again_ and add config-specific
    # definitions. This is necessary (fix for multi-config
    # environment).
    #
    # UGH, now added yet another loop iteration.
    # FIXME This is getting waaaaay too messy, need to refactor it to have a
    # clean hierarchy.
    if target_is_valid
      write_conditional_target_valid_begin()
      arr_config_info.each { |config_info_curr|
        condition = config_info_curr.condition

        tools = config_info_curr.tools

        # NOTE: the commands below can stay in the general section (outside of
        # var_v2c_want_buildcfg_curr above), but only since they define properties
        # which are clearly named as being configuration-_specific_ already!
        #
        # I don't know WhyTH we're iterating over a compiler_info here,
        # but let's just do it like that for now since it's required
        # by our current data model:
        tools.arr_compiler_info.each { |compiler_info_curr|

          print_marker_line('per-compiler_info')

          arr_target_config_info.each { |target_config_info_curr|
	    next if not condition.entails(target_config_info_curr.condition)

	    hash_defines_augmented = compiler_info_curr.hash_defines.clone

	    add_target_config_specific_definitions(condition, target_config_info_curr, hash_defines_augmented)
            # Convert hash into array as required by the definitions helper function
            # (it's probably a good idea to provide "cooked" "key=value" entries
            # for more complete matching possibilities
            # within the regex matching parts done by it).
            # TODO: this might be relocatable to a common generator base helper method.
            arr_defs_assignments = Array.new
            hash_ensure_sorted_each(hash_defines_augmented).each { |key, value|
              str_define = value.empty? ? key : "#{key}=#{value}"
              arr_defs_assignments.push(str_define)
            }
            write_property_compile_definitions(condition, arr_defs_assignments, map_defines)
            # Original compiler flags are MSVC-only, of course. TODO: provide an automatic conversion towards gcc?
            compiler_info_curr.arr_tool_variant_specific_info.each { |compiler_specific|
  	      str_conditional_compiler_platform = map_compiler_name_to_cmake_platform_conditional(compiler_specific.compiler_name)
              # I don't think we need this (we have per-target properties), thus we'll NOT write it!
              #if not attr_opts.nil?
              #  local_generator.write_directory_property_compile_flags(attr_options)
              #end
              write_property_compile_flags(condition, compiler_specific.arr_flags, str_conditional_compiler_platform)
            } # compiler.tool_specific.each
          } # arr_target_config_info.each

          # Since the precompiled header CMake module currently
          # _resets_ a target's COMPILE_FLAGS property,
          # make sure to generate it _before_ specifying any COMPILE_FLAGS:
          # UPDATE: nope, it's now fixed, thus move it *after* the target
	  # is fully configured (it needs to be able to correctly gather
	  # all settings of the target it is supposed to be used for).
          write_precompiled_header(condition, compiler_info_curr.precompiled_header_info)

        } # config_info_curr.tools.arr_compiler_info.each
        tools.arr_linker_info.each { |linker_info_curr|
          linker_info_curr.arr_tool_variant_specific_info.each { |linker_specific|
	    str_conditional_linker_platform = map_linker_name_to_cmake_platform_conditional(linker_specific.linker_name)
            # Probably more linker flags support needed? (mention via
            # CMAKE_SHARED_LINKER_FLAGS / CMAKE_MODULE_LINKER_FLAGS / CMAKE_EXE_LINKER_FLAGS
            # depending on target type, and make sure to filter out options pre-defined by CMake platform
            # setup modules)
            write_property_link_flags(condition, linker_specific.arr_flags, str_conditional_linker_platform)
          } # linker.tool_specific.each
        } # arr_linker_info.each
      } # config_info_curr
      write_conditional_target_valid_end()
    end

    if target_is_valid
      write_func_v2c_target_post_setup(project_info.name, project_info.vs_keyword)

      set_properties_vs_scc(@target.name, project_info.scc_info)

      # TODO: might want to set a target's FOLDER property, too...
      # (and perhaps a .vcproj has a corresponding attribute
      # which indicates that?)

      # TODO: perhaps there are useful Xcode (XCODE_ATTRIBUTE_*) properties to convert?
    end # target_is_valid

    arr_orig_proj_files = project_info.arr_p_original_project_files.collect { |orig_proj_file|
      orig_proj_file.relative_path_from(@project_dir)
    }
    write_func_v2c_project_post_setup(project_info.name, arr_orig_proj_files)
  end

  private

  def put_project(project_name, arr_progr_languages = nil)
    arr_args_project_name_and_attrs = [ project_name ]
    if arr_progr_languages.nil? or arr_progr_languages.empty?
      ## No programming language given? Indicate special marker "NONE"
      ## to skip any compiler checks.
      # Nope, no language means "unknown", thus don't specify anything -
      # to keep CMake's auto-detection mechanism active.
      #arr_args_project_name_and_attrs.push('NONE')
    else
      arr_args_project_name_and_attrs.concat(arr_progr_languages)
    end
    write_command_list_single_line('project', arr_args_project_name_and_attrs)
  end
  def write_project(project_info)
    # Figure out language type (C CXX etc.) and add it to project() command
    arr_languages = detect_programming_languages(project_info)
    put_project(project_info.name, arr_languages)
  end
  def put_conversion_info(project_name, str_from_buildtool_version)
    # Add an explicit file generation timestamp,
    # to enable easy identification (grepping) of files of a certain age
    # (a filesystem-based creation/modification timestamp might be unreliable
    # due to copying/modification).
    str_time = ''
    timestamp_format = $v2c_generator_timestamp_format
    if not timestamp_format.nil? and not timestamp_format.empty?
      timestamp_format_docs = timestamp_format.tr('%', '')
      time = Time.new
      str_time = time.utc.strftime(timestamp_format)
    end
    write_comment_at_level(COMMENT_LEVEL_VERBOSE,
      "For this project's file, indicates originating build environment / IDE,\n" \
      "and indicates conversion moment in time (UTC, format #{timestamp_format_docs})"
    )
    write_invoke_v2c_function_quoted('v2c_project_conversion_info_set', [ project_name, str_time, str_from_buildtool_version ])
  end
  def detect_programming_languages(project_info)
    language_detector = V2C_CMakeProjectLanguageDetector.new(project_info)
    language_detector.detect
  end
  def put_include_MasterProjectDefaults_vcproj2cmake
    if @textOut.generated_comments_level() >= 2
      @textOut.write_data %{\

# This part is for including a file which contains
# settings (compiler flags, path settings, platform stuff, ...)
# which are _globally_ applicable for all sub projects of a solution
# e.g. have vcproj2cmake-specific MasterProjectDefaults_vcproj2cmake
# which then _also_ includes a global MasterProjectDefaults module
# for _all_ CMakeLists.txt. This needs to sit post-project()
# since e.g. compiler info is dependent on a valid project.
}
      # NOTE: V2C_LIBS, V2C_SOURCES are _target_-specific
      # (one local directory - i.e. one single CMakeLists.txt - may contain _multiple_
      # project files - i.e. project()s -!). I.e., they need to be reset
      # per-project()!
      @textOut.write_block( \
	"# MasterProjectDefaults_vcproj2cmake is supposed to define generic settings\n" \
        "# (such as V2C_HOOK_PROJECT, defined as e.g.\n" \
        "# #{$v2c_config_dir_local}/hook_project.txt,\n" \
        "# and other hook include variables below).\n" \
        "# NOTE: it usually should also reset variables\n" \
        "# V2C_LIBS, V2C_SOURCES etc. as used below since they should contain\n" \
        "# project-specific contents only, not accumulate!" \
      )
    end
    # (side note: see "ldd -u -r" on Linux for superfluous link parts potentially caused by this!)
    write_include('MasterProjectDefaults_vcproj2cmake', true)
  end
  def write_funcs_v2c_project_platform_define_build_types(project_name, build_platform_configs)
    build_platform_configs.get_platforms().each { |platform_name|
      arr_platform_build_types = build_platform_configs.get_build_types(platform_name)
      write_func_v2c_project_platform_define_build_types(project_name, platform_name, arr_platform_build_types)
    }
    write_invoke_v2c_function_quoted('v2c_platform_build_setting_configure', [ project_name ])
  end
  def write_func_v2c_project_platform_define_build_types(project_name, platform_name, arr_platform_build_types)
    arr_args_func = [ platform_name ]
    arr_args_func.concat(arr_platform_build_types)
    write_invoke_config_object_v2c_function_quoted('v2c_project_platform_define_build_types', project_name, arr_args_func)
  end
  def put_hook_project
    put_customization_hook_commented_from_cmake_var(
      'V2C_HOOK_PROJECT',
      COMMENT_LEVEL_STANDARD,
      "Hook e.g. for invoking Find scripts as expected by\n" \
      "the _LIBRARIES / _INCLUDE_DIRS mappings created\n" \
      "by your include/dependency map files."
    )
  end

  def generate_project_leadin(project_info)
    write_project(project_info)
    put_conversion_info(project_info.name, project_info.orig_environment_shortname)
    put_include_MasterProjectDefaults_vcproj2cmake()
    write_funcs_v2c_project_platform_define_build_types(project_info.name, project_info.build_platform_configs)
    put_hook_project()
  end
  # _target_ generator specific method.
  def set_property(target_name, property, value)
    arr_args_func = [ 'TARGET', target_name, 'PROPERTY', property, value ]
    write_command_list_quoted('set_property', nil, arr_args_func)
  end
  def write_func_v2c_project_post_setup(project_name, arr_proj_files)
    # This function invokes CMakeLists.txt rebuilder only
    # (TODO: should be changed into specific naming!),
    # thus skip on one-time generation.
    return if $v2c_generator_one_time_conversion_only

    # Rationale: keep count of generated lines of CMakeLists.txt to a bare minimum -
    # call v2c_project_post_setup(), by simply passing all parameters that are _custom_ data
    # of the current generated CMakeLists.txt file - all boilerplate handling functionality
    # that's identical for each project should be implemented by the v2c_project_post_setup() function
    # _internally_.
    arr_args_func = [ array_to_cmake_list(arr_proj_files) ]
    write_invoke_config_object_v2c_function_quoted('v2c_project_post_setup', project_name, arr_args_func)
  end
end

# Supposed to generate the globally configured parts
# within an entire "solution" hierarchy.
# Currently, these end up (repeated) in each local CMakeLists.txt file.
# Should be generating into a common include() file instead.
class V2C_CMakeGlobalGenerator < V2C_CMakeV2CSyntaxGenerator
  def put_configuration_types(configuration_types)
    configuration_types_list = separate_arguments(configuration_types)
    write_set_var_quoted('CMAKE_CONFIGURATION_TYPES', configuration_types_list)
  end
end

# Generates the CMake code required to bootstrap V2C operation
# (provided by each scope which may still need to execute this init code)
class V2C_CMakeGlobalBootstrapCodeGenerator < V2C_CMakeV2CSyntaxGenerator
  def initialize(textOut, relative_path_to_root, script_location_relative_to_master)
    super(textOut)
    @relative_path_to_root = relative_path_to_root
    @script_location_relative_to_master = script_location_relative_to_master
  end
  def generate
    put_per_scope_setup(@relative_path_to_root)
  end

  private

  def put_per_scope_setup(str_conversion_root_rel)
    write_comment_at_level(COMMENT_LEVEL_STANDARD,
      "This part of *global* V2C bootstrap steps (policies, include function module, ...)\n" \
      "*has* to be repeated within each *local* file,\n" \
      "to be able to support the use case of creating a build environment\n" \
      "from single local project directories, too.\n" \
      "But there's a nice trick: if a guard variable is already defined,\n" \
      "then some other (parent?) scope already did all that setup work for us." \
    )
    str_per_scope_definition_guard = '_v2c_global_defs_per_scope_defined'
    str_condition_inverse = get_conditional_inverted(str_per_scope_definition_guard)
    write_conditional_if(str_condition_inverse)
      put_per_scope_cmake_minimum_version()
      put_per_scope_cmake_policies()

      put_cmake_module_path(str_conversion_root_rel)
      put_include_vcproj2cmake_func()
      put_var_config_dir_local()
      # We'll have converter script setup one-time within global setup as well -
      # while different project files/dirs may have been converted
      # with differing scripts, such a use case can be considered
      # sufficiently pathological, thus we will not support it.
      put_converter_script_location(@script_location_relative_to_master)
      write_set_var_bool(str_per_scope_definition_guard, true)
    write_conditional_end(str_condition_inverse)
  end

  # cmake_minimum_required() is required to be mentioned open-coded
  # per-CMakeLists.txt (exact requirement seems to be:
  # to be executed whenever it has not been done before within a scope),
  # thus we always do need to generate this line
  # rather than having it carried out by our module file.
  # Having it mentioned by an included macro executed locally is not
  # accepted either.
  def put_per_scope_cmake_minimum_version
    # Required version line to make cmake happy.
    write_comment_at_level(COMMENT_LEVEL_VERBOSE,
      "For features provided (or not) by various CMake versions,\n" \
      "please see http://www.cmake.org/Wiki/CMake_Released_Versions\n" \
      "(and page CMake_Version_Compatibility_Matrix)."
    )
    str_cmake_minimum_version = '2.6'
    write_comment_at_level(COMMENT_LEVEL_MINIMUM,
      ">= #{str_cmake_minimum_version} due to crucial set_property(... COMPILE_DEFINITIONS_* ...)"
    )
    write_cmake_minimum_version(str_cmake_minimum_version)
  end
  def put_per_scope_cmake_policies
    str_conditional = get_var_conditional_command('cmake_policy')
    write_conditional_if(str_conditional)
      # CMP0005: manual quoting of brackets in definitions doesn't seem to work otherwise,
      # in cmake 2.6.4-7.el5 with "OLD".
      # We'll decide to write the policies one after another -
      # we could be embedding all higher-numbered policies
      # within the conditionals of the lower ones,
      # but this would be less compatible (it is conceivable
      # that certain policy numbers get withdrawn completely in future,
      # in which case hierarchic conditionals would fail).
      write_cmake_policy(5, true, "automatic quoting of brackets")
      write_cmake_policy(11, false, \
	"we do want the includer to be affected by our updates,\n" \
        "since it might define project-global settings.\n" \
      )
      write_cmake_policy(15, true, \
        ".vcproj contains relative paths to additional library directories,\n" \
        "thus we need to be able to cope with that" \
      )
    write_conditional_end(str_conditional)
  end
  def put_cmake_module_path(str_conversion_root_rel)
    # try to point to cmake/Modules of the topmost directory of the vcproj2cmake conversion tree.
    # This also contains vcproj2cmake helper modules (these should - just like the CMakeLists.txt -
    # be within the project tree as well, since someone might want to copy the entire project tree
    # including .vcproj conversions to a different machine, thus all v2c components should be available)
    # NOTE that V2C_MASTER_PROJECT_SOURCE_DIR is a very important variable
    # which may eventually be supported to end up _different_ from CMAKE_SOURCE_DIR
    # (e.g. in the case of integrating _multiple_ different solution (.sln) files
    # - and their project hierarchy each! - into a _higher-level_ natively CMake-based tree!!).
    # We might possibly eventually want to rename V2C_MASTER_PROJECT_SOURCE_DIR into V2C_SOLUTION_ROOT_SOURCE_DIR
    # to reflect the fact that a project hierarchy has been created from a solution
    # that sits in a specific directory...
    next_paragraph()
    write_comment_at_level(COMMENT_LEVEL_STANDARD,
      "Denotes the source root directory where the V2C conversion run was carried out.\n" \
      "This directory also contains certain global vcproj2cmake support subdirs."
    )

    # Handle the case of generating for V2C root (== empty relative path).
    str_conversion_root_rel_cooked = ''
    if not str_conversion_root_rel.empty?
      str_conversion_root_rel_cooked = "/#{str_conversion_root_rel}"
    end
    str_master_proj_source_dir = "#{get_dereferenced_variable_name('CMAKE_CURRENT_SOURCE_DIR')}#{str_conversion_root_rel_cooked}"
    write_set_var_quoted('V2C_MASTER_PROJECT_SOURCE_DIR', str_master_proj_source_dir)
    str_master_proj_binary_dir = "#{get_dereferenced_variable_name('CMAKE_CURRENT_BINARY_DIR')}#{str_conversion_root_rel_cooked}"
    write_set_var_quoted('V2C_MASTER_PROJECT_BINARY_DIR', str_master_proj_binary_dir)
    # NOTE: use set() instead of list(APPEND...) to _prepend_ path
    # (otherwise not able to provide proper _overrides_)
    write_comment_at_level(COMMENT_LEVEL_STANDARD,
      "Extend module path with both a precise relative hint to source root\n" \
      "and a flexible link via CMAKE_SOURCE_DIR expression,\n" \
      "since in certain situations both may end up used\n" \
      "(think build tree created from standalone project)."
    )
    # Whatever we do here - make sure we don't stomp out any potential prior CMAKE_MODULE_PATH definition!!
    # (for details, see "CMake coding guide"
    #    http://www.aldebaran-robotics.com/documentation/qibuild/contrib/cmake/coding_guide.html )
    arr_args_func = [ "${V2C_MASTER_PROJECT_SOURCE_DIR}/#{$v2c_module_path_local}", "${CMAKE_SOURCE_DIR}/#{$v2c_module_path_local}", get_dereferenced_variable_name('CMAKE_MODULE_PATH') ]
    write_list_quoted('CMAKE_MODULE_PATH', arr_args_func)
  end
  def put_include_vcproj2cmake_func
    next_paragraph()
    write_comment_at_level(COMMENT_LEVEL_STANDARD,
      "Include the main file for pre-defined vcproj2cmake helper functions"
    )
    write_include('vcproj2cmake_func')
  end
  # "export" our internal $v2c_config_dir_local variable (to be able to reference it in CMake scripts as well)
  def put_var_config_dir_local; write_set_var_quoted('V2C_CONFIG_DIR_LOCAL', $v2c_config_dir_local) end
end

# This class generates the output of multiple input projects to a text output
# (usually CMakeLists.txt within a local directory).
class V2C_CMakeLocalFileContentGenerator < V2C_CMakeV2CSyntaxGenerator
  def initialize(textOut, local_dir, p_solution_dir, arr_local_project_targets, script_location_relative_to_master)
    super(textOut)
    @local_dir = local_dir
    @p_solution_dir = p_solution_dir
    @master_project_dir = p_solution_dir.to_s
    @arr_local_project_targets = arr_local_project_targets
    @script_location_relative_to_master = script_location_relative_to_master
    local_dir_fqpn = File.expand_path(local_dir)
    p_local_dir_fqpn = Pathname.new(local_dir_fqpn)
    p_root = Pathname.new(File.expand_path(@master_project_dir))
    @p_relative_path_to_root = p_root.relative_path_from(p_local_dir_fqpn)
    # FIXME: handle arr_config_var_handling appropriately
    # (place the translated CMake commands somewhere suitable)
    @arr_config_var_handling = Array.new
    @generator_base = V2C_BaseGlobalGenerator.new(@master_project_dir)
    @map_lib_dirs = Hash.new
    read_mappings_combined(FILENAME_MAP_LIB_DIRS, @map_lib_dirs, @master_project_dir)
    @map_lib_dirs_dep = Hash.new
    read_mappings_combined(FILENAME_MAP_LIB_DIRS_DEP, @map_lib_dirs_dep, @master_project_dir)
    @map_dependencies = Hash.new
    read_mappings_combined(FILENAME_MAP_DEP, @map_dependencies, @master_project_dir)
    @map_defines = Hash.new
    read_mappings_combined(FILENAME_MAP_DEF, @map_defines, @master_project_dir)
  end

  def generate
    generate_it
  end
  def write_include_directories(arr_includes, map_includes)
    # Side note: unfortunately CMake as of 2.8.7 probably still does not have
    # a way of specifying _per-configuration_ syntax of include_directories().
    # See "[CMake] vcproj2cmake.rb script: announcing new version / hosting questions"
    #   http://www.cmake.org/pipermail/cmake/2010-June/037538.html
    #
    # Side note #2: relative arguments to include_directories() (e.g. "..")
    # are relative to CMAKE_PROJECT_SOURCE_DIR and _not_ BINARY,
    # at least on Makefile and .vcproj.
    # CMake dox currently don't offer such details... (yet!)
    return if arr_includes.empty?
    arr_includes_translated = arr_includes.collect { |elem_inc_dir|
      vs7_create_config_variable_translation(elem_inc_dir, @arr_config_var_handling)
    }
    write_build_attributes('include_directories', arr_includes_translated, map_includes, nil)
  end

  def write_link_directories(arr_lib_dirs, map_lib_dirs)
    arr_lib_dirs_translated = arr_lib_dirs.collect { |elem_lib_dir|
      vs7_create_config_variable_translation(elem_lib_dir, @arr_config_var_handling)
    }
    arr_lib_dirs_translated.push(get_dereferenced_variable_name('V2C_LIB_DIRS'))
    write_comment_at_level(COMMENT_LEVEL_VERBOSE,
      "It is said to be much preferable to be able to use target_link_libraries()\n" \
      "rather than the very unspecific link_directories()."
    )
    write_build_attributes('link_directories', arr_lib_dirs_translated, map_lib_dirs, nil)
  end
  def put_directory_property_compile_flags(attr_opts, flag_append)
    write_command_single_line('set_property', "DIRECTORY APPEND PROPERTY COMPILE_FLAGS #{attr_opts}")
  end
  def write_directory_property_compile_flags(attr_opts)
    next_paragraph()
    # Query WIN32 instead of MSVC, since AFAICS there's nothing in the
    # .vcproj to indicate tool specifics, thus these seem to
    # be settings for ANY PARTICULAR tool that is configured
    # on the Win32 side (.vcproj in general).
    str_platform = 'WIN32'
    write_conditional_if(str_platform)
      put_directory_property_compile_flags(attr_opts, true)
    write_conditional_end(str_platform)
  end
  def write_build_attributes(cmake_command, arr_defs, map_defs, cmake_command_arg, skip_failed_lookups = false)
    # the container for the list of _actual_ dependencies as stated by the project
    all_platform_defs = Hash.new
    parse_platform_conversions(all_platform_defs, arr_defs, map_defs, skip_failed_lookups)
    # HACK: yes, we do need to re-sort this Hash _right before_ using it...
    hash_ensure_sorted_each(all_platform_defs).each { |key, arr_platdefs|
      #logger.info "arr_platdefs: #{arr_platdefs}"
      next_paragraph()
      str_platform = key if not key.eql?(V2C_ALL_PLATFORMS_MARKER)
      write_conditional_if(str_platform)
        write_command_list_quoted(cmake_command, cmake_command_arg, arr_platdefs)
      write_conditional_end(str_platform)
    }
  end
  private

  def generate_it
    generate_header
    generate_body
    generate_footer
  end
  def generate_header
    put_file_header(@p_relative_path_to_root.to_s)
  end
  def generate_body
    # FIXME: all these function arguments are temporary crap! - they're supposed to be per-ProjectTarget mostly.
    generate_projects(@local_dir, @generator_base, @map_lib_dirs, @map_lib_dirs_dep, @map_dependencies, @map_defines)
  end
  def generate_footer
    write_func_v2c_directory_post_setup
  end
  def generate_projects(local_dir, generator_base, map_lib_dirs, map_lib_dirs_dep, map_dependencies, map_defines)
    @arr_local_project_targets.each { |project_info|
      project_generator = V2C_CMakeProjectTargetGenerator.new(project_info, local_dir, self, @textOut)

      begin
        project_generator.generate_it(generator_base, map_lib_dirs, map_lib_dirs_dep, map_dependencies, map_defines)
      rescue V2C_GeneratorError => e
        logger.error("project #{project_info.name} generation failed: #{e.message}")
        # Hohumm, this variable is not really what we should be having here...
        if ($v2c_validate_vcproj_abort_on_error > 0)
          raise # escalate the problem
        end
      end
    }
  end

  def put_file_header(str_conversion_root_rel)
    @textOut.put_file_header_temporary_marker()
    bootstrap_generator =
      V2C_CMakeGlobalBootstrapCodeGenerator.new(@textOut, str_conversion_root_rel, @script_location_relative_to_master)
    bootstrap_generator.generate
    put_include_vcproj2cmake_defs()
    put_hook_pre()
  end
  def write_func_v2c_directory_post_setup
    write_invoke_v2c_function_quoted('v2c_directory_post_setup', [])
  end

  private

  def put_include_vcproj2cmake_defs
    next_paragraph()
    write_comment_at_level(COMMENT_LEVEL_STANDARD,
      "Include the globally provided module for re-init of local (per-scope)\n" \
      "configuration settings definitions (to be customized by user as needed)"
    )
    write_include('vcproj2cmake_defs')
  end
  def put_hook_pre
    # this CMakeLists.txt-global optional include could be used e.g.
    # to skip the entire build of this file on certain platforms:
    # if(PLATFORM) message(STATUS "not supported") return() ...
    # (note that we appended CMAKE_MODULE_PATH _prior_ to this include()!)
    put_customization_hook('${V2C_CONFIG_DIR_LOCAL}/hook_pre.txt')
  end
end

# Hrmm, I'm not quite sure yet where to aggregate this function...
# (missing some proper generator base class or so...)
def v2c_generator_check_file_accessible(project_dir, file_relative, file_item_description, project_name, throw_error)
  file_accessible = false
  if $v2c_validate_vcproj_ensure_files_ok
    if file_relative.nil? or file_relative.empty?
      log_warn "#{project_name}: empty file argument! (#{file_item_description})"
    else
      # TODO: perhaps we need to add a permissions check, too?
      file_location = "#{project_dir}/#{file_relative}"
      if File.exist?(file_location)
        file_accessible = true
      else
        log_error "File #{file_relative} (#{file_item_description}) as listed by project #{project_name} does not exist!? (perhaps filename with wrong case, or wrong path, ...)"
        if throw_error
  	# FIXME: should be throwing an exception, to not exit out
  	# on entire possibly recursive (global) operation
          # when a single project is in error...
          log_fatal "Improper original file - will abort and NOT generate a broken converted project file. Please fix content of the original project file!"
        end
      end
    end
  else
    file_accessible = true
  end
  return file_accessible
end

# Detect .vcproj files actually generated by CMake generator itself:
# This detection is a bit troublesome since
# - apart from the CMake generator having added its CMakeLists.txt to the source groups -
# some people may have decided to manually list the CMakeLists.txt in their projects -
# in which case the file is NOT a generated project file, however.
VCPROJ_IS_GENERATED_BY_CMAKE_REGEX_OBJ = %r{CMakeLists.txt}
def v2c_is_project_file_generated_by_cmake(str_proj_file)
  generated_file = false
  cmakelists_text = ''
  File.open(str_proj_file, 'r') { |f_vcproj|
    cmakelists_text = f_vcproj.grep(VCPROJ_IS_GENERATED_BY_CMAKE_REGEX_OBJ)
  }
  if not cmakelists_text.empty?
    generated_file = true
  end
  return generated_file
end


class V2C_CMakeLocalFileGenerator < V2C_LoggerBase
  def initialize(p_v2c_script, p_master_project, p_generator_proj_file, arr_projects)
    @p_master_project = p_master_project

    # figure out a project_dir variable from the generated project file location
    @p_generator_proj_file = p_generator_proj_file
    @arr_projects = arr_projects
    @script_location_relative_to_master = p_v2c_script.relative_path_from(p_master_project)
    #logger.debug "p_v2c_script #{p_v2c_script} | p_master_project #{p_master_project} | @script_location_relative_to_master #{@script_location_relative_to_master}"
  end
  def generate
    output_file_location = @p_generator_proj_file.to_s
    logger.info "Generating project(s) in #{logger.escape_item(@p_generator_proj_file.dirname)} into #{logger.escape_item(output_file_location)}"
    generate_local = V2C_GenerateIntoTempFile.new('local CMakeLists.txt', 'vcproj2cmake', output_file_location)
    generate_local.generate { |textOut|
	content_generator = V2C_CMakeLocalFileContentGenerator.new(textOut, @p_generator_proj_file.dirname, @p_master_project, @arr_projects, @script_location_relative_to_master)
	content_generator.generate
    }
  end
end


# Determines whether a CMakeLists.txt file - e.g. as generated by
# recursive-crawl or whole-solution converter mechanisms -
# is supposed to be generated (i.e. overwritten) at all.
def v2c_want_cmakelists_rewritten(str_cmakelists_file)
  want_cmakelists_rewritten = true
  cmakelists_type = check_cmakelists_txt_type(str_cmakelists_file)
  case cmakelists_type
  when CMAKELISTS_FILE_TYPE_ZERO_SIZE
    # zero-size files may have happened due to out-of-disk-space issues,
    # thus ensure overwriting in such cases.
    log_info 'ZERO-SIZE FILE detected, overwriting!'
  when CMAKELISTS_FILE_TYPE_NONE
    # nothing to be logged here
  when CMAKELISTS_FILE_TYPE_CUSTOM
    log_info "existing #{str_cmakelists_file} is custom, \"native\" form --> skipping!"
    want_cmakelists_rewritten = false
  when CMAKELISTS_FILE_TYPE_V2C_ROOT
    # It's our special V2C source root skeleton file --> replace it
    # (rationale: project-local file is supposed to be able to do everything
    # that our root file does; plus if there's an IDE project in the root
    # directory, then we _need_ to convert it, and that means getting rid of
    # any *same-name* skeleton file).
    log_info "existing #{str_cmakelists_file} is our own auto-generated skeleton root directory file --> replacing!"
  when CMAKELISTS_FILE_TYPE_V2C_LOCAL
    # ok, it _is_ a CMakeLists.txt, but a temporary vcproj2cmake one
    # which we can overwrite.
    log_info "existing #{str_cmakelists_file} is our own auto-generated file --> replacing!"
  else
    error_unknown_case_value('CMakeLists.txt type', cmakelists_type)
    want_cmakelists_rewritten = false # keep it safe - encode a skip instruction anyway
  end
  return want_cmakelists_rewritten
end

def v2c_source_root_write_projects_list_file(output_file_fqpn, output_file_permissions, arr_project_subdirs)
  # write into temporary file, to avoid corrupting previous file due to syntax error abort, disk space or failure issues
  generate_projects_list = V2C_GenerateIntoTempFile.new('projects list file', 'vcproj2cmake_recursive', output_file_fqpn)
  generate_projects_list.generate { |textOut|
    projects_list_generator = V2C_CMakeSyntaxGenerator.new(textOut)
    arr_project_subdirs.each { |subdir|
      projects_list_generator.add_subdirectory(subdir)
    }
  }
end


# Class extended with root/solution location specific parts
# in addition to standard handling of content of a local CMakeLists.txt
# file.
class V2C_CMakeRootFileContentGenerator < V2C_CMakeLocalFileContentGenerator
  def initialize(textOut, projects_list_file, script_location_relative_to_master)
    super(textOut, '.', Pathname.new('.'), [ ], script_location_relative_to_master)
    @projects_list_file = projects_list_file
  end
  def generate_footer
    next_paragraph()
    put_projects_list_file_include()
    super
  end
  def put_projects_list_file_include
    write_comment_at_level(COMMENT_LEVEL_MINIMUM,
      "Includes the generated file that adds all sub directories\n" \
      "which contain projects converted by V2C."
    )
    # TODO: once vcproj2cmake_func.cmake is available at this point in
    # time, should invoke a V2C helper macro instead which does that.
    write_include(@projects_list_file)
  end
end

def v2c_source_root_write_cmakelists_skeleton_file(p_master_project, p_script, path_cmakelists_txt, projects_list_file)
  generate_skeleton = V2C_GenerateIntoTempFile.new('root skeleton CMakeLists.txt', 'vcproj2cmake_root_skeleton', path_cmakelists_txt)
  generate_skeleton.generate { |textOut|
    script_location_relative_to_master = p_script.relative_path_from(p_master_project)
    content_generator = V2C_CMakeRootFileContentGenerator.new(textOut, projects_list_file, script_location_relative_to_master)
    content_generator.generate
  }
end

# For collections of project configs,
# create a skeleton fallback root file whenever there's no user-provided main file
# pre-existing:
# FIXME: conflicts with the "V2C-generated project file" case, will overwrite!!!
def v2c_source_root_ensure_usable_cmakelists_skeleton_file(project_converter_script_filename, source_root, projects_list_file)
  root_cmakelists_txt_file = "#{source_root}/CMakeLists.txt"
  root_cmakelists_txt_type = check_cmakelists_txt_type(root_cmakelists_txt_file)
  skip_skeleton_root_file_reason = nil
  case root_cmakelists_txt_type
  when CMAKELISTS_FILE_TYPE_NONE, CMAKELISTS_FILE_TYPE_ZERO_SIZE, CMAKELISTS_FILE_TYPE_V2C_ROOT
  when CMAKELISTS_FILE_TYPE_CUSTOM
    skip_skeleton_root_file_reason = 'custom/modified file content'
  when CMAKELISTS_FILE_TYPE_V2C_LOCAL
    skip_skeleton_root_file_reason = 'local project sub dir type CMakeLists.txt file'
  else
    raise V2C_GeneratorError, 'unknown/unsupported/corrupt CMakeLists.txt type value!'
  end

  file_descr = 'initially usable skeleton file'
  if nil == skip_skeleton_root_file_reason
    begin
      log_info "Creating/updating an #{file_descr} at #{root_cmakelists_txt_file}"
      script_location = File.expand_path(project_converter_script_filename)
      p_script = Pathname.new(script_location)
      v2c_source_root_write_cmakelists_skeleton_file(Pathname.new(source_root), p_script, root_cmakelists_txt_file, projects_list_file)
    rescue
      log_error "FAILED to create #{root_cmakelists_txt_file}, aborting!"
      raise
    end
  else
    log_info "Skipping create of an #{file_descr} (#{skip_skeleton_root_file_reason})."
  end
end


def v2c_convert_project_inner(p_script, p_master_project, arr_p_parser_proj_files, p_generator_proj_file)

  arr_projects = Array.new

  arr_p_parser_proj_files.each { |p_parser_proj_file|
    log_info "About to parse #{p_parser_proj_file}"
    parser_project_extension = p_parser_proj_file.extname
    # Q&D parser switch...
    parser = nil # IMPORTANT: reset it!
    case parser_project_extension
    when '.vcproj'
      parser = V2C_VS7ProjectFilesBundleParser.new(p_parser_proj_file, arr_projects)
    when '.vfproj'
      log_warn 'Detected Fortran .vfproj - parsing is VERY experimental, needs much more work!'
      parser = V2C_VS7ProjectFilesBundleParser.new(p_parser_proj_file, arr_projects)
    when '.vcxproj'
      parser = V2C_VS10ProjectFilesBundleParser.new(p_parser_proj_file, arr_projects)
    else
      parser = nil
    end

    if not parser.nil?
      parser.parse
    else
      log_implementation_bug "No project parser found for project file #{p_parser_proj_file.to_s}!?"
    end
  }

  arr_projects.each { |proj|
    log_debug "Parsed project #{proj.name}."
  }

  # FIXME VERY DIRTY interim handling:
  arr_projects.each { |project_info|
    next if true == project_info.have_build_units
    project_info.file_lists.arr_file_lists.each { |file_list|
      arr_file_infos = file_list.arr_files
      have_build_units = check_have_build_units_in_file_list(arr_file_infos)
      if true == have_build_units
        project_info.have_build_units = have_build_units
        break
      end
    }
  }

  # Now validate the project...
  # This validation step should be _separate_ from both parser _and_ generator implementations,
  # since otherwise each individual parser/generator would have to remember carrying out validation
  # (they could easily forget about that).
  # Besides, parsing/generating should be concerned about fast (KISS)
  # parsing/generating only anyway.
  arr_projects.delete_if { |project|
    project_valid = true
    begin
      validator = V2C_ProjectValidator.new(project)
      validator.validate
    rescue V2C_ValidationError => e
      project_valid = false
      error_msg = "project validation failed: #{e.message}"
      log_error error_msg
      if ($v2c_validate_vcproj_abort_on_error > 0)
        raise # escalate the problem
      end
    rescue Exception => e
      logger.unhandled_exception(e, 'project validation')
      raise
    end
    (false == project_valid)
  }

  begin
    # TODO: it's probably a valid use case to want to generate
    # multiple build environments from the parsed projects.
    # In such case the set of generators should be available
    # at user configuration side, and the configuration/mappings part
    # (currently sitting at cmake/vcproj2cmake/ at default setting)
    # should be distinctly provided for each generator, too.
    generator = nil
    if true
      generator = V2C_CMakeLocalFileGenerator.new(p_script, p_master_project, p_generator_proj_file, arr_projects)
    end

    if not generator.nil?
      generator.generate
    end
  end
end

# Treat non-normalized ("raw") input arguments as needed,
# then pass on to inner function.
def v2c_convert_project_outer(project_converter_script_filename, master_project_dir, arr_parser_proj_files, generator_proj_file)
  arr_p_parser_proj_files = arr_parser_proj_files.collect { |parser_proj_file|
    Pathname.new(parser_proj_file)
  }
  p_generator_proj_file = Pathname.new(generator_proj_file)
  master_project_location = File.expand_path(master_project_dir)
  p_master_project = Pathname.new(master_project_location)

  script_location = File.expand_path(project_converter_script_filename)
  p_script = Pathname.new(script_location)

  v2c_convert_project_inner(p_script, p_master_project, arr_p_parser_proj_files, p_generator_proj_file)
end

# Writes the final message.
def v2c_convert_finished()
  log_info %{\
Finished. You should make sure to have all important v2c settings includes such as vcproj2cmake_defs.cmake somewhere in your CMAKE_MODULE_PATH}
end
