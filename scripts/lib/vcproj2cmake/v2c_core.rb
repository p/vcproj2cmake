require 'vcproj2cmake/util_file' # V2C_Util_File.cmp()

def load_configuration_file(str_file, str_descr, arr_descr_loaded)
  begin
  success = true # be optimistic :)
    load str_file
    arr_descr_loaded.push("#{str_descr} #{str_file}")
  rescue LoadError
    success = false
  end
  return success
end

def load_configuration
  # FIXME: we should be offering instances of configuration classes!
  # That way, rather than having the user possibly _create_ ad-hoc global
  # variables, we'll have a restricted set of class members which the
  # user may modify --> the user will _know_ immediately in case
  # a now non-existent variable gets modified
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

# global variable to indicate whether we want debug output or not
# FIXME: deprecated, always directly use $v2c_log_level instead.
$v2c_debug = ($v2c_log_level >= 4)

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
  if plugin_parser.version == 1
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
  if f_plugin =~ PLUGIN_FILE_REGEX_OBJ
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


def log_debug(str)
  return if not $v2c_debug
  puts str
end

def log_info(str)
  # We choose to not log an INFO: prefix (reduce log spew).
  puts str
end

def log_todo(str); puts "TODO: #{str}" end

def log_warn(str); puts "WARNING: #{str}" end

def log_error(str); $stderr.puts "ERROR: #{str}" end

# FIXME: should probably replace most log_fatal()
# with exceptions since in many cases
# one would want to have _partial_ aborts of processing only.
# Soft error handling via exceptions would apply to errors due to problematic input -
# but errors due to bugs in our code should cause immediate abort.
def log_fatal(str); log_error "#{str}. Aborting!"; exit 1 end

def log_implementation_bug(str); log_fatal(str) end

# Change \ to /, and remove leading ./
def normalize_path(p)
  felems = p.tr('\\', '/').split('/')
  # DON'T eradicate single '.' !!
  felems.shift if felems[0] == '.' and felems.size > 1
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

COMMENT_LINE_REGEX_OBJ = %r{^\s*#}
def read_mappings(filename_mappings, mappings)
  # line format is: "tag:PLATFORM1:PLATFORM2=tag_replacement2:PLATFORM3=tag_replacement3"
  if File.exists?(filename_mappings)
    #Hash[*File.read(filename_mappings).scan(/^(.*)=(.*)$/).flatten]
    File.open(filename_mappings, 'r').each do |line|
      next if line =~ COMMENT_LINE_REGEX_OBJ
      b, c = line.chomp.split(':')
      mappings[b] = c
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
  read_mappings("#{master_project_dir}/#{filename_mappings}", mappings)
end

def push_platform_defn(platform_defs, platform, defn_value)
  #log_debug "adding #{defn_value} on platform #{platform}"
  if platform_defs[platform].nil?; platform_defs[platform] = Array.new end
  platform_defs[platform].push(defn_value)
end

def parse_platform_conversions(platform_defs, arr_defs, map_defs)
  arr_defs.each { |curr_defn|
    #log_debug map_defs[curr_defn]
    map_line = map_defs[curr_defn]
    if map_line.nil?
      # hmm, no direct match! Try to figure out whether any map entry
      # is a regex which would match our curr_defn
      map_defs.each do |key_regex, value|
        if curr_defn =~ /^#{key_regex}$/
          log_debug "KEY: #{key_regex} curr_defn #{curr_defn}"
          map_line = value
          break
        end
      end
    end
    if map_line.nil?
      # no mapping? --> unconditionally use the original define
      push_platform_defn(platform_defs, 'ALL', curr_defn)
    else
      # Tech note: chomp on map_line should not be needed as long as
      # original constant input has already been pre-treated (chomped).
      map_line.split('|').each do |platform_element|
        #log_debug "platform_element #{platform_element}"
        platform, replacement_defn = platform_element.split('=')
        if platform.empty?
          # specified a replacement without a specific platform?
          # ("tag:=REPLACEMENT")
          # --> unconditionally use it!
          platform = 'ALL'
        else
          if replacement_defn.nil?
            replacement_defn = curr_defn
          end
        end
        push_platform_defn(platform_defs, platform, replacement_defn)
      end
    end
  }
end

# IMPORTANT NOTE: the generator/target/parser class hierarchy and _naming_
# is supposed to be eerily similar to the one used by CMake.
# Dito for naming of individual methods...
#
# Global generator: generates/manages parts which are not project-local/target-related (i.e., manages things related to the _entire solution_ configuration)
# local generator: has a Makefile member (which contains a list of targets),
#   then generates project files by iterating over the targets via a newly generated target generator each.
# target generator: generates targets. This is the one creating/producing the output file stream. Not provided by all generators (VS10 yes, VS7 no).

class V2C_Info_Condition
  def initialize(str_condition)
    @str_condition = str_condition
  end
end

# @brief Mostly used to manage the condition element...
class V2C_Info_Elem_Base
  def initialize
    @condition = nil # V2C_Info_Condition
  end
end

class V2C_Info_Include_Dir < V2C_Info_Elem_Base
  def initialize
    super()
    @dir = String.new
    @attr_after = 0
    @attr_before = 0
    @attr_system = 0
  end
  attr_accessor :dir
  attr_accessor :attr_after
  attr_accessor :attr_before
  attr_accessor :attr_system
end

# Not sure whether we really need this base class -
# do we really want to know the tool name??
class V2C_Tool_Base_Info
  def initialize
    @name = nil
    @suppress_startup_banner_enable = false # used by at least VS10 Compiler _and_ Linker, thus it's member of the common base class.
  end
  attr_accessor :name
  attr_accessor :suppress_startup_banner_enable
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

class V2C_Tool_Compiler_Info < V2C_Tool_Base_Info
  def initialize
    super()
    @arr_info_include_dirs = Array.new
    @hash_defines = Hash.new
    @rtti = true
    @precompiled_header_info = nil
    @detect_64bit_porting_problems_enable = true # TODO: translate into MSVC /Wp64 flag; Enabled by default is preferable, right?
    @exception_handling = 1 # we do want it enabled, right? (and as Sync?)
    @multi_core_compilation_enable = false # TODO: translate into MSVC10 /MP flag...; Disabled by default is preferable (some builds might not have clean target dependencies...)
    @warnings_are_errors_enable = false # TODO: translate into MSVC /WX flag
    @show_includes_enable = false # TODO: translate into MSVC /showIncludes flag
    @static_code_analysis_enable = false # TODO: translate into MSVC7/10 /analyze flag
    @optimization = 0 # currently supporting these values: 0 == Non Debug, 1 == Min Size, 2 == Max Speed, 3 == Max Optimization
    @show_includes = false # Whether to show the filenames of included header files.
    @arr_compiler_specific_info = Array.new
  end
  attr_accessor :arr_info_include_dirs
  attr_accessor :hash_defines
  attr_accessor :rtti
  attr_accessor :precompiled_header_info
  attr_accessor :detect_64bit_porting_problems_enable
  attr_accessor :exception_handling
  attr_accessor :multi_core_compilation_enable
  attr_accessor :warnings_are_errors_enable
  attr_accessor :show_includes_enable
  attr_accessor :static_code_analysis_enable
  attr_accessor :optimization
  attr_accessor :show_includes
  attr_accessor :arr_compiler_specific_info

  def get_include_dirs(flag_system, flag_before)
    arr_includes = Array.new
    arr_info_include_dirs.each { |inc_dir_info|
      # TODO: evaluate flag_system and flag_before
      # and collect only those dirs that match these settings
      # (equivalent to CMake include_directories() SYSTEM / BEFORE).
      arr_includes.push(inc_dir_info.dir)
    }  
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

class V2C_Tool_Linker_Specific_Info_MSVC7 < V2C_Tool_Linker_Specific_Info
  def initialize()
    super('MSVC7')
  end
end

class V2C_Tool_Linker_Specific_Info_MSVC10 < V2C_Tool_Linker_Specific_Info
  def initialize()
    super('MSVC10')
  end
end

class V2C_Tool_Linker_Info < V2C_Tool_Base_Info
  def initialize(linker_specific_info = nil)
    super()
    @arr_dependencies = Array.new # FIXME: should be changing this into a dependencies class (we need an attribute which indicates whether this dependency is a library _file_ or a target name, since we should be reliably able to decide whether we can add "debug"/"optimized" keywords to CMake variables or target_link_library() parms)
    @link_incremental = 0 # 1 means NO, thus 2 probably means YES?
    @module_definition_file = nil
    @optimize_references_enable = false
    @pdb_file = nil
    @arr_lib_dirs = Array.new
    @arr_linker_specific_info = Array.new
    if not linker_specific_info.nil?
      linker_specific_info.original = true
      @arr_linker_specific_info.push(linker_specific_info)
    end
  end
  attr_accessor :arr_dependencies
  attr_accessor :link_incremental
  attr_accessor :module_definition_file
  attr_accessor :optimize_references_enable
  attr_accessor :pdb_file
  attr_accessor :arr_lib_dirs
  attr_accessor :arr_linker_specific_info
end

module V2C_BaseConfig_Defines
  CHARSET_SBCS = 0
  CHARSET_UNICODE = 1
  CHARSET_MBCS = 2
  MFC_FALSE = 0
  MFC_STATIC = 1
  MFC_DYNAMIC = 2
end

# Common base class of both file config and project config.
class V2C_Config_Base_Info < V2C_Info_Elem_Base
  def initialize
    @build_type = '' # WARNING: it may contain spaces!
    @platform = ''
    @cfg_type = 0

    # 0 == no MFC
    # 1 == static MFC
    # 2 == shared MFC
    @use_of_mfc = 0 # TODO: perhaps make ATL/MFC values an enum?
    @use_of_atl = 0
    @charset = 0 # Simply uses VS7 values for now. TODO: should use our own enum definition or so.
    @whole_program_optimization = 0 # Simply uses VS7 values for now. TODO: should use our own enum definition or so.; it seems for CMake the related setting is target/directory property INTERPROCEDURAL_OPTIMIZATION_<CONFIG> (described by Wikipedia "Interprocedural optimization")
    @use_debug_libs = false
    @arr_compiler_info = Array.new
    @arr_linker_info = Array.new
  end
  attr_accessor :build_type
  attr_accessor :platform
  attr_accessor :cfg_type
  attr_accessor :use_of_mfc
  attr_accessor :use_of_atl
  attr_accessor :charset
  attr_accessor :whole_program_optimization
  attr_accessor :use_debug_libs
  attr_accessor :arr_compiler_info
  attr_accessor :arr_linker_info
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

# FIXME UNUSED
class V2C_Makefile
  def initialize
    @config_info = V2C_Project_Config_Info.new
  end

  attr_accessor :config_info
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

class V2C_Filters_Container
  def initialize
    @arr_filters = Array.new # the array which contains V2C_Info_Filter elements. Now supported by VS10 parser. FIXME: rework VS7 parser to also create a linear array of filters!
    # In addition to the filters Array, we also need a filters Hash
    # for fast lookup when intending to insert a new file item of the project.
    # There's now a new ordered hash which might preserve the ordering
    # as guaranteed by an Array, but it's too new (Ruby 1.9!).
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
end

class V2C_File_List_Info
  include V2C_File_List_Types
  def initialize(name, type = TYPE_NONE)
    @name = name # VS10: One of None, ClCompile, ClInclude, ResourceCompile; VS7: the name of the filter that contains these files
    @type = type
    @arr_files = Array.new
  end
  attr_accessor :name
  attr_accessor :type
  attr_accessor :arr_files
  def get_list_type_name()
    list_types =
     [ 'unknown', # VS10: None
       'sources', # VS10: ClCompile
       'headers', # VS10: ClInclude
       'resources' # VS10: ResourceCompile
     ]
    type = @type <= TYPE_RESOURCES ? @type : TYPE_NONE
    return list_types[type]
  end
end

class V2C_File_Lists_Container
  def initialize
    @file_lists = Array.new
  end
  def get(file_list_type, file_list_name)
    #log_fatal "get!!"
  end
end

# Well, in fact in Visual Studio, "target" and "project"
# seem to be pretty much synonymous...
# FIXME: we should still do better separation between these two...
class V2C_Project_Info # formerly V2C_Target
  def initialize
    @type = nil # project type
    # VS10: in case the main project file is lacking a ProjectName element,
    # the project will adopt the _exact name part_ of the filename,
    # thus enforce this ctor taking a project name to use as a default if no ProjectName element is available:
    @name = nil

    # the original environment (build environment / IDE)
    # which defined the project (MSVS7, MSVS10 - Visual Studio, etc.).
    # _Short_ name - may NOT contain whitespace.
    # Perhaps we should also be supplying a long name, too? ('Microsoft Visual Studio 7')
    @orig_environment_shortname = nil
    @creator = nil # VS7 "ProjectCreator" setting
    @guid = nil
    @root_namespace = nil
    @version = nil

    # .vcproj Keyword attribute ("Win32Proj", "MFCProj", "ATLProj", "MakeFileProj", "Qt4VSv1.0").
    # TODO: should perhaps do Keyword-specific post-processing at generator
    # (to enable Qt integration, etc.):
    @vs_keyword = nil
    @scc_info = V2C_SCC_Info.new
    @arr_config_info = Array.new
    @file_lists = V2C_File_Lists_Container.new
    @filters = V2C_Filters_Container.new
    @main_files = nil # FIXME get rid of this VS7 crap, rework file list/filters handling there!
    # semi-HACK: we need this variable, since we need to be able
    # to tell whether we're able to build a target
    # (i.e. whether we have any build units i.e.
    # implementation files / non-header files),
    # otherwise we should not add a target since CMake will
    # complain with "Cannot determine link language for target "xxx"".
    @have_build_units = false
  end

  attr_accessor :type
  attr_accessor :name
  attr_accessor :orig_environment_shortname
  attr_accessor :creator
  attr_accessor :guid
  attr_accessor :root_namespace
  attr_accessor :version
  attr_accessor :vs_keyword
  attr_accessor :scc_info
  attr_accessor :arr_config_info
  attr_accessor :file_lists
  attr_accessor :filters
  attr_accessor :main_files
  attr_accessor :have_build_units
end

class V2C_ValidationError < StandardError
end

class V2C_ProjectValidator
  def initialize(project_info)
    @project_info = project_info
  end
  def validate
    #log_debug "project data: #{@project_info.inspect}"
    if @project_info.orig_environment_shortname.nil?; validation_error('original environment not set!?') end
    if @project_info.name.nil?; validation_error('name not set!?') end
    # FIXME: Disabled for TESTING only - should re-enable this check once VS10 parsing is complete.
    #if @project_info.main_files.nil?; validation_error('no files!?') end
    arr_config_info = @project_info.arr_config_info
    if arr_config_info.nil? or arr_config_info.length == 0
      validation_error('no config information!?')
    end
  end
  def validation_error(str_message)
    raise V2C_ValidationError, "Project: #{str_message}; #{@project_info.inspect}"
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


CMAKE_VAR_MATCH_REGEX_STR = '\\$\\{[[:alnum:]_]+\\}'
CMAKE_IS_LIST_VAR_CONTENT_REGEX_OBJ = %r{^".*;.*"$}
CMAKE_ENV_VAR_MATCH_REGEX_STR = '\\$ENV\\{[[:alnum:]_]+\\}'

# Contains functionality common to _any_ file-based generator
class V2C_TextStreamSyntaxGeneratorBase
  def initialize(out, indent_start, indent_step, comments_level)
    @out = out
    @indent_now = indent_start
    @indent_step = indent_step
    @comments_level = comments_level
  end

  def generated_comments_level; return @comments_level end

  def get_indent; return @indent_now end

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
    @out.puts part
  end

  def write_empty_line; @out.puts end
  def write_new_line(part)
    write_empty_line()
    write_line(part)
  end
end

#class V2C_CMakeSyntaxGenerator < V2C_TextStreamSyntaxGeneratorBase
# FIXME: most likely V2C_CMakeSyntaxGenerator should _not_ be the base class
# of other CMake generator classes, but rather a _member_ of those classes only.
# Reasoning: that class implements the border crossing towards specific CMake syntax,
# i.e. it is the _only one_ to know specific CMake syntax (well, "ideally", I have to say, currently).
# If it was the base class of the various CMake generators,
# then it would be _hard-coded_ i.e. not configurable (which would be the case
# when having ctor parameterisation from the outside).
class V2C_CMakeSyntaxGenerator
  VCPROJ2CMAKE_FUNC_CMAKE = 'vcproj2cmake_func.cmake'
  V2C_ATTRIBUTE_NOT_PROVIDED_MARKER = 'V2C_NOT_PROVIDED'
  def initialize(textOut)
    @textOut = textOut
    # internal CMake generator helpers
  end

  def next_paragraph()
    @textOut.write_empty_line()
  end
  def write_comment_at_level(level, block)
    return if @textOut.generated_comments_level() < level
    block.split("\n").each { |line|
      @textOut.write_line("# #{line}")
    }
  end
  # TODO: ideally we would do single-line/multi-line splitting operation _automatically_
  # (and bonus points for configure line length...)
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
  def dereference_variable_name(str_var); return "${#{str_var}}" end

  def get_var_conditional_command(command_name); return "COMMAND #{command_name}" end

  def get_conditional_inverted(str_conditional); return "NOT #{str_conditional}" end
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
  def get_keyword_bool(setting); return setting ? 'true' : 'false' end
  def write_set_var(var_name, setting)
    arr_args_func = [ setting ]
    write_command_list('set', var_name, arr_args_func)
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
    arr_args_func = [ setting ]
    write_command_list_quoted('set', var_name, arr_args_func)
  end
  def write_include(include_file, optional = false)
    arr_args_include_file = [ element_handle_quoting(include_file) ]
    arr_args_include_file.push('OPTIONAL') if optional
    write_command_list('include', nil, arr_args_include_file)
  end
  def write_include_from_cmake_var(include_file_var, optional = false)
    write_include(dereference_variable_name(include_file_var), optional)
  end
  def write_vcproj2cmake_func_comment()
    write_comment_at_level(2, "See function implementation/docs in #{$v2c_module_path_root}/#{VCPROJ2CMAKE_FUNC_CMAKE}")
  end
  def write_cmake_policy(policy_num, set_to_new, comment)
    str_policy = '%s%04d' % [ 'CMP', policy_num ]
    str_conditional = "POLICY #{str_policy}"
    write_conditional_if(str_conditional)
      if not comment.nil?
        write_comment_at_level(3, comment)
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
    arr_elems.push('FILES', dereference_variable_name(source_files_variable))
    # Use multi-line method since source_group() arguments can be very long.
    write_command_list_quoted('source_group', source_group_name, arr_elems)
  end
  def put_include_directories(arr_directories, flag_system=false, flag_before=false)
    arr_args = Array.new
    arr_args.push('SYSTEM') if flag_system
    arr_args.push('BEFORE') if flag_before
    arr_args.concat(arr_directories)
    write_command_list_quoted('include_directories', nil, arr_args)
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
    if elem.match(CMAKE_STRING_NEEDS_QUOTING_REGEX_OBJ)
      content_needs_quoting = true
    end
    if elem.match(CMAKE_STRING_HAS_QUOTES_REGEX_OBJ)
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
    return (not str_elem.match(CMAKE_IS_LIST_VAR_CONTENT_REGEX_OBJ).nil?)
  end
end

class V2C_CMakeGlobalGenerator < V2C_CMakeSyntaxGenerator
  def put_configuration_types(configuration_types)
    configuration_types_list = separate_arguments(configuration_types)
    write_set_var_quoted('CMAKE_CONFIGURATION_TYPES', configuration_types_list)
  end

  private
end

class V2C_CMakeLocalGenerator < V2C_CMakeSyntaxGenerator
  def initialize(textOut)
    super(textOut)
    # FIXME: handle arr_config_var_handling appropriately
    # (place the translated CMake commands somewhere suitable)
    @arr_config_var_handling = Array.new
  end
  def put_file_header
    put_file_header_temporary_marker()
    put_file_header_cmake_minimum_version()
    put_file_header_cmake_policies()

    put_cmake_module_path()
    put_var_config_dir_local()
    put_include_vcproj2cmake_func()
    put_hook_pre()
  end
  def put_project(project_name, arr_languages = nil)
    arr_args_project_name_and_attrs = [ project_name ]
    if not arr_languages.nil?; arr_args_project_name_and_attrs.concat(arr_languages) end
    write_command_list_single_line('project', arr_args_project_name_and_attrs)
  end
  def put_conversion_details(project_name, orig_environment_shortname)
    # We could have stored all information in one (list) variable,
    # but generating two lines instead of one isn't much waste
    # and actually much easier to parse.
    put_converted_timestamp(project_name)
    put_converted_from_marker(project_name, orig_environment_shortname)
  end
  def put_include_MasterProjectDefaults_vcproj2cmake
    if @textOut.generated_comments_level() >= 2
      @textOut.write_data %{\

# this part is for including a file which contains
# _globally_ applicable settings for all sub projects of a master project
# (compiler flags, path settings, platform stuff, ...)
# e.g. have vcproj2cmake-specific MasterProjectDefaults_vcproj2cmake
# which then _also_ includes a global MasterProjectDefaults module
# for _all_ CMakeLists.txt. This needs to sit post-project()
# since e.g. compiler info is dependent on a valid project.
}
      @textOut.write_block( \
	"# MasterProjectDefaults_vcproj2cmake is supposed to define generic settings\n" \
        "# (such as V2C_HOOK_PROJECT, defined as e.g.\n" \
        "# #{$v2c_config_dir_local}/hook_project.txt,\n" \
        "# and other hook include variables below).\n" \
        "# NOTE: it usually should also reset variables\n" \
        "# V2C_LIBS, V2C_SOURCES etc. as used below since they should contain\n" \
        "# directory-specific contents only, not accumulate!" \
      )
    end
    # (side note: see "ldd -u -r" on Linux for superfluous link parts potentially caused by this!)
    write_include('MasterProjectDefaults_vcproj2cmake', true)
  end
  def put_hook_project
    write_comment_at_level(2, \
	"hook e.g. for invoking Find scripts as expected by\n" \
	"the _LIBRARIES / _INCLUDE_DIRS mappings created\n" \
	"by your include/dependency map files." \
    )
    write_include_from_cmake_var('V2C_HOOK_PROJECT', true)
  end

  def put_include_project_source_dir
    # AFAIK .vcproj implicitly adds the project root to standard include path
    # (for automatic stdafx.h resolution etc.), thus add this
    # (and make sure to add it with high priority, i.e. use BEFORE).
    # For now sitting in LocalGenerator and not per-target handling since this setting is valid for the entire directory.
    next_paragraph()
    arr_directories = [ dereference_variable_name('PROJECT_SOURCE_DIR') ]
    put_include_directories(arr_directories, false, true)
  end
  def put_cmake_mfc_atl_flag(config_info)
    # Hmm, do we need to actively _reset_ CMAKE_MFC_FLAG / CMAKE_ATL_FLAG
    # (i.e. _unconditionally_ set() it, even if it's 0),
    # since projects in subdirs shouldn't inherit?
    # Given the discussion at
    # "[CMake] CMAKE_MFC_FLAG is inherited in subdirectory ?"
    #   http://www.cmake.org/pipermail/cmake/2009-February/026896.html
    # I'd strongly assume yes...
    # See also "Re: [CMake] CMAKE_MFC_FLAG not working in functions"
    #   http://www.mail-archive.com/cmake@cmake.org/msg38677.html

    #if config_info.use_of_mfc > V2C_BaseConfig_Defines::MFC_FALSE
      write_set_var('CMAKE_MFC_FLAG', config_info.use_of_mfc)
    #end
    # ok, there's no CMAKE_ATL_FLAG yet, AFAIK, but still prepare
    # for it (also to let people probe on this in hook includes)
    # FIXME: since this flag does not exist yet yet MFC sort-of
    # includes ATL configuration, perhaps as a workaround one should
    # set the MFC flag if use_of_atl is true?
    #if config_info.use_of_atl > 0
      # TODO: should also set the per-configuration-type variable variant
      write_set_var('CMAKE_ATL_FLAG', config_info.use_of_atl)
    #end
  end
  def write_include_directories(arr_includes, map_includes)
    # Side note: unfortunately CMake as of 2.8.7 probably still does not have
    # a # way of specifying _per-configuration_ syntax of include_directories().
    # See "[CMake] vcproj2cmake.rb script: announcing new version / hosting questions"
    #   http://www.cmake.org/pipermail/cmake/2010-June/037538.html
    #
    # Side note #2: relative arguments to include_directories() (e.g. "..")
    # are relative to CMAKE_PROJECT_SOURCE_DIR and _not_ BINARY,
    # at least on Makefile and .vcproj.
    # CMake dox currently don't offer such details... (yet!)
    return if arr_includes.empty?
    arr_includes_translated = Array.new
    arr_includes.each { |elem_inc_dir|
      elem_inc_dir = vs7_create_config_variable_translation(elem_inc_dir, @arr_config_var_handling)
      arr_includes_translated.push(elem_inc_dir)
    }
    write_build_attributes('include_directories', arr_includes_translated, map_includes, nil)
  end

  def write_link_directories(arr_lib_dirs, map_lib_dirs)
    arr_lib_dirs_translated = Array.new
    arr_lib_dirs.each { |elem_lib_dir|
      elem_lib_dir = vs7_create_config_variable_translation(elem_lib_dir, @arr_config_var_handling)
      arr_lib_dirs_translated.push(elem_lib_dir)
    }
    arr_lib_dirs_translated.push(dereference_variable_name('V2C_LIB_DIRS'))
    write_comment_at_level(3, \
      "It is said to be much preferable to be able to use target_link_libraries()\n" \
      "rather than the very unspecific link_directories()." \
    )
    write_build_attributes('link_directories', arr_lib_dirs_translated, map_lib_dirs, nil)
  end
  def write_directory_property_compile_flags(attr_opts)
    return if attr_opts.nil?
    next_paragraph()
    # Query WIN32 instead of MSVC, since AFAICS there's nothing in the
    # .vcproj to indicate tool specifics, thus these seem to
    # be settings for ANY PARTICULAR tool that is configured
    # on the Win32 side (.vcproj in general).
    str_platform = 'WIN32'
    write_conditional_if(str_platform)
      write_command_single_line('set_property', "DIRECTORY APPEND PROPERTY COMPILE_FLAGS #{attr_opts}")
    write_conditional_end(str_platform)
  end
  # FIXME private!
  def write_build_attributes(cmake_command, arr_defs, map_defs, cmake_command_arg)
    # the container for the list of _actual_ dependencies as stated by the project
    all_platform_defs = Hash.new
    parse_platform_conversions(all_platform_defs, arr_defs, map_defs)
    all_platform_defs.each { |key, arr_platdefs|
      #log_info "arr_platdefs: #{arr_platdefs}"
      next if arr_platdefs.empty?
      arr_platdefs.uniq!
      next_paragraph()
      str_platform = key if not key.eql?('ALL')
      write_conditional_if(str_platform)
        write_command_list_quoted(cmake_command, cmake_command_arg, arr_platdefs)
      write_conditional_end(str_platform)
    }
  end
  def put_var_converter_script_location(script_location_relative_to_master)
    # For the CMakeLists.txt rebuilder (automatic rebuild on file changes),
    # add handling of a script file location variable, to enable users
    # to override the script location if needed.
    next_paragraph()
    write_comment_at_level(1, \
      "user override mechanism (allow defining custom location of script)" \
    )
    # NOTE: we'll make V2C_SCRIPT_LOCATION express its path via
    # relative argument to global CMAKE_SOURCE_DIR and _not_ CMAKE_CURRENT_SOURCE_DIR,
    # (this provision should even enable people to manually relocate
    # an entire sub project within the source tree).
    write_set_var_if_unset(
      'V2C_SCRIPT_LOCATION',
      element_manual_quoting("${CMAKE_SOURCE_DIR}/#{script_location_relative_to_master}")
    )
  end
  def write_func_v2c_project_post_setup(project_name, orig_project_file_basename)
    # Rationale: keep count of generated lines of CMakeLists.txt to a bare minimum -
    # call v2c_project_post_setup(), by simply passing all parameters that are _custom_ data
    # of the current generated CMakeLists.txt file - all boilerplate handling functionality
    # that's identical for each project should be implemented by the v2c_project_post_setup() function
    # _internally_.
    write_vcproj2cmake_func_comment()
    arr_args_func = [ "${CMAKE_CURRENT_SOURCE_DIR}/#{orig_project_file_basename}", dereference_variable_name('CMAKE_CURRENT_LIST_FILE') ]
    write_invoke_config_object_function_quoted('v2c_project_post_setup', project_name, arr_args_func)
  end

  private

  def put_file_header_temporary_marker
    # WARNING: since this comment header is meant to advertise
    # _generated_ vcproj2cmake files, user-side code _will_ check for this
    # particular wording to tell apart generated CMakeLists.txt from
    # custom-written ones, thus one should definitely avoid changing
    # this phrase.
    @textOut.write_data %{\
#
# TEMPORARY Build file, AUTO-GENERATED by http://vcproj2cmake.sf.net
# DO NOT CHECK INTO VERSION CONTROL OR APPLY \"PERMANENT\" MODIFICATIONS!!
#

}
  end
  def put_file_header_cmake_minimum_version
    # Required version line to make cmake happy.
    write_comment_at_level(1, \
      ">= 2.6 due to crucial set_property(... COMPILE_DEFINITIONS_* ...)" \
    )
    write_command_single_line('cmake_minimum_required', 'VERSION 2.6')
  end
  def put_file_header_cmake_policies
    str_conditional = get_var_conditional_command('cmake_policy')
    write_conditional_if(str_conditional)
      # CMP0005: manual quoting of brackets in definitions doesn't seem to work otherwise,
      # in cmake 2.6.4-7.el5 with "OLD".
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
  def put_cmake_module_path
    # try to point to cmake/Modules of the topmost directory of the vcproj2cmake conversion tree.
    # This also contains vcproj2cmake helper modules (these should - just like the CMakeLists.txt -
    # be within the project tree as well, since someone might want to copy the entire project tree
    # including .vcproj conversions to a different machine, thus all v2c components should be available)
    #write_new_line("set(V2C_MASTER_PROJECT_DIR \"#{@master_project_dir}\")")
    next_paragraph()
    write_set_var_quoted('V2C_MASTER_PROJECT_DIR', dereference_variable_name('CMAKE_SOURCE_DIR'))
    # NOTE: use set() instead of list(APPEND...) to _prepend_ path
    # (otherwise not able to provide proper _overrides_)
    arr_args_func = [ "${V2C_MASTER_PROJECT_DIR}/#{$v2c_module_path_local}", dereference_variable_name('CMAKE_MODULE_PATH') ]
    write_list_quoted('CMAKE_MODULE_PATH', arr_args_func)
  end
  # "export" our internal $v2c_config_dir_local variable (to be able to reference it in CMake scripts as well)
  def put_var_config_dir_local; write_set_var_quoted('V2C_CONFIG_DIR_LOCAL', $v2c_config_dir_local) end
  def put_include_vcproj2cmake_func
    next_paragraph()
    write_comment_at_level(2, \
      "include the main file for pre-defined vcproj2cmake helper functions\n" \
      "This module will also include the configuration settings definitions module" \
    )
    write_include('vcproj2cmake_func')
  end
  def put_hook_pre
    # this CMakeLists.txt-global optional include could be used e.g.
    # to skip the entire build of this file on certain platforms:
    # if(PLATFORM) message(STATUS "not supported") return() ...
    # (note that we appended CMAKE_MODULE_PATH _prior_ to this include()!)
    write_include('${V2C_CONFIG_DIR_LOCAL}/hook_pre.txt', true)
  end
  def put_converted_timestamp(project_name)
    # Add an explicit file generation timestamp,
    # to enable easy identification (grepping) of files of a certain age
    # (a filesystem-based creation/modification timestamp might be unreliable
    # due to copying/modification).
    timestamp_format = $v2c_generator_timestamp_format
    return if timestamp_format.nil? or timestamp_format.length == 0
    timestamp_format_docs = timestamp_format.tr('%', '')
    write_comment_at_level(3, "Indicates project conversion moment in time (UTC, format #{timestamp_format_docs})")
    time = Time.new
    str_time = time.utc.strftime(timestamp_format)
    # Add project_name as _prefix_ (keep variables grep:able, via "v2c_converted_at_utc")
    # Since timestamp format now is user-configurable, quote potential whitespace.
    write_set_var("#{project_name}_v2c_converted_at_utc", element_handle_quoting(str_time))
  end
  def put_converted_from_marker(project_name, str_from_buildtool_version)
    write_comment_at_level(3, 'Indicates originating build environment / IDE')
    # Add project_name as _prefix_ (keep variables grep:able, via "v2c_converted_from")
    write_set_var("#{project_name}_v2c_converted_from", element_handle_quoting(str_from_buildtool_version))
  end
end

# Hrmm, I'm not quite sure yet where to aggregate this function...
# (missing some proper generator base class or so...)
def v2c_generator_check_file_accessible(project_dir, file_relative, file_item_description, project_name, throw_error)
  file_accessible = true
  if $v2c_validate_vcproj_ensure_files_ok
    # TODO: perhaps we need to add a permissions check, too?
    file_location = "#{project_dir}/#{file_relative}"
    if not File.exist?(file_location)
      log_error "File #{file_relative} (#{file_item_description}) as listed by project #{project_name} does not exist!? (perhaps filename with wrong case, or wrong path, ...)"
      if throw_error
	# FIXME: should be throwing an exception, to not exit out
	# on entire possibly recursive (global) operation
        # when a single project is in error...
        log_fatal "Improper original file - will abort and NOT generate a broken converted project file. Please fix content of the original project file!"
      end
      file_accessible = false
    end
  end
  return file_accessible
end

# FIXME: temporarily appended a _VS7 suffix since we're currently changing file list generation during our VS10 generator work.
class V2C_CMakeFileListGenerator_VS7 < V2C_CMakeSyntaxGenerator
  def initialize(textOut, project_name, project_dir, files_str, parent_source_group, arr_sub_sources_for_parent)
    super(textOut)
    @project_name = project_name
    @project_dir = project_dir
    @files_str = files_str
    @parent_source_group = parent_source_group
    @arr_sub_sources_for_parent = arr_sub_sources_for_parent
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
  VS7_UNWANTED_FILE_TYPES_REGEX_OBJ = %r{\.(lex|y|ico|bmp|txt)$}
  VS7_IDL_FILE_TYPES_REGEX_OBJ = %r{_(i|p).c$}
  VS7_LIB_FILE_TYPES_REGEX_OBJ = %r{\.lib$}
  def put_file_list_recursive(files_str, parent_source_group, arr_sub_sources_for_parent)
    filter_info = files_str[:filter_info]
    group_name = get_filter_group_name(filter_info)
      log_debug("#{self.class.name}: #{group_name}")
    if not files_str[:arr_sub_filters].nil?
      arr_sub_filters = files_str[:arr_sub_filters]
    end
    if not files_str[:arr_file_infos].nil?
      arr_local_sources = Array.new
      files_str[:arr_file_infos].each { |file|
        f = file.path_relative

	v2c_generator_check_file_accessible(@project_dir, f, 'file item in project', @project_name, ($v2c_validate_vcproj_abort_on_error > 0))

        ## Ignore header files
        #return if f =~ /\.(h|H|lex|y|ico|bmp|txt)$/
        # No we should NOT ignore header files: if they aren't added to the target,
        # then VS won't display them in the file tree.
        next if f =~ VS7_UNWANTED_FILE_TYPES_REGEX_OBJ

        # Verbosely ignore IDL generated files
        if f =~ VS7_IDL_FILE_TYPES_REGEX_OBJ
          # see file_mappings.txt comment above
          log_info "#{@project_name}::#{f} is an IDL generated file: skipping! FIXME: should be platform-dependent."
          included_in_build = false
          next # no complex handling, just skip
        end

        # Verbosely ignore .lib "sources"
        if f =~ VS7_LIB_FILE_TYPES_REGEX_OBJ
          # probably these entries are supposed to serve as dependencies
          # (i.e., non-link header-only include dependency, to ensure
          # rebuilds in case of foreign-library header file changes).
          # Not sure whether these were added by users or
          # it's actually some standard MSVS mechanism... FIXME
          log_info "#{@project_name}::#{f} registered as a \"source\" file!? Skipping!"
          included_in_build = false
          return # no complex handling, just return
        end

        arr_local_sources.push(f)
      }
    end

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
          #log_info "writing: #{subfilter}"
          put_file_list_recursive(subfilter, this_source_group, arr_my_sub_sources)
        }
      @textOut.indent_less()
    end

    source_group_var_suffix = this_source_group.clone.gsub(VS7_UNWANTED_GROUP_TAG_CHARS_MATCH_REGEX_OBJ,'_')

    # process our hierarchy's own files
    if not arr_local_sources.nil?
      source_files_variable = "SOURCES_files_#{source_group_var_suffix}"
      write_list_quoted(source_files_variable, arr_local_sources)
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
      arr_source_vars = Array.new
      # dump sub filters...
      arr_my_sub_sources.each { |sources_elem|
        arr_source_vars.push(dereference_variable_name(sources_elem))
      }
      # ...then our own files
      if not source_files_variable.nil?
        arr_source_vars.push(dereference_variable_name(source_files_variable))
      end
      next_paragraph()
      write_list_quoted(sources_variable, arr_source_vars)
      # add our source list variable to parent return
      arr_sub_sources_for_parent.push(sources_variable)
    end
  end
end

class V2C_CMakeTargetGenerator < V2C_CMakeSyntaxGenerator
  def initialize(target, project_dir, localGenerator, textOut)
    super(textOut)
    @target = target
    @project_dir = project_dir
    @localGenerator = localGenerator
  end

  # File-related TODO:
  # should definitely support the following CMake properties, as needed:
  # PUBLIC_HEADER (cmake --help-property PUBLIC_HEADER), PRIVATE_HEADER, HEADER_FILE_ONLY
  # and possibly the PUBLIC_HEADER option of the INSTALL(TARGETS) command.
  def put_file_list_source_group_recursive(project_name, files_str, parent_source_group, arr_sub_sources_for_parent)
    if files_str.nil?
      puts "ERROR: WHAT THE HELL, NO FILES!?"
      return
    end
    filelist_generator = V2C_CMakeFileListGenerator_VS7.new(@textOut, project_name, @project_dir, files_str, parent_source_group, arr_sub_sources_for_parent)
    filelist_generator.generate
  end
  def put_source_vars(arr_sub_source_list_var_names)
    arr_source_vars = Array.new
    arr_sub_source_list_var_names.each { |sources_elem|
	arr_source_vars.push(dereference_variable_name(sources_elem))
    }
    next_paragraph()
    write_list_quoted('SOURCES', arr_source_vars)
  end
  def put_hook_post_sources; write_include_from_cmake_var('V2C_HOOK_POST_SOURCES', true) end
  def put_hook_post_definitions
    next_paragraph()
    write_comment_at_level(1, \
	"hook include after all definitions have been made\n" \
	"(but _before_ target is created using the source list!)" \
    )
    write_include_from_cmake_var('V2C_HOOK_POST_DEFINITIONS', true)
  end
  #def evaluate_precompiled_header_config(target, files_str)
  #end
  #
  def write_conditional_target_valid_begin
    write_conditional_if(get_var_conditional_target(@target.name))
  end
  def write_conditional_target_valid_end
    write_conditional_end(get_var_conditional_target(@target.name))
  end

  def get_var_conditional_target(target_name); return "TARGET #{target_name}" end

  # FIXME: not sure whether map_lib_dirs etc. should be passed in in such a raw way -
  # probably mapping should already have been done at that stage...
  def put_target(target, arr_sub_source_list_var_names, map_lib_dirs, map_dependencies, config_info_curr)
    target_is_valid = false

    # create a target only in case we do have any meat at all
    #if not main_files[:arr_sub_filters].empty? or not main_files[:arr_file_infos].empty?
    #if not arr_sub_source_list_var_names.empty?
    if target.have_build_units

      # first add source reference, then do linker setup, then create target

      put_source_vars(arr_sub_source_list_var_names)

      # write link_directories() (BEFORE establishing a target!)
      config_info_curr.arr_linker_info.each { |linker_info_curr|
        @localGenerator.write_link_directories(linker_info_curr.arr_lib_dirs, map_lib_dirs)
      }

      target_is_valid = put_target_type(target, map_dependencies, config_info_curr)
    end # target.have_build_units

    put_hook_post_target()
    return target_is_valid
  end
  def put_target_type(target, map_dependencies, config_info_curr)
    target_is_valid = false

    str_condition_no_target = get_conditional_inverted(get_var_conditional_target(target.name))
    write_conditional_if(str_condition_no_target)
          # FIXME: should use a macro like rosbuild_add_executable(),
          # http://www.ros.org/wiki/rosbuild/CMakeLists ,
          # https://kermit.cse.wustl.edu/project/robotics/browser/trunk/vendor/ros/core/rosbuild/rosbuild.cmake?rev=3
          # to be able to detect non-C++ file types within a source file list
          # and add a hook to handle them specially.

          # see VCProjectEngine ConfigurationTypes enumeration
    case config_info_curr.cfg_type
    when 1       # typeApplication (.exe)
      target_is_valid = true
      #syntax_generator.write_line("add_executable_vcproj2cmake( #{target.name} WIN32 ${SOURCES} )")
      # TODO: perhaps for real cross-platform binaries (i.e.
      # console apps not needing a WinMain()), we should detect
      # this and not use WIN32 in this case...
      # Well, this toggle probably is related to the .vcproj Keyword attribute...
      write_target_executable()
    when 2    # typeDynamicLibrary (.dll)
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
    when 4    # typeStaticLibrary
      target_is_valid = true
      write_target_library_static()
    when 0    # typeUnknown (utility)
      log_warn "Project type 0 (typeUnknown - utility) is a _custom command_ type and thus probably cannot be supported easily. We will not abort and thus do write out a file, but it probably needs fixup (hook scripts?) to work properly. If this project type happens to use VCNMakeTool tool, then I would suggest to examine BuildCommandLine/ReBuildCommandLine/CleanCommandLine attributes for clues on how to proceed."
    else
    #when 10    # typeGeneric (Makefile) [and possibly other things...]
      # TODO: we _should_ somehow support these project types...
      log_fatal "Project type #{config_info_curr.cfg_type} not supported."
    end
    write_conditional_end(str_condition_no_target)

    # write target_link_libraries() in case there's a valid target
    if target_is_valid
      config_info_curr.arr_linker_info.each { |linker_info_curr|
        write_link_libraries(linker_info_curr.arr_dependencies, map_dependencies)
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
    #write_new_line("add_library_vcproj2cmake( #{target.name} STATIC ${SOURCES} )")
    next_paragraph()
    write_command_single_line('add_library', "#{@target.name} STATIC ${SOURCES}")
  end
  def put_hook_post_target
    next_paragraph()
    write_comment_at_level(1, \
      "e.g. to be used for tweaking target properties etc." \
    )
    write_include_from_cmake_var('V2C_HOOK_POST_TARGET', true)
  end
  COMPILE_DEF_NEEDS_ESCAPING_REGEX_OBJ = %r{[\(\)]+}
  def generate_property_compile_definitions(config_name_upper, arr_platdefs, str_platform)
      write_conditional_if(str_platform)
        arr_compile_defn = Array.new
        arr_platdefs.each do |compile_defn|
    	  # Need to escape the value part of the key=value definition:
          if compile_defn =~ COMPILE_DEF_NEEDS_ESCAPING_REGEX_OBJ
            escape_char(compile_defn, '\\(')
            escape_char(compile_defn, '\\)')
          end
          arr_compile_defn.push(compile_defn)
        end
        # make sure to specify APPEND for greater flexibility (hooks etc.)
        cmake_command_arg = "TARGET #{@target.name} APPEND PROPERTY COMPILE_DEFINITIONS_#{config_name_upper}"
	write_command_list('set_property', cmake_command_arg, arr_compile_defn)
      write_conditional_end(str_platform)
  end
  def put_precompiled_header(target_name, build_type, pch_use_mode, pch_source_name)
    # FIXME: empty filename may happen in case of precompiled file
    # indicated via VS7 FileConfiguration UsePrecompiledHeader
    # (however this is an entry of the .cpp file: not sure whether we can
    # and should derive the header from that - but we could grep the
    # .cpp file for the similarly named include......).
    return if pch_source_name.nil? or pch_source_name.length == 0
    arr_args_precomp_header = [ build_type, "#{pch_use_mode}", pch_source_name ]
    write_invoke_config_object_function_quoted('v2c_target_add_precompiled_header', target_name, arr_args_precomp_header)
  end
  def write_precompiled_header(str_build_type, precompiled_header_info)
    return if not $v2c_target_precompiled_header_enable
    return if precompiled_header_info.nil?
    return if precompiled_header_info.header_source_name.nil?
    # FIXME: this filesystem validation should be carried out by a non-parser/non-generator validator class...
    pch_ok = v2c_generator_check_file_accessible(@project_dir, precompiled_header_info.header_source_name, 'header file to be precompiled', @target.name, false)
    # Implement non-hard failure
    # (reasoning: the project is compilable anyway, even without pch)
    # in case the file is not valid:
    return if not pch_ok
    put_precompiled_header(
      @target.name,
      prepare_string_literal(str_build_type),
      precompiled_header_info.use_mode,
      precompiled_header_info.header_source_name
    )
  end
  def write_property_compile_definitions(config_name, hash_defs, map_defs)
    # Convert hash into array as required by common helper functions
    # (it's probably a good idea to provide "key=value" entries
    # for more complete matching possibilities
    # within the regex matching parts done by those functions).
    # TODO: this might be relocatable to a common generator base helper method.
    arr_defs = Array.new
    hash_defs.each { |key, value|
      str_define = value.empty? ? key : "#{key}=#{value}"
      arr_defs.push(str_define)
    }
    config_name_upper = get_config_name_upcase(config_name)
    # the container for the list of _actual_ dependencies as stated by the project
    all_platform_defs = Hash.new
    parse_platform_conversions(all_platform_defs, arr_defs, map_defs)
    all_platform_defs.each { |key, arr_platdefs|
      #log_info "arr_platdefs: #{arr_platdefs}"
      next if arr_platdefs.empty?
      arr_platdefs.uniq!
      next_paragraph()
      str_platform = key if not key.eql?('ALL')
      generate_property_compile_definitions(config_name_upper, arr_platdefs, str_platform)
    }
  end
  def write_property_compile_flags(config_name, arr_flags, str_conditional)
    return if arr_flags.empty?
    config_name_upper = get_config_name_upcase(config_name)
    next_paragraph()
    write_conditional_if(str_conditional)
      # FIXME!!! It appears that while CMake source has COMPILE_DEFINITIONS_<CONFIG>,
      # it does NOT provide a per-config COMPILE_FLAGS property! Need to verify ASAP
      # whether compile flags do get passed properly in debug / release.
      # Strangely enough it _does_ have LINK_FLAGS_<CONFIG>, though!
      conditional_target = get_var_conditional_target(@target.name)
      cmake_command_arg = "#{conditional_target} APPEND PROPERTY COMPILE_FLAGS_#{config_name_upper}"
      write_command_list('set_property', cmake_command_arg, arr_flags)
    write_conditional_end(str_conditional)
  end
  def write_property_link_flags(config_name, arr_flags, str_conditional)
    return if arr_flags.empty?
    config_name_upper = get_config_name_upcase(config_name)
    next_paragraph()
    write_conditional_if(str_conditional)
      conditional_target = get_var_conditional_target(@target.name)
      cmake_command_arg = "#{conditional_target} APPEND PROPERTY LINK_FLAGS_#{config_name_upper}"
      write_command_list('set_property', cmake_command_arg, arr_flags)
    write_conditional_end(str_conditional)
  end
  def write_link_libraries(arr_dependencies, map_dependencies)
    arr_dependencies.push(dereference_variable_name('V2C_LIBS'))
    @localGenerator.write_build_attributes('target_link_libraries', arr_dependencies, map_dependencies, @target.name)
  end
  def write_func_v2c_target_post_setup(project_name, project_keyword)
    # Rationale: keep count of generated lines of CMakeLists.txt to a bare minimum -
    # call v2c_project_post_setup(), by simply passing all parameters that are _custom_ data
    # of the current generated CMakeLists.txt file - all boilerplate handling functionality
    # that's identical for each project should be implemented by the v2c_project_post_setup() function
    # _internally_.
    write_vcproj2cmake_func_comment()
    if project_keyword.nil?; project_keyword = V2C_ATTRIBUTE_NOT_PROVIDED_MARKER end
    arr_args_func = [ project_name, project_keyword ]
    write_invoke_config_object_function_quoted('v2c_target_post_setup', @target.name, arr_args_func)
  end
  def set_properties_vs_scc(scc_info)
    # Keep source control integration in our conversion!
    # FIXME: does it really work? Then reply to
    # http://www.itk.org/Bug/view.php?id=10237 !!

    # If even scc_info.project_name is unavailable,
    # then we can bail out right away...
    return if scc_info.project_name.nil?

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
    scc_info.project_name.gsub!(/"/, '&quot;')
    if scc_info.local_path
      escape_backslash(scc_info.local_path)
      escape_char(scc_info.local_path, '"')
    end
    if scc_info.provider
      escape_char(scc_info.provider, '"')
    end
    if scc_info.aux_path
      escape_backslash(scc_info.aux_path)
      escape_char(scc_info.aux_path, '"')
    end

    next_paragraph()
    write_vcproj2cmake_func_comment()
    arr_args_func = [ scc_info.project_name, scc_info.local_path, scc_info.provider, scc_info.aux_path ]
    write_invoke_config_object_function_quoted('v2c_target_set_properties_vs_scc', @target.name, arr_args_func)
  end

  private

  def get_config_name_upcase(config_name)
    # need to also convert config names with spaces into underscore variants, right?
    config_name.clone.upcase.tr(' ','_')
  end

  def set_property(target_name, property, value)
    arr_args_func = [ 'TARGET', target_name, 'PROPERTY', property, value ]
    write_command_list_quoted('set_property', nil, arr_args_func)
  end
end

# XML support as required by VS7+/VS10 parsers:
require 'rexml/document'

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

# See also
# "How to: Use Environment Variables in a Build"
#   http://msdn.microsoft.com/en-us/library/ms171459.aspx
# "Macros for Build Commands and Properties"
#   http://msdn.microsoft.com/en-us/library/c02as0cs%28v=vs.71%29.aspx
# To examine real-life values of such MSVS configuration/environment variables,
# open a Visual Studio project's additional library directories dialog,
# then press its "macros" button for a nice list.
def vs7_create_config_variable_translation(str, arr_config_var_handling)
  # http://langref.org/all-languages/pattern-matching/searching/loop-through-a-string-matching-a-regex-and-performing-an-action-for-each-match
  str_scan_copy = str.dup # create a deep copy of string, to avoid "`scan': string modified (RuntimeError)"
  str_scan_copy.scan(VS7_PROP_VAR_SCAN_REGEX_OBJ) {
    config_var = $1
    # MSVS Property / Environment variables are documented to be case-insensitive,
    # thus implement insensitive match:
    config_var_upcase = config_var.upcase
    config_var_replacement = ''
    #TODO_OPTIMIZE: could replace this huge case switch
    # with a hash lookup on a result struct,
    # at least in cases where a hard-coded (i.e., non-flexible)
    # result handling is sufficient.
    case config_var_upcase
      when 'CONFIGURATIONNAME'
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
        # Probability of SolutionDir being identical to CMAKE_SOURCE_DIR
	# (i.e. the source root dir) ought to be strongly approaching 100%.
	config_var_replacement = '${CMAKE_SOURCE_DIR}'
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
        log_warn "Unknown/user-custom config variable name #{config_var} encountered in line '#{str}' --> TODO?"

        #str.gsub!(/\$\(#{config_var}\)/, "${v2c_VS_#{config_var}}")
	# For now, at least better directly reroute from environment variables:
	config_var_replacement = "$ENV{#{config_var}}"
      end
      if config_var_replacement != ''
        log_info "Replacing MSVS configuration variable $(#{config_var}) by #{config_var_replacement}."
        str.gsub!(/\$\(#{config_var}\)/, config_var_replacement)
      end
  }

  #log_info "str is now #{str}, was #{str_scan_copy}"
  return str
end

def log_error_unhandled_exception(e)
  log_error "unhandled exception occurred! #{e.message}, #{e.backtrace.inspect}"
end

class V2C_VSParserBase
  VS_VALUE_SEPARATOR_REGEX_OBJ = %r{[;,]}
  VS_SCC_ATTR_REGEX_OBJ = %r{^Scc}
  def initialize(elem_xml)
    @elem_xml = elem_xml
  end
  def log_debug_class(str); log_debug "#{self.class.name}: #{str}" end
  def unknown_attribute(name); unknown_something('attribute', name) end
  def unknown_element(name); unknown_something('element', name) end
  def unknown_element_text(name); unknown_something('element text', name) end
  def skipped_element_warn(elem_name)
    log_todo "#{self.class.name}: unhandled less important XML element (#{elem_name})!"
  end
  def parser_error(str_description); log_error(str_description) end
  # "Ruby Exceptions", http://rubylearning.com/satishtalim/ruby_exceptions.html
  def unhandled_exception(e); log_error_unhandled_exception(e) end
  def unhandled_functionality(str_description); log_error(str_description) end
  def get_boolean_value(str_value)
    value = false
    if not str_value.nil?
      case str_value.downcase
      when 'true'
        value = true
      when 'false', '' # seems empty string is VS equivalent to false, right?
        value = false
      else
        # Hrmm, did we hit a totally unexpected (new) element value!?
        parser_error("unknown value text #{str_value}")
      end
    end
    return value
  end
  def split_values_list(str_value)
    return str_value.split(VS_VALUE_SEPARATOR_REGEX_OBJ)
  end

  def string_to_index(arr_settings, str_setting, default_val)
    val = default_val
    n = arr_settings.index(str_setting)
    if not n.nil?
      val = n
    else
      unknown_attribute(str_setting)
    end
    return val
  end

  private

  def unknown_something(something_name, name)
    log_todo "#{self.class.name}: unknown/incorrect XML #{something_name} (#{name})!"
  end
end

class V2C_VSProjectFileXmlParserBase
  def initialize(doc_proj, arr_projects_new)
    @doc_proj = doc_proj
    @arr_projects_new = arr_projects_new
  end
end

class V2C_VSProjectParserBase < V2C_VSParserBase
  def initialize(project_xml, project_out)
    super(project_xml)
    @project = project_out
  end
end

class V2C_VS7ProjectParserBase < V2C_VSProjectParserBase
end

module V2C_VSToolDefines
  TEXT_ADDITIONALOPTIONS = 'AdditionalOptions'
  TEXT_SUPPRESSSTARTUPBANNER = 'SuppressStartupBanner'
end

class V2C_VSToolParserBase < V2C_VSParserBase
  include V2C_VSToolDefines
  def parse_setting(tool_info, setting_key, setting_value)
    found = true # be optimistic :)
    case setting_key
    when V2C_VSToolDefines::TEXT_SUPPRESSSTARTUPBANNER
      tool_info.suppress_startup_banner_enable = get_boolean_value(setting_value)
    else
      found = false
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
    arr_flags.replace(attr_options.split(';'))
  end
end

module V2C_VSToolCompilerDefines
  include V2C_VSToolDefines
  TEXT_ADDITIONALINCLUDEDIRECTORIES = 'AdditionalIncludeDirectories'
  TEXT_DISABLESPECIFICWARNINGS = 'DisableSpecificWarnings'
  TEXT_ENABLEPREFAST = 'EnablePREfast'
  TEXT_EXCEPTIONHANDLING = 'ExceptionHandling'
  TEXT_OPTIMIZATION = 'Optimization'
  TEXT_PREPROCESSORDEFINITIONS = 'PreprocessorDefinitions'
  TEXT_RUNTIMETYPEINFO = 'RuntimeTypeInfo'
  TEXT_SHOWINCLUDES = 'ShowIncludes'
  TEXT_WARNINGLEVEL = 'WarningLevel'
end

class V2C_VSToolCompilerParser < V2C_VSToolParserBase
  include V2C_VSToolCompilerDefines
  def initialize(compiler_xml, arr_compiler_info_out)
    super(compiler_xml)
    @arr_compiler_info = arr_compiler_info_out
  end
  def allocate_precompiled_header_info(compiler_info)
    return if not compiler_info.precompiled_header_info.nil?
    compiler_info.precompiled_header_info = V2C_Precompiled_Header_Info.new
  end
  def parse_setting(compiler_info, setting_key, setting_value)
    if super; return true end # base method successful!
    found = true # be optimistic :)
    case setting_key
    when V2C_VSToolCompilerDefines::TEXT_ADDITIONALINCLUDEDIRECTORIES
      parse_additional_include_directories(compiler_info, setting_value)
    when V2C_VSToolDefines::TEXT_ADDITIONALOPTIONS
      parse_additional_options(compiler_info.arr_compiler_specific_info[0].arr_flags, setting_value)
    when V2C_VSToolCompilerDefines::TEXT_DISABLESPECIFICWARNINGS
      parse_disable_specific_warnings(compiler_info.arr_compiler_specific_info[0].arr_disable_warnings, setting_value)
    when V2C_VSToolCompilerDefines::TEXT_ENABLEPREFAST
      compiler_info.static_code_analysis_enable = get_boolean_value(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_PREPROCESSORDEFINITIONS
      parse_preprocessor_definitions(compiler_info.hash_defines, setting_value)
    when V2C_VSToolCompilerDefines::TEXT_RUNTIMETYPEINFO
      compiler_info.rtti = get_boolean_value(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_SHOWINCLUDES
      compiler_info.show_includes_enable = get_boolean_value(setting_value)
    else
      found = false
    end
    return found
  end

  private

  def parse_additional_include_directories(compiler_info, attr_incdir)
    arr_includes = Array.new
    split_values_list(attr_incdir).each { |elem_inc_dir|
      elem_inc_dir = normalize_path(elem_inc_dir).strip
      #log_info "include is '#{elem_inc_dir}'"
      arr_includes.push(elem_inc_dir)
    }
    arr_includes.each { |inc_dir|
      info_inc_dir = V2C_Info_Include_Dir.new
      info_inc_dir.dir = inc_dir
      compiler_info.arr_info_include_dirs.push(info_inc_dir)
    }
  end
  def parse_disable_specific_warnings(arr_disable_warnings, attr_disable_warnings)
    arr_disable_warnings.replace(attr_disable_warnings.split(';'))
  end
  def parse_preprocessor_definitions(hash_defines, attr_defines)
    split_values_list(attr_defines).each { |elem_define|
      str_define_key, str_define_value = elem_define.strip.split('=')
      # Since a Hash will indicate nil for any non-existing key,
      # we do need to fill in _empty_ value for our _existing_ key.
      if str_define_value.nil?
        str_define_value = ''
      end
      hash_defines[str_define_key] = str_define_value
    }
  end
end

module V2C_VS7ToolDefines
  include V2C_VSToolDefines
  TEXT_NAME = 'Name'
  TEXT_VCCLCOMPILERTOOL = 'VCCLCompilerTool'
  TEXT_VCLINKERTOOL = 'VCLinkerTool'
end

module V2C_VS7ToolCompilerDefines
  include V2C_VS7ToolDefines
  include V2C_VSToolCompilerDefines
  # pch names are _different_ (_swapped_) from their VS10 meanings...
  TEXT_PRECOMPILEDHEADERFILE_BINARY = 'PrecompiledHeaderFile'
  TEXT_PRECOMPILEDHEADERFILE_SOURCE = 'PrecompiledHeaderThrough'
  TEXT_USEPRECOMPILEDHEADER = 'UsePrecompiledHeader'
  TEXT_WARNASERROR = 'WarnAsError'
end

class V2C_VS7ToolCompilerParser < V2C_VSToolCompilerParser
  include V2C_VS7ToolCompilerDefines
  def parse
    compiler_info = V2C_Tool_Compiler_Info.new

    parse_attributes(compiler_info)

    @arr_compiler_info.push(compiler_info)
  end

  private

  def parse_attributes(compiler_info)
    compiler_specific = V2C_Tool_Compiler_Specific_Info_MSVC7.new
    compiler_specific.original = true
    compiler_info.arr_compiler_specific_info.push(compiler_specific)
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(compiler_info, attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(compiler_info, setting_key, setting_value)
    if super; return true end # base method successful!
    case setting_key
    when 'Detect64BitPortabilityProblems'
      # TODO: add /Wp64 to flags of an MSVC compiler info...
      compiler_info.detect_64bit_porting_problems_enable = get_boolean_value(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_EXCEPTIONHANDLING
      compiler_info.exception_handling = setting_value.to_i
    when V2C_VS7ToolDefines::TEXT_NAME
      compiler_info.name = setting_value
    when V2C_VSToolCompilerDefines::TEXT_OPTIMIZATION
      compiler_info.optimization = setting_value.to_i
    when V2C_VS7ToolCompilerDefines::TEXT_PRECOMPILEDHEADERFILE_BINARY
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.header_binary_name = normalize_path(setting_value)
    when V2C_VS7ToolCompilerDefines::TEXT_PRECOMPILEDHEADERFILE_SOURCE
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.header_source_name = normalize_path(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_SHOWINCLUDES
      compiler_info.show_includes = get_boolean_value(setting_value)
    when V2C_VS7ToolCompilerDefines::TEXT_USEPRECOMPILEDHEADER
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.use_mode = parse_use_precompiled_header(setting_value)
    when V2C_VS7ToolCompilerDefines::TEXT_WARNASERROR
      compiler_info.warnings_are_errors_enable = get_boolean_value(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_WARNINGLEVEL
      compiler_info.arr_compiler_specific_info[0].warning_level = setting_value.to_i
    else
      unknown_attribute(setting_key)
    end
  end
  def parse_use_precompiled_header(value_use_precompiled_header)
    use_val = value_use_precompiled_header.to_i
    if use_val == 3; use_val = 2 end # VS7 --> VS8 migration change: all values of 3 have been replaced by 2, it seems...
    return use_val
  end
end

module V2C_VSToolLinkerDefines
  include V2C_VSToolDefines
  TEXT_ADDITIONALDEPENDENCIES = 'AdditionalDependencies'
  TEXT_ADDITIONALLIBRARYDIRECTORIES = 'AdditionalLibraryDirectories'
  TEXT_LINKINCREMENTAL = 'LinkIncremental'
  TEXT_MODULEDEFINITIONFILE = 'ModuleDefinitionFile'
  TEXT_OPTIMIZEREFERENCES = 'OptimizeReferences'
  TEXT_PROGRAMDATABASEFILE = 'ProgramDatabaseFile'
end

class V2C_VSToolLinkerParser < V2C_VSToolParserBase
  include V2C_VSToolLinkerDefines
  def initialize(linker_xml, arr_linker_info_out)
    super(linker_xml)
    @arr_linker_info = arr_linker_info_out
  end
  def parse_setting(linker_info, setting_key, setting_value)
    if super; return true end # base method successful!
    found = true # be optimistic :)
    case setting_key
    when V2C_VSToolLinkerDefines::TEXT_ADDITIONALDEPENDENCIES
      parse_additional_dependencies(setting_value, linker_info.arr_dependencies)
    when V2C_VSToolLinkerDefines::TEXT_ADDITIONALLIBRARYDIRECTORIES
      parse_additional_library_directories(setting_value, linker_info.arr_lib_dirs)
    when V2C_VSToolDefines::TEXT_ADDITIONALOPTIONS
      parse_additional_options(linker_info.arr_linker_specific_info[0].arr_flags, setting_value)
    when V2C_VSToolLinkerDefines::TEXT_MODULEDEFINITIONFILE
      linker_info.module_definition_file = parse_module_definition_file(setting_value)
    when V2C_VSToolLinkerDefines::TEXT_PROGRAMDATABASEFILE
      linker_info.pdb_file = parse_pdb_file(setting_value)
    else
      found = false
    end
    return found
  end

  private

  def parse_additional_dependencies(attr_deps, arr_dependencies)
    return if attr_deps.length == 0
    attr_deps.split.each { |elem_lib_dep|
      elem_lib_dep = normalize_path(elem_lib_dep).strip
      dependency_name = File.basename(elem_lib_dep, '.lib')
      arr_dependencies.push(dependency_name)
    }
  end
  def parse_additional_library_directories(attr_lib_dirs, arr_lib_dirs)
    return if attr_lib_dirs.length == 0
    split_values_list(attr_lib_dirs).each { |elem_lib_dir|
      elem_lib_dir = normalize_path(elem_lib_dir).strip
      #log_info "lib dir is '#{elem_lib_dir}'"
      arr_lib_dirs.push(elem_lib_dir)
    }
  end
  # See comment at compiler-side method counterpart
  # It seems VS7 linker arguments are separated by whitespace --> empty split() argument.
  def parse_additional_options(arr_flags, attr_options); arr_flags.replace(attr_options.split()) end
  def parse_module_definition_file(attr_module_definition_file)
    return normalize_path(attr_module_definition_file)
  end
  def parse_pdb_file(attr_pdb_file); return normalize_path(attr_pdb_file) end
end

module V2C_VS7ToolLinkerDefines
  include V2C_VSToolLinkerDefines
  include V2C_VS7ToolDefines
end

class V2C_VS7ToolLinkerParser < V2C_VSToolLinkerParser
  include V2C_VS7ToolLinkerDefines
  def parse
    # parse linker configuration...
    linker_info_curr = V2C_Tool_Linker_Info.new(V2C_Tool_Linker_Specific_Info_MSVC7.new)
    parse_attributes(linker_info_curr)
    @arr_linker_info.push(linker_info_curr)
  end

  private

  def parse_attributes(linker_info)
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(linker_info, attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(linker_info, setting_key, setting_value)
    if super; return true end # base method successful!
    case setting_key
    when V2C_VSToolLinkerDefines::TEXT_LINKINCREMENTAL
      linker_info.link_incremental = parse_link_incremental(setting_value)
    when V2C_VS7ToolDefines::TEXT_NAME
      linker_info.name = setting_value
    when V2C_VSToolLinkerDefines::TEXT_OPTIMIZEREFERENCES
      linker_info.optimize_references_enable = setting_value.to_i
    else
      unknown_attribute(setting_key)
    end
  end
  def parse_link_incremental(str_link_incremental); return str_link_incremental.to_i end
end

class V2C_VS7ToolParser < V2C_VSParserBase
  def initialize(tool_xml, config_info_out)
    super(tool_xml)
    @config_info = config_info_out
  end
  def parse
    parse_attributes()
  end
  def parse_attributes
    @elem_xml.attributes.each_attribute { |attr_xml|
      case attr_xml.name
      when V2C_VS7ToolDefines::TEXT_NAME
        toolname = attr_xml.value
        case toolname
        when V2C_VS7ToolDefines::TEXT_VCCLCOMPILERTOOL
          elem_parser = V2C_VS7ToolCompilerParser.new(@elem_xml, @config_info.arr_compiler_info)
        when V2C_VS7ToolDefines::TEXT_VCLINKERTOOL
          elem_parser = V2C_VS7ToolLinkerParser.new(@elem_xml, @config_info.arr_linker_info)
        else
          unknown_element(toolname)
        end
        if not elem_parser.nil?
          elem_parser.parse
        end
      else
        unknown_attribute(attr_xml.name)
      end
    }
  end
end

class V2C_VS7ConfigurationBaseParser < V2C_VSParserBase
  def initialize(config_xml, config_info_out)
    super(config_xml)
    @config_info = config_info_out
  end
  def parse
    res = false
    parse_attributes(@config_info)
    parse_elements(@config_info)
    res = true
    return res
  end

  private

  def parse_attributes(config_info)
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(config_info, attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(config_info, setting_key, setting_value)
    found = true # be optimistic :)
    case setting_key
    when 'CharacterSet'
      config_info.charset = parse_charset(setting_value)
    when 'ConfigurationType'
      config_info.cfg_type = parse_configuration_type(setting_value)
    when 'Name'
      arr_name = setting_value.split('|')
      config_info.build_type = arr_name[0]
      config_info.platform = arr_name[1]
    when 'UseOfMFC'
      # VS7 does not seem to use string values (only 0/1/2 integers), while VS10 additionally does.
      # NOTE SPELLING DIFFERENCE: MSVS7 has UseOfMFC, MSVS10 has UseOfMfc (see CMake MSVS generators)
      config_info.use_of_mfc = setting_value.to_i
    when 'UseOfATL'
      config_info.use_of_atl = setting_value.to_i
    when 'WholeProgramOptimization'
      config_info.whole_program_optimization = parse_wp_optimization(setting_value)
    else
      found = false
    end
    return found
  end
  def parse_elements(config_info)
    @elem_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'Tool'
        elem_parser = V2C_VS7ToolParser.new(subelem_xml, config_info)
      else
        unknown_element(subelem_xml.name)
      end
      if not elem_parser.nil?
        elem_parser.parse
      end
    }
  end
  def parse_charset(str_charset); return str_charset.to_i end
  def parse_configuration_type(str_configuration_type); return str_configuration_type.to_i end
  def parse_wp_optimization(str_opt); return str_opt.to_i end
end

class V2C_VS7ProjectConfigurationParser < V2C_VS7ConfigurationBaseParser

  private

  def parse_setting(config_info, setting_key, setting_value)
    if super; return true end # base method successful!
    unknown_attribute(setting_key)
  end
end

class V2C_VS7FileConfigurationParser < V2C_VS7ConfigurationBaseParser

  private

  def parse_setting(config_info, setting_key, setting_value)
    if super; return true end # base method successful!
    case setting_key
    when 'ExcludedFromBuild'
      config_info.excluded_from_build = get_boolean_value(setting_value)
    else
      unknown_attribute(setting_key)
    end
  end
end

class V2C_VS7ConfigurationsParser < V2C_VSParserBase
  def initialize(configs_xml, arr_config_info_out)
    super(configs_xml)
    @arr_config_info = arr_config_info_out
  end
  def parse
    @elem_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'Configuration'
        config_info_curr = V2C_Project_Config_Info.new
        elem_parser = V2C_VS7ProjectConfigurationParser.new(subelem_xml, config_info_curr)
        if elem_parser.parse
          @arr_config_info.push(config_info_curr)
        end
      else
        unknown_element(subelem_xml.name)
      end
    }
  end
end

class V2C_Info_File
  def initialize
    @config_info = nil
    @path_relative = ''
  end
  attr_accessor :config_info
  attr_accessor :path_relative
end

class V2C_VS7FileParser < V2C_VSParserBase
  def initialize(file_xml, arr_file_infos_out)
    super(file_xml)
    @arr_file_infos = arr_file_infos_out
    @have_build_units = false # HACK
  end
  BUILD_UNIT_FILE_TYPES_REGEX_OBJ = %r{\.(c|C)}
  def parse
    log_debug_class('parse')
    info_file = V2C_Info_File.new
    parse_attributes(info_file)

    config_info_curr = nil
    @elem_xml.elements.each { |subelem_xml|
      case subelem_xml.name
      when 'FileConfiguration'
	config_info_curr = V2C_File_Config_Info.new
        elem_parser = V2C_VS7FileConfigurationParser.new(subelem_xml, config_info_curr)
        elem_parser.parse
        info_file.config_info = config_info_curr
      else
        unknown_element(subelem_xml.name)
      end
    }

    # FIXME: move these file skipping parts to _generator_ side,
    # don't skip adding file array entries here!!

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
      @arr_file_infos.push(info_file)
      # HACK:
      if not @have_build_units
        if info_file.path_relative =~ BUILD_UNIT_FILE_TYPES_REGEX_OBJ
          @have_build_units = true
        end
      end
    end
    return @have_build_units
  end

  private

  def parse_attributes(info_file)
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(info_file, attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(info_file, setting_key, setting_value)
    case setting_key
    when 'RelativePath'
      info_file.path_relative = normalize_path(setting_value)
    else
      unknown_attribute(setting_key)
    end
  end
end

class V2C_VS7FilterParser < V2C_VSParserBase
  def initialize(files_xml, project_out, files_str_out)
    super(files_xml)
    @project = project_out
    @files_str = files_str_out
  end
  def parse
    res = parse_file_list(@elem_xml, @files_str)
    return res
  end
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
      if filter_info.val_scmfiles == false
        log_info "#{filter_info.name}: SourceControlFiles set to false, listing generated files? --> skipping!"
        return false
      end
      if not filter_info.name.nil?
        # Hrmm, this string match implementation is very open-coded ad-hoc imprecise.
        if filter_info.name == 'Generated Files' or filter_info.name == 'Generierte Dateien'
          # Hmm, how are we supposed to handle Generated Files?
          # Most likely we _are_ supposed to add such files
          # and set_property(SOURCE ... GENERATED) on it.
          log_info "#{filter_info.name}: encountered a filter named Generated Files --> skipping! (FIXME)"
          return false
        end
      end
    end

    arr_file_infos = Array.new
    vcproj_filter_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'File'
        log_debug_class('FOUND File')
        elem_parser = V2C_VS7FileParser.new(subelem_xml, arr_file_infos)
	if elem_parser.parse
          @project.have_build_units = true
        end
      when 'Filter'
        log_debug_class('FOUND Filter')
        subfiles_str = Files_str.new
        elem_parser = V2C_VS7FilterParser.new(subelem_xml, @project, subfiles_str)
        if elem_parser.parse
          if files_str[:arr_sub_filters].nil?
            files_str[:arr_sub_filters] = Array.new
          end
          files_str[:arr_sub_filters].push(subfiles_str)
        end
      else
        unknown_element(subelem_xml.name)
      end
    } # |subelem_xml|

    if not arr_file_infos.empty?
      files_str[:arr_file_infos] = arr_file_infos
    end
    return true
  end

  private

  def parse_file_list_attributes(vcproj_filter_xml, files_str)
    filter_info = nil
    file_group_name = nil
    if vcproj_filter_xml.attributes.length
      filter_info = V2C_Info_Filter.new
    end
    vcproj_filter_xml.attributes.each_attribute { |attr_xml|
      setting_value = attr_xml.value
      case attr_xml.name
      when 'Filter'
        filter_info.arr_scfilter = split_values_list(setting_value)
      when 'Name'
        file_group_name = setting_value
        filter_info.name = file_group_name
      when 'SourceControlFiles'
        filter_info.val_scmfiles = get_boolean_value(setting_value)
      when 'UniqueIdentifier'
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
          unknown_attribute("unknown/custom UniqueIdentifier #{setting_value_upper}")
        end
      else
        unknown_attribute(attr_xml.name)
      end
    }
    if file_group_name.nil?
      file_group_name = 'COMMON'
    end
    #log_debug_class("parsed files group #{file_group_name}, type #{filter_info.get_group_type()}")
    files_str[:filter_info] = filter_info
  end
end

class V2C_VS7ProjectParser < V2C_VS7ProjectParserBase
  def parse
    parse_attributes

    @elem_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'Configurations'
        elem_parser = V2C_VS7ConfigurationsParser.new(subelem_xml, @project.arr_config_info)
      when 'Files' # "Files" simply appears to be a special "Filter" element without any filter conditions.
        # FIXME: we most likely shouldn't pass a rather global "target" object here! (pass a file info object)
        @project.main_files = Files_str.new
        elem_parser = V2C_VS7FilterParser.new(subelem_xml, @project, @project.main_files)
      when 'Platforms'
        skipped_element_warn(subelem_xml.name)
      else
        unknown_element(subelem_xml.name)
      end
      if not elem_parser.nil?
        elem_parser.parse
      end
    }
  end

  private

  def parse_attributes
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(attr_xml.name, attr_xml.value, @project)
    }
  end
  def parse_setting(setting_key, setting_value, project_out)
    case setting_key
    when 'Keyword'
      project_out.vs_keyword = setting_value
    when 'Name'
      project_out.name = setting_value
    when 'ProjectCreator' # used by Fortran .vfproj ("Intel Fortran")
      project_out.creator = setting_value
    when 'ProjectGUID', 'ProjectIdGuid' # used by Visual C++ .vcproj, Fortran .vfproj
      project_out.guid = setting_value
    when 'ProjectType'
      project_out.type = setting_value
    when 'RootNamespace'
      project_out.root_namespace = setting_value
    when 'Version'
      project_out.version = setting_value

    when VS_SCC_ATTR_REGEX_OBJ
      parse_attributes_scc(setting_key, setting_value, project_out.scc_info)
    else
      unknown_attribute(setting_key)
    end
  end
  def parse_attributes_scc(setting_key, setting_value, scc_info_out)
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
      unknown_attribute(setting_key)
    end
  end
end

class V2C_VSProjectFilesBundleParserBase
  def initialize(p_parser_proj_file, str_orig_environment_shortname, arr_projects_new)
    @p_parser_proj_file = p_parser_proj_file
    @proj_filename = p_parser_proj_file.to_s # FIXME: do we want to keep the string-based filename? We should probably change several sub classes to be Pathname-based...
    @str_orig_environment_shortname = str_orig_environment_shortname
    @arr_projects_new = arr_projects_new # We'll keep a project _array_ as member since it's conceivable that both VS7 and VS10 might have several project elements in their XML files.
  end
  def parse
    parse_project_files
    check_unhandled_file_types
    mark_projects_postprocessing
  end

  # Hrmm, that function does not really belong
  # in this somewhat too specific class...
  def check_unhandled_file_type(str_ext)
    str_file = "#{@proj_filename}.#{str_ext}"
    if File.exists?(str_file)
      unhandled_functionality("parser does not handle type of file #{str_file} yet!")
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
  end
  def mark_projects_orig_environment_shortname(str_orig_environment_shortname)
    @arr_projects_new.each { |project_new|
      project_new.orig_environment_shortname = str_orig_environment_shortname
    }
  end
  def mark_projects_default_project_name(project_name_default)
    @arr_projects_new.each { |project_new|
      if project_new.name.nil?
        project_new.name = project_name_default
      end
    }
  end
end

# Project parser variant which works on XML-stream-based input
class V2C_VS7ProjectFileXmlParser < V2C_VSProjectFileXmlParserBase
  def parse
    @doc_proj.elements.each { |subelem_xml|
      setting_key = subelem_xml.name
      case setting_key
      when 'VisualStudioProject'
        project = V2C_Project_Info.new
        project_parser = V2C_VS7ProjectParser.new(subelem_xml, project)
        project_parser.parse

        @arr_projects_new.push(project)
      else
        unknown_element(setting_key)
      end
    }
  end
end

# Project parser variant which works on file-based input
class V2C_VSProjectFileParserBase < V2C_VSParserBase
  def initialize(p_parser_proj_file, arr_projects_new)
    @p_parser_proj_file = p_parser_proj_file
    @proj_filename = p_parser_proj_file.to_s
    @arr_projects_new = arr_projects_new
    @proj_xml_parser = nil
  end
  def parse
    @proj_xml_parser.parse
  end
end

class V2C_VS7ProjectFileParser < V2C_VSProjectFileParserBase
  def parse
    File.open(@proj_filename) { |io|
      doc_proj = REXML::Document.new io

      @proj_xml_parser = V2C_VS7ProjectFileXmlParser.new(doc_proj, @arr_projects_new)
      #super.parse
      @proj_xml_parser.parse
    }
  end
end

class V2C_VS7ProjectFilesBundleParser < V2C_VSProjectFilesBundleParserBase
  def initialize(p_parser_proj_file, arr_projects_new)
    super(p_parser_proj_file, 'MSVS7', arr_projects_new)
  end
  def parse_project_files
    proj_file_parser = V2C_VS7ProjectFileParser.new(@p_parser_proj_file, @arr_projects_new)
    proj_file_parser.parse
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

# NOTE: VS10 == MSBuild == somewhat Ant-based.
# Thus it would probably be useful to create an Ant syntax parser base class
# and derive MSBuild-specific behaviour from it.
class V2C_VS10ParserBase < V2C_VSParserBase
end

# Parses elements with optional conditional information (Condition=xxx).
class V2C_VS10BaseElemParser < V2C_VS10ParserBase
  def initialize(elem_xml)
    super(elem_xml)
    @have_condition = false
  end
  def parse_attributes(setting_key, setting_value)
    found = true # be optimistic :)
    case setting_key
    when 'blubb'
    else
      unknown_attribute(setting_key)
    end
    return found
  end
end

class V2C_VS10ItemGroupProjectConfigurationParser < V2C_VS10ParserBase
  def initialize(projconf_xml, config_info_out)
    super(projconf_xml)
    @config_info = config_info_out
  end
  def parse
    @elem_xml.elements.each  { |subelem_xml|
      setting_key = subelem_xml.name
      setting_value = subelem_xml.text
      case setting_key
      when 'Configuration'
        @config_info.build_type = setting_value
      when 'Platform'
        @config_info.platform = setting_value
      else
        unknown_element(setting_key)
      end
    }
    log_debug_class("build type #{@config_info.build_type}, platform #{@config_info.platform}")
  end
end

class V2C_VS10ItemGroupProjectConfigurationsParser < V2C_VS10ParserBase
  def initialize(itemgroup_xml, arr_config_info)
    super(itemgroup_xml)
    @arr_config_info = arr_config_info
  end
  def parse
    @elem_xml.elements.each { |itemgroup_elem_xml|
      parse_element(itemgroup_elem_xml, itemgroup_elem_xml.name, itemgroup_elem_xml.text)
    }
  end
  def parse_element(itemgroup_elem_xml, setting_key, setting_name)
    case itemgroup_elem_xml.name
    when 'ProjectConfiguration'
      config_info = V2C_Project_Config_Info.new
      projconf_parser = V2C_VS10ItemGroupProjectConfigurationParser.new(itemgroup_elem_xml, config_info)
      projconf_parser.parse
      @arr_config_info.push(config_info)
    else
      unknown_element(itemgroup_elem_xml.name)
    end
  end
end

class V2C_ItemGroup_Info
  def initialize
    @label = String.new
    @items = Array.new
  end
end

class V2C_VS10ItemGroupElemFilterParser < V2C_VS10ParserBase
  def initialize(elem_xml, filter)
    super(elem_xml)
    @filter = filter
  end
  def parse
    parse_attributes
    @elem_xml.elements.each { |subelem_xml|
      parse_setting(subelem_xml.name, subelem_xml.text)
    }
  end
  def parse_attributes
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_attribute(attr_xml.name, attr_xml.value)
    }
  end
  def parse_attribute(setting_value, setting_key)
    case setting_key
    when 'Include'
       @filter.name = setting_value
    else
      unknown_attribute(setting_key)
    end
  end
  def parse_setting(setting_key, setting_value)
    case setting_key
    when 'Extensions'
      @filter.arr_scfilter = split_values_list(setting_value)
    when 'UniqueIdentifier'
      @filter.guid = setting_value
    else
      unknown_element(setting_key)
    end
  end
end

class V2C_VS10ItemGroupAnonymousParser < V2C_VS10ParserBase
  def initialize(itemgroup_xml, project_out)
    super(itemgroup_xml)
    @project = project_out
  end
  def parse
    @elem_xml.elements.each { |subelem_xml|
      setting_key = subelem_xml.name
      case setting_key
      when 'Filter'
        filter = V2C_Info_Filter.new
        elem_parser = V2C_VS10ItemGroupElemFilterParser.new(subelem_xml, filter)
	elem_parser.parse
        @project.filters.append(filter)
      when 'ClCompile', 'ClInclude', 'None', 'ResourceCompile'
        # Due to split between .vcxproj and .vcxproj.filters,
        # need to possibly _enhance_ an _existing_ (added by the prior file)
        # item group info, thus make sure to do lookup first.
        file_list_name = setting_key
        file_list_type = get_file_list_type(file_list_name)
        file_list = @project.file_lists.get(file_list_type, file_list_name)
      else
        unknown_element(setting_key)
      end
      # TODO:
      #if not @itemgroup.label.nil?
      #  if not setting_key == @itemgroup.label
      #    parser_error("item label #{setting_key} does not match group's label #{@itemgroup.label}!?")
      #  end
      #end
    }
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
    else
      unhandled_functionality("file list name #{file_list_name}")
      type = V2C_File_List_Types::TYPE_NONE
    end
    return type
  end
end

class V2C_VS10ItemGroupParser < V2C_VS10ParserBase
  def initialize(itemgroup_xml, project_out)
    super(itemgroup_xml)
    @project = project_out
    @label = nil
  end
  def parse
    parse_attributes
    log_debug_class("Label #{@label}!")
    item_group_parser = nil
    case @label
    when 'ProjectConfigurations'
      item_group_parser = V2C_VS10ItemGroupProjectConfigurationsParser.new(@elem_xml, @project.arr_config_info)
    when nil
      item_group_parser = V2C_VS10ItemGroupAnonymousParser.new(@elem_xml, @project)
    else
      unknown_element("Label #{@label}")
    end
    if not item_group_parser.nil?
      item_group_parser.parse
    end
  end

  private

  def parse_attributes
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(setting_key, setting_value)
    case setting_key
    when 'Label'
      @label = setting_value
    else
      unknown_attribute(setting_key)
    end
  end
end

module V2C_VS10ToolDefines
  include V2C_VSToolDefines
end

module V2C_VS10ToolCompilerDefines
  include V2C_VS10ToolDefines
  include V2C_VSToolCompilerDefines
  TEXT_PRECOMPILEDHEADER = 'PrecompiledHeader'
  TEXT_PRECOMPILEDHEADERFILE = 'PrecompiledHeaderFile'
  TEXT_PRECOMPILEDHEADEROUTPUTFILE = 'PrecompiledHeaderOutputFile'
  TEXT_TREATWARNINGASERROR = 'TreatWarningAsError'
end

class V2C_VS10ToolCompilerParser < V2C_VSToolCompilerParser
  include V2C_VS10ToolCompilerDefines
  def parse
    compiler_info = V2C_Tool_Compiler_Info.new

    parse_elements(compiler_info)

    @arr_compiler_info.push(compiler_info)
  end

  private

  def parse_elements(compiler_info)
    compiler_specific = V2C_Tool_Compiler_Specific_Info_MSVC10.new
    compiler_specific.original = true
    compiler_info.arr_compiler_specific_info.push(compiler_specific)
    @elem_xml.elements.each { |subelem_xml|
      parse_setting(compiler_info, subelem_xml.name, subelem_xml.text)
    }
  end
  def parse_setting(compiler_info, setting_key, setting_value)
    if super; return true end # base method successful!
    case setting_key
    when 'AssemblerListingLocation'
      skipped_element_warn(setting_key)
    when 'MultiProcessorCompilation'
      compiler_info.multi_core_compilation_enable = get_boolean_value(setting_value)
    when 'ObjectFileName'
       # TODO: support it - but with a CMake out-of-tree build this setting is very unimportant methinks.
       skipped_element_warn(setting_key)
    when V2C_VSToolCompilerDefines::TEXT_EXCEPTIONHANDLING
      compiler_info.exception_handling = parse_exception_handling(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_OPTIMIZATION
      compiler_info.optimization = parse_optimization(setting_value)
    when V2C_VS10ToolCompilerDefines::TEXT_PRECOMPILEDHEADER
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.use_mode = parse_use_precompiled_header(setting_value)
    when V2C_VS10ToolCompilerDefines::TEXT_PRECOMPILEDHEADERFILE
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.header_source_name = normalize_path(setting_value)
    when V2C_VS10ToolCompilerDefines::TEXT_PRECOMPILEDHEADEROUTPUTFILE
      allocate_precompiled_header_info(compiler_info)
      compiler_info.precompiled_header_info.header_binary_name = normalize_path(setting_value)
    when V2C_VS10ToolCompilerDefines::TEXT_TREATWARNINGASERROR
      compiler_info.warnings_are_errors_enable = get_boolean_value(setting_value)
    when V2C_VSToolCompilerDefines::TEXT_WARNINGLEVEL
      compiler_info.arr_compiler_specific_info[0].warning_level = parse_warning_level(setting_value)
    else
      unknown_element(setting_key)
    end
  end

  private

  def parse_exception_handling(str_exception_handling)
    arr_except = [
      'false', # 0, false
      'Sync', # 1, Sync, /EHsc
      'Async', # 2, Async, /EHa
      'SyncCThrow' # 3, SyncCThrow, /EHs
    ]
    return string_to_index(arr_except, str_exception_handling, 0)
  end
  def parse_optimization(str_optimization)
    arr_optimization = [
      'Disabled', # 0, /Od
      'MinSpace', # 1, /O1
      'MaxSpeed', # 2, /O2
      'Full' # 3, /Ox
    ]
    return string_to_index(arr_optimization, str_optimization, 0)
  end
  def parse_use_precompiled_header(str_use_precompiled_header)
    return string_to_index([ 'NotUsing', 'Create', 'Use' ], str_use_precompiled_header, 0)
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
    return string_to_index(arr_warn_level, str_warning_level, 3)
  end
end

module V2C_VS10ToolLinkerDefines
end

class V2C_VS10ToolLinkerParser < V2C_VSToolLinkerParser
  include V2C_VS10ToolLinkerDefines
  def parse
    linker_info = V2C_Tool_Linker_Info.new(V2C_Tool_Linker_Specific_Info_MSVC10.new)

    parse_elements(linker_info)

    @arr_linker_info.push(linker_info)
  end

  private

  def parse_elements(linker_info)
    @elem_xml.elements.each { |subelem_xml|
      parse_setting(linker_info, subelem_xml.name, subelem_xml.text)
    }
  end
  def parse_setting(linker_info, setting_key, setting_value)
    if super; return true end # base method successful!
    case setting_key
    when V2C_VSToolLinkerDefines::TEXT_OPTIMIZEREFERENCES
      linker_info.optimize_references_enable = get_boolean_value(setting_value)
    else
      unknown_element(setting_key)
    end
  end
end

class V2C_VS10ItemDefinitionGroupParser < V2C_VS10BaseElemParser
  def initialize(itemdefgroup_xml, config_info_out)
    super(itemdefgroup_xml)
    @config_info = config_info_out
  end
  def parse
    parse_elements(@config_info)
    return true
  end
  def parse_elements(config_info)
    @elem_xml.elements.each { |subelem_xml|
      setting_key = subelem_xml.name
      item_def_group_parser = nil # IMPORTANT: reset it!
      case setting_key
      when 'ClCompile'
        item_def_group_parser = V2C_VS10ToolCompilerParser.new(subelem_xml, config_info.arr_compiler_info)
      #when 'ResourceCompile'
      when 'Link'
        item_def_group_parser = V2C_VS10ToolLinkerParser.new(subelem_xml, config_info.arr_linker_info)
      when 'Midl'
        skipped_element_warn(setting_key)
      else
        unknown_element(setting_key)
      end
      if not item_def_group_parser.nil?
        item_def_group_parser.parse
      end
    }
  end
end

class V2C_VS10PropertyGroupConfigurationParser < V2C_VS10ParserBase
  def initialize(propgroup_xml, config_info_out)
    super(propgroup_xml)
    @config_info = config_info_out
  end
  def parse
    parse_elements(@config_info)
  end
  def parse_elements(config_info)
    @elem_xml.elements.each { |subelem_xml|
      parse_setting(config_info, subelem_xml.name, subelem_xml.text)
    }
  end
  def parse_setting(config_info, setting_key, setting_value)
    case setting_key
    when 'CharacterSet'
      config_info.charset = parse_charset(setting_value)
    when 'ConfigurationType'
      config_info.cfg_type = parse_configuration_type(setting_value)
    when 'UseOfAtl'
      config_info.use_of_atl = parse_use_of_atl_mfc(setting_value)
    when 'UseOfMfc'
      config_info.use_of_mfc = parse_use_of_atl_mfc(setting_value)
    when 'WholeProgramOptimization'
      config_info.whole_program_optimization = parse_wp_optimization(setting_value)
    else
      unknown_element(setting_key)
    end
  end

  private

  def parse_charset(str_charset)
    # Possibly useful related link: "[CMake] Bug #12189"
    #   http://www.cmake.org/pipermail/cmake/2011-June/045002.html
    arr_charset = [
      'NotSet',  # 0 (ASCII i.e. SBCS)
      'Unicode', # 1 (The Healthy Choice)
      'MultiByte' # 2 (MBCS)
    ]
    return string_to_index(arr_charset, str_charset, 0)
  end
  def parse_configuration_type(str_configuration_type)
    arr_config_type = [
      'Unknown', # 0, typeUnknown (utility)
      'Application', # 1, typeApplication (.exe)
      'DynamicLibrary', # 2, typeDynamicLibrary (.dll)
      'UNKNOWN_FIXME', # 3
      'StaticLibrary' # 4, typeStaticLibrary
    ]
    return string_to_index(arr_config_type, str_configuration_type, 0)
  end
  def parse_use_of_atl_mfc(str_use_of_atl_mfc)
    return string_to_index([ 'false', 'Static', 'Dynamic' ], str_use_of_atl_mfc, 0)
  end
  def parse_wp_optimization(str_opt); return get_boolean_value(str_opt) end
end

class V2C_VS10PropertyGroupGlobalsParser < V2C_VS10ParserBase
  def initialize(propgroup_xml, project_out)
    super(propgroup_xml)
    @project = project_out
  end
  def parse
    @elem_xml.elements.each { |subelem_xml|
      setting_key = subelem_xml.name
      setting_value = subelem_xml.text
      case setting_key
      when 'Keyword'
        @project.vs_keyword = setting_value
      when 'ProjectGuid'
        @project.guid = setting_value
      when 'ProjectName'
        @project.name = setting_value
      when 'RootNamespace'
        @project.root_namespace = setting_value
      when VS_SCC_ATTR_REGEX_OBJ
        parse_elements_scc(setting_key, setting_value, @project.scc_info)
      else
        unknown_element(setting_key)
      end
    }
    if @project.name.nil?
      # This can be seen e.g. with sbnc.vcxproj
      # (contains RootNamespace and NOT ProjectName),
      # despite sbnc.vcproj containing Name and NOT RootNamespace. WEIRD.
      # Couldn't find any hint how this case should be handled,
      # which setting to adopt then. FIXME check on MSVS.
      parser_error('missing project name? Adopting root namespace...')
      @project.name = @project.root_namespace
    end
  end
  def parse_elements_scc(setting_key, setting_value, scc_info_out)
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
      unknown_element(setting_key)
    end
  end
end

class V2C_VS10PropertyGroupParser < V2C_VS10BaseElemParser
  def initialize(propgroup_xml, project_out)
    super(propgroup_xml)
    @project = project_out
  end
  def parse
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(setting_key, setting_value)
    case setting_key
    when 'Condition'
      # set have_condition bool to true,
      # then verify further below that the element that was filled in
      # actually had its condition parsed properly (V2C_Info_Elem_Base.@condition != nil),
      # since conditions need to be parsed separately by each property item class type's base class
      # (upon "Condition" attribute parsing the exact property item class often is not known yet i.e. nil!!).
      # Or is there a better way to achieve common, reliable parsing of that condition information?
      @have_condition = true
    when 'Label'
      propgroup_label = setting_value
      log_debug_class("Label #{propgroup_label}!")
      case propgroup_label
      when 'Configuration'
	config_info_curr = V2C_Project_Config_Info.new
        propgroup_parser = V2C_VS10PropertyGroupConfigurationParser.new(@elem_xml, config_info_curr)
        propgroup_parser.parse
        @project.arr_config_info.push(config_info_curr)
      when 'Globals'
        propgroup_parser = V2C_VS10PropertyGroupGlobalsParser.new(@elem_xml, @project)
        propgroup_parser.parse
      else
        unknown_element("Label #{propgroup_label}")
      end
    else
      unknown_attribute(setting_key)
    end
  end
end

class V2C_VS10ProjectParserBase < V2C_VSProjectParserBase
end

class V2C_VS10ProjectParser < V2C_VS10ProjectParserBase

  def parse
    # Do strict traversal over _all_ elements, parse what's supported by us,
    # and yell loudly for any element which we don't know about!
    parse_attributes()
    @elem_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'ItemGroup'
        elem_parser = V2C_VS10ItemGroupParser.new(subelem_xml, @project)
        elem_parser.parse
      when 'ItemDefinitionGroup'
        config_info_curr = V2C_Project_Config_Info.new
        elem_parser = V2C_VS10ItemDefinitionGroupParser.new(subelem_xml, config_info_curr)
        if elem_parser.parse
          @project.arr_config_info.push(config_info_curr)
        end
      when 'PropertyGroup'
        elem_parser = V2C_VS10PropertyGroupParser.new(subelem_xml, @project)
        elem_parser.parse
      else
        unknown_element(subelem_xml.name)
      end
    }
  end

  private

  def parse_attributes
    @elem_xml.attributes.each_attribute { |attr_xml|
      parse_setting(@project, attr_xml.name, attr_xml.value)
    }
  end
  def parse_setting(target, setting_key, setting_value)
    case setting_key
    when 'XXX'
    else
      unknown_attribute(setting_key)
    end
  end
end

# Project parser variant which works on XML-stream-based input
class V2C_VS10ProjectFileXmlParser < V2C_VSProjectFileXmlParserBase
  def initialize(doc_proj, arr_projects_new, filters_only)
    super(doc_proj, arr_projects_new)
    @filters_only = filters_only
  end
  def parse
    @doc_proj.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'Project'
        project_info = V2C_Project_Info.new
        elem_parser = V2C_VS10ProjectParser.new(subelem_xml, project_info)
        elem_parser.parse
        @arr_projects_new.push(project_info)
      else
        unknown_element(subelem_xml.name)
      end
    }
  end
end

# Project parser variant which works on file-based input
class V2C_VS10ProjectFileParser < V2C_VSProjectFileParserBase
  def initialize(p_parser_proj_file, arr_projects_new, filters_only)
    super(p_parser_proj_file, arr_projects_new)
    @filters_only = filters_only # are we parsing main file or extension file (.filters) only?
  end
  def parse
    success = false
    # Parse the project-related file if it exists (_separate_ .filters file in VS10!):
    begin
      File.open(@proj_filename) { |io|
        doc_proj = REXML::Document.new io

        @proj_xml_parser = V2C_VS10ProjectFileXmlParser.new(doc_proj, @arr_projects_new, @filters_only)
        #super.parse
        @proj_xml_parser.parse
        success = true
      }
    rescue Exception => e
      # File probably does not exiѕt...
      log_error_unhandled_exception(e)
    end
    return success
  end
end

class V2C_VS10ProjectFiltersParser < V2C_VS10ParserBase
  def initialize(project_filters_xml, project_out)
    super(project_filters_xml)
    @project = project_out
  end

  def parse
    # Do strict traversal over _all_ elements, parse what's supported by us,
    # and yell loudly for any element which we don't know about!
    @elem_xml.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'ItemGroup'
        # FIXME: _perhaps_ we should pass a boolean to V2C_VS10ItemGroupParser
        # indicating whether we're .vcxproj or .filters.
        # But then VS handling of file elements in .vcxproj and .filters
        # might actually be completely identical, so a boolean split would be
        # counterproductive (TODO verify!).
        elem_parser = V2C_VS10ItemGroupParser.new(subelem_xml, @project)
      #when 'PropertyGroup'
      #  proj_filters_elem_parser = V2C_VS10PropertyGroupParser.new(subelem_xml, @project)
      else
        unknown_element(subelem_xml.name)
      end
      if not elem_parser.nil?
        elem_parser.parse
      end
    }
  end
end

# Project filters parser variant which works on XML-stream-based input
# The fact that the xmlns= attribute's value of a .filters file
# is _identical_ with the one of a .vcxproj file should be enough proof
# that a .filters file's content is simply a KISS extension of the
# (possibly same) content of a .vcxproj file. IOW, parsing should
# most likely be _identical_ (and thus enhance possibly already added structures!?).
class V2C_VS10ProjectFiltersXmlParser
  def initialize(doc_proj_filters, arr_projects)
    @doc_proj_filters = doc_proj_filters
    @arr_projects = arr_projects
  end
  def parse
    idx_target = 0
    puts "FIXME: filters file exists, needs parsing!"
    @doc_proj_filters.elements.each { |subelem_xml|
      elem_parser = nil # IMPORTANT: reset it!
      case subelem_xml.name
      when 'Project'
	# FIXME handle fetch() exception
        project_info = @arr_projects.fetch(idx_target)
        idx_target += 1
        elem_parser = V2C_VS10ProjectFiltersParser.new(subelem_xml, project_info)
        elem_parser.parse
      else
        unknown_element(subelem_xml.name)
      end
    }
  end
end

# Project filters parser variant which works on file-based input
class V2C_VS10ProjectFiltersFileParser
  def initialize(proj_filters_filename, arr_projects)
    @proj_filters_filename = proj_filters_filename
    @arr_projects = arr_projects
  end
  def parse
    success = false
    # Parse the file filters file (_separate_ in VS10!)
    # if it exists:
    begin
      File.open(@proj_filters_filename) { |io|
        doc_proj_filters = REXML::Document.new io

        project_filters_parser = V2C_VS10ProjectFiltersXmlParser.new(doc_proj_filters, @arr_projects)
        project_filters_parser.parse
        success = true
      }
    rescue Exception => e
      # File probably does not exiѕt...
      log_error_unhandled_exception(e)
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
  def initialize(p_parser_proj_file, arr_projects_new)
    super(p_parser_proj_file, 'MSVS10', arr_projects_new)
  end
  def parse_project_files
    proj_filename = @p_parser_proj_file.to_s
    proj_file_parser = V2C_VS10ProjectFileParser.new(@p_parser_proj_file, @arr_projects_new, false)
    proj_filters_file_parser = V2C_VS10ProjectFiltersFileParser.new("#{@proj_filename}.filters", @arr_projects_new)

    if proj_file_parser.parse
      proj_filters_file_parser.parse
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

WHITESPACE_REGEX_OBJ = %r{\s}
def util_flatten_string(in_string)
  return in_string.gsub(WHITESPACE_REGEX_OBJ, '_')
end

class V2C_CMakeGenerator
  def initialize(p_script, p_master_project, p_parser_proj_file, p_generator_proj_file, arr_projects)
    @p_master_project = p_master_project
    @orig_proj_file_basename = p_parser_proj_file.basename
    # figure out a project_dir variable from the generated project file location
    @project_dir = p_generator_proj_file.dirname
    @cmakelists_output_file = p_generator_proj_file.to_s
    @arr_projects = arr_projects
    @script_location_relative_to_master = p_script.relative_path_from(p_master_project)
    #puts "p_script #{p_script} | p_master_project #{p_master_project} | @script_location_relative_to_master #{@script_location_relative_to_master}"
  end
  def generate
    @arr_projects.each { |project_info|
      # write into temporary file, to avoid corrupting previous CMakeLists.txt due to syntax error abort, disk space or failure issues
      tmpfile = Tempfile.new('vcproj2cmake')

      File.open(tmpfile.path, 'w') { |out|
        project_generate_cmake(@p_master_project, @orig_proj_file_basename, out, project_info)

        # Close file, since Fileutils.mv on an open file will barf on XP
        out.close
      }

      # make sure to close that one as well...
      tmpfile.close

      # Since we're forced to fumble our source tree (a definite no-no in all other cases!)
      # by writing our CMakeLists.txt there, use a write-back-when-updated approach
      # to make sure we only write back the live CMakeLists.txt in case anything did change.
      # This is especially important in case of multiple concurrent builds on a shared
      # source on NFS mount.

      configuration_changed = false
      have_old_file = false
      output_file = @cmakelists_output_file
      if File.exists?(output_file)
        have_old_file = true
        if not V2C_Util_File.cmp(tmpfile.path, output_file)
          configuration_changed = true
        end
      else
        configuration_changed = true
      end

      if configuration_changed
        if have_old_file
          # Move away old file.
          # Usability trick:
          # rename to CMakeLists.txt.previous and not CMakeLists.previous.txt
          # since grepping for all *.txt files would then hit these outdated ones.
          V2C_Util_File.mv(output_file, output_file + '.previous')
        end
        # activate our version
        # [for chmod() comments, see our $v2c_generator_file_create_permissions settings variable]
        V2C_Util_File.chmod($v2c_generator_file_create_permissions, tmpfile.path)
        V2C_Util_File.mv(tmpfile.path, output_file)

        log_info %{\
Wrote #{output_file}
Finished. You should make sure to have all important v2c settings includes such as vcproj2cmake_defs.cmake somewhere in your CMAKE_MODULE_PATH
}
      else
        log_info "No settings changed, #{output_file} not updated."
        # tmpfile will auto-delete when finalized...

        # Some make dependency mechanisms might require touching (timestamping) the unchanged(!) file
        # to indicate that it's up-to-date,
        # however we won't do this here since it's not such a good idea.
        # Any user who needs that should do a manual touch subsequently.
      end
    }
  end
  def project_generate_cmake(p_master_project, orig_proj_file_basename, out, project_info)
        target_is_valid = false

        master_project_dir = p_master_project.to_s
        generator_base = V2C_BaseGlobalGenerator.new(master_project_dir)
        map_lib_dirs = Hash.new
        read_mappings_combined(FILENAME_MAP_LIB_DIRS, map_lib_dirs, master_project_dir)
        map_dependencies = Hash.new
        read_mappings_combined(FILENAME_MAP_DEP, map_dependencies, master_project_dir)
        map_defines = Hash.new
        read_mappings_combined(FILENAME_MAP_DEF, map_defines, master_project_dir)

	textOut = V2C_TextStreamSyntaxGeneratorBase.new(out, $v2c_generator_indent_initial_num_spaces, $v2c_generator_indent_step, $v2c_generator_comments_level)
        syntax_generator = V2C_CMakeSyntaxGenerator.new(textOut)

        # we likely shouldn't declare this, since for single-configuration
        # generators CMAKE_CONFIGURATION_TYPES shouldn't be set
        # Also, the configuration_types array should be inferred from arr_config_info.
        ## configuration types need to be stated _before_ declaring the project()!
        #syntax_generator.next_paragraph()
        #global_generator.put_configuration_types(configuration_types)

        local_generator = V2C_CMakeLocalGenerator.new(textOut)

        local_generator.put_file_header()

        # TODO: figure out language type (C CXX etc.) and add it to project() command
        # ok, let's try some initial Q&D handling...
        arr_languages = nil
        if not project_info.creator.nil?
          if project_info.creator.match(/Fortran/)
            arr_languages = Array.new
            arr_languages.push('Fortran')
          end
        end
        local_generator.put_project(project_info.name, arr_languages)
	local_generator.put_conversion_details(project_info.name, project_info.orig_environment_shortname)

        #global_generator = V2C_CMakeGlobalGenerator.new(out)

        ## sub projects will inherit, and we _don't_ want that...
        # DISABLED: now to be done by MasterProjectDefaults_vcproj2cmake module if needed
        #syntax_generator.write_line('# reset project-local variables')
        #syntax_generator.write_set_var('V2C_LIBS', '')
        #syntax_generator.write_set_var('V2C_SOURCES', '')

        local_generator.put_include_MasterProjectDefaults_vcproj2cmake()

        local_generator.put_hook_project()

        target_generator = V2C_CMakeTargetGenerator.new(project_info, @project_dir, local_generator, textOut)

        # arr_sub_source_list_var_names will receive the names of the individual source list variables:
        arr_sub_source_list_var_names = Array.new
        target_generator.put_file_list_source_group_recursive(project_info.name, project_info.main_files, nil, arr_sub_source_list_var_names)

        if not arr_sub_source_list_var_names.empty?
          # add a ${V2C_SOURCES} variable to the list, to be able to append
          # all sorts of (auto-generated, ...) files to this list within
          # hook includes.
  	# - _right before_ creating the target with its sources
  	# - and not earlier since earlier .vcproj-defined variables should be clean (not be made to contain V2C_SOURCES contents yet)
          arr_sub_source_list_var_names.push('V2C_SOURCES')
        else
          log_warn "#{project_info.name}: no source files at all!? (header-based project?)"
        end

        local_generator.put_include_project_source_dir()

        target_generator.put_hook_post_sources()

	arr_config_info = project_info.arr_config_info

        # ARGH, we have an issue with CMake not being fully up to speed with
        # multi-configuration generators (e.g. .vcproj):
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
          config_multi_authoritative = arr_config_info[0].build_type
        end

        arr_config_info.each { |config_info_curr|
          log_debug "config_info #{config_info_curr.inspect}"
          build_type_condition = ''
          build_type_cooked = syntax_generator.prepare_string_literal(config_info_curr.build_type)
          if config_multi_authoritative == config_info_curr.build_type
  	    build_type_condition = "CMAKE_CONFIGURATION_TYPES OR CMAKE_BUILD_TYPE STREQUAL #{build_type_cooked}"
          else
  	    # YES, this condition is supposed to NOT trigger in case of a multi-configuration generator
  	    build_type_condition = "CMAKE_BUILD_TYPE STREQUAL #{build_type_cooked}"
  	  end
  	  syntax_generator.write_set_var_bool_conditional(get_var_name_of_config_info_condition(config_info_curr), build_type_condition)
        }

        arr_config_info.each { |config_info_curr|
  	var_v2c_want_buildcfg_curr = get_var_name_of_config_info_condition(config_info_curr)
  	syntax_generator.next_paragraph()
  	syntax_generator.write_conditional_if(var_v2c_want_buildcfg_curr)

  	local_generator.put_cmake_mfc_atl_flag(config_info_curr)

  	config_info_curr.arr_compiler_info.each { |compiler_info_curr|
	  arr_includes = compiler_info_curr.get_include_dirs(false, false)
  	  local_generator.write_include_directories(arr_includes, generator_base.map_includes)
  	}

  	# FIXME: hohumm, the position of this hook include is outdated, need to update it
  	target_generator.put_hook_post_definitions()

        # Technical note: target type (library, executable, ...) in .vcproj can be configured per-config
        # (or, in other words, different configs are capable of generating _different_ target _types_
        # for the _same_ target), but in CMake this isn't possible since _one_ target name
        # maps to _one_ target type and we _need_ to restrict ourselves to using the project name
        # as the exact target name (we are unable to define separate PROJ_lib and PROJ_exe target names,
        # since other .vcproj file contents always link to our target via the main project name only!!).
        # Thus we need to declare the target _outside_ the scope of per-config handling :(
  	target_is_valid = target_generator.put_target(project_info, arr_sub_source_list_var_names, map_lib_dirs, map_dependencies, config_info_curr)

  	syntax_generator.write_conditional_end(var_v2c_want_buildcfg_curr)
        } # [END per-config handling]

        # Now that we likely _do_ have a valid target
        # (created by at least one of the Debug/Release/... build configs),
        # *iterate through the configs again* and add config-specific
        # definitions. This is necessary (fix for multi-config
        # environment).
        if target_is_valid
          target_generator.write_conditional_target_valid_begin()
          arr_config_info.each { |config_info_curr|
            # NOTE: the commands below can stay in the general section (outside of
            # var_v2c_want_buildcfg_curr above), but only since they define properties
            # which are clearly named as being configuration-_specific_ already!
            #
  	    # I don't know WhyTH we're iterating over a compiler_info here,
  	    # but let's just do it like that for now since it's required
  	    # by our current data model:
  	    config_info_curr.arr_compiler_info.each { |compiler_info_curr|

              # Since the precompiled header CMake module currently
              # _resets_ a target's COMPILE_FLAGS property,
              # make sure to generate it _before_ generating COMPILE_FLAGS:
              target_generator.write_precompiled_header(config_info_curr.build_type, compiler_info_curr.precompiled_header_info)

	      hash_defines_actual = compiler_info_curr.hash_defines.clone
	      # Hrmm, are we even supposed to be doing this?
	      # On Windows I guess UseOfMfc in generated VS project files
	      # would automatically cater for it, and all other platforms
	      # would have to handle it some way or another anyway.
	      # But then I guess there are other build environments on Windows
	      # which would need us handling it here manually, so let's just keep it for now.
	      # Plus, defining _AFXEXT already includes the _AFXDLL setting
	      # (MFC will define it implicitly),
	      # thus it's quite likely that our current handling is somewhat incorrect.
              if config_info_curr.use_of_mfc == V2C_BaseConfig_Defines::MFC_DYNAMIC
                # FIXME: need to add /MD (dynamic) or /MT (static) switch to compiler-specific info (MSVC) as well!
                hash_defines_actual['_AFXEXT'] = ''
                hash_defines_actual['_AFXDLL'] = ''
              end
	      case config_info_curr.charset
              when V2C_BaseConfig_Defines::CHARSET_SBCS # nothing to do?
              when V2C_BaseConfig_Defines::CHARSET_UNICODE
                # http://blog.m-ri.de/index.php/2007/05/31/_unicode-versus-unicode-und-so-manches-eigentuemliche/
                #   "    "Use Unicode Character Set" setzt beide Defines _UNICODE und UNICODE
                #       "Use Multi-Byte Character Set" setzt nur _MBCS.
                #           "Not set" setzt Erwartungsgemäß keinen der Defines..."
                hash_defines_actual['_UNICODE'] = ''
                hash_defines_actual['UNICODE'] = ''
              when V2C_BaseConfig_Defines::CHARSET_MBCS
                hash_defines_actual['_MBCS'] = ''
              else
                log_implementation_bug('unknown charset type!?')
              end
              target_generator.write_property_compile_definitions(config_info_curr.build_type, hash_defines_actual, map_defines)
              # Original compiler flags are MSVC-only, of course. TODO: provide an automatic conversion towards gcc?
              str_conditional_compiler_platform = nil
              compiler_info_curr.arr_compiler_specific_info.each { |compiler_specific|
		str_conditional_compiler_platform = map_compiler_name_to_cmake_platform_conditional(compiler_specific.compiler_name)
                # I don't think we need this (we have per-target properties), thus we'll NOT write it!
                #local_generator.write_directory_property_compile_flags(attr_options)
                target_generator.write_property_compile_flags(config_info_curr.build_type, compiler_specific.arr_flags, str_conditional_compiler_platform)
              }
            }
            config_info_curr.arr_linker_info.each { |linker_info_curr|
              str_conditional_linker_platform = nil
              linker_info_curr.arr_linker_specific_info.each { |linker_specific|
		str_conditional_linker_platform = map_linker_name_to_cmake_platform_conditional(linker_specific.linker_name)
                # Probably more linker flags support needed? (mention via
                # CMAKE_SHARED_LINKER_FLAGS / CMAKE_MODULE_LINKER_FLAGS / CMAKE_EXE_LINKER_FLAGS
                # depending on target type, and make sure to filter out options pre-defined by CMake platform
                # setup modules)
                target_generator.write_property_link_flags(config_info_curr.build_type, linker_specific.arr_flags, str_conditional_linker_platform)
              }
            }
          }
          target_generator.write_conditional_target_valid_end()
        end

        if target_is_valid
          target_generator.write_func_v2c_target_post_setup(project_info.name, project_info.vs_keyword)

          target_generator.set_properties_vs_scc(project_info.scc_info)

          # TODO: might want to set a target's FOLDER property, too...
          # (and perhaps a .vcproj has a corresponding attribute
          # which indicates that?)

          # TODO: perhaps there are useful Xcode (XCODE_ATTRIBUTE_*) properties to convert?
        end # target_is_valid

        local_generator.put_var_converter_script_location(@script_location_relative_to_master)
        local_generator.write_func_v2c_project_post_setup(project_info.name, orig_proj_file_basename)
  end

  private

  # Hrmm, I'm not quite sure yet where to aggregate this function...
  def get_var_name_of_config_info_condition(config_info)
    # Name may contain spaces - need to handle them!
    config_name = util_flatten_string(config_info.build_type)
    return "v2c_want_buildcfg_#{config_name}"
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
      log_error "unknown (unsupported) compiler name #{compiler_name}!"
    end
    return str_conditional_compiler_platform
  end
  def map_linker_name_to_cmake_platform_conditional(linker_name)
    # For now, let's assume that compiler / linker name mappings are the same:
    # BTW, we probably don't have much use for the CMAKE_LINKER variable anywhere, right?
    return map_compiler_name_to_cmake_platform_conditional(linker_name)
  end
end


def v2c_convert_project_inner(p_script, p_parser_proj_file, p_generator_proj_file, p_master_project)
  #p_project_dir = Pathname.new(project_dir)
  #p_cmakelists = Pathname.new(output_file)
  #cmakelists_dir = p_cmakelists.dirname
  #p_cmakelists_dir = Pathname.new(cmakelists_dir)
  #p_cmakelists_dir.relative_path_from(...)

  arr_projects = Array.new

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
  end

  if not parser.nil?
    parser.parse
  else
    log_implementation_bug "No project parser found for project file #{p_parser_proj_file.to_s}!?"
  end

  # Now validate the project...
  # This validation step should be _separate_ from both parser _and_ generator implementations,
  # since otherwise each individual parser/generator would have to remember carrying out validation
  # (they could easily forget about that).
  # Besides, parsing/generating should be concerned about fast (KISS)
  # parsing/generating only anyway.
  projects_valid = true
  begin
    arr_projects.each { |project|
      validator = V2C_ProjectValidator.new(project)
      validator.validate
    }
  rescue V2C_ValidationError => e
    projects_valid = false
    error_msg = "project validation failed: #{e.message}"
    if ($v2c_validate_vcproj_abort_on_error > 0)
      log_fatal error_msg
    else
      log_error error_msg
    end
  rescue Exception => e
    log_error_unhandled_exception(e)
  end

  if projects_valid
    # TODO: it's probably a valid use case to want to generate
    # multiple build environments from the parsed projects.
    # In such case the set of generators should be available
    # at user configuration side, and the configuration/mappings part
    # (currently sitting at cmake/vcproj2cmake/ at default setting)
    # should be distinctly provided for each generator, too.
    generator = nil
    if true
      generator = V2C_CMakeGenerator.new(p_script, p_master_project, p_parser_proj_file, p_generator_proj_file, arr_projects)
    end

    if not generator.nil?
      generator.generate
    end
  end
end

# Treat non-normalized ("raw") input arguments as needed,
# then pass on to inner function.
def v2c_convert_project_outer(project_converter_script_filename, parser_proj_file, generator_proj_file, master_project_dir)
  p_parser_proj_file = Pathname.new(parser_proj_file)
  p_generator_proj_file = Pathname.new(generator_proj_file)
  master_project_location = File.expand_path(master_project_dir)
  p_master_project = Pathname.new(master_project_location)

  script_location = File.expand_path(project_converter_script_filename)
  p_script = Pathname.new(script_location)

  v2c_convert_project_inner(p_script, p_parser_proj_file, p_generator_proj_file, p_master_project)
end
