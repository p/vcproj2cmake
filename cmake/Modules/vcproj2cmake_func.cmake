# This file is part of the vcproj2cmake build converter (vcproj2cmake.sf.net)

# Some helper functions to be used by all converted V2C projects in the tree

# This vcproj2cmake-specific CMake module
# should be installed at least to your V2C-side source root
# (i.e., V2C_SOURCE_ROOT, likely identical with CMAKE_SOURCE_ROOT...),
# to subdir cmake/Modules/, which will end up as an additionally configured
# local (V2C-specific) part of CMAKE_MODULE_PATH.
#
# Content rationale:
# - provide powerful infrastructure to draw as many configuration
#   aspects of a local project/target (CMakeLists.txt) into our function space
#   as possible, by hooking up configuration content
#   at custom V2C properties (target- or directory-specific)
# - given this rich persistent data, our function space can then have
#   flexible decision-making depending on CMake version specifics,
#   build generator specifics etc.
# - this will enable having huge functions within this module
#   yet merely tiny amounts of syntax within the repeatedly generated
#   converted CMakeLists.txt files
# - implement many flexible base helper functions (list manipulation, ...)
# - function prefix: _v2c_* indicates internal functions, whereas v2c_* are
#   relatively public ones
# - prefer _upper-case_ V2C prefix for _cache variables_ such as V2C_BUILD_PLATFORM,
#   to ensure that they're all sorted under The One True upper-case "V2C" prefix
#   in "grouped view" mode of CMake GUI (dito for properties)
# - several functions are expected to be _very_ volatile,
#   with frequent signature and content changes
#   (--> vcproj2cmake.rb and vcproj2cmake_func.cmake versions
#   should always be kept in sync)

# Policy descriptions:
# *V2C_DOCS_POLICY_MACRO*:
#   All "functions" with this markup need to remain _macros_,
#   for some of the following (rather similar) reasons:
#   - otherwise scoping is broken (newly established function scope)
#   - calls include() (which should remain able to define things in user-side scope!)
#   - helper sets externally obeyed variables!

# Important backwards compatibility comment:
# Since this file will usually end up in the main custom module path
# of a source tree and the vcproj2cmake scripts might be kept (and
# updated!) _external_ to that tree, one should still attempt to provide
# certain amounts of backwards compatibility in this module,
# for users who don't automatically and consistently install
# the new module in their source tree.
# Thus, if you do API-incompatible changes to functions,
# try to provide some old-style wrapper functions for a limited time,
# together with an obvious marker comment.
# However we should probably also provide a configurable functionality
# to automatically add the _vcproj2cmake-side_ cmake/Modules/ path
# to the user projects' module path in future, in order to prevent
# Ruby script vs. module file versions from getting desynchronized.


# TODO:
# - should add a _v2c_parse_arguments() macro
#   (available at http://www.cmake.org/Wiki/CMakeMacroParseArguments ),
#   to then be used by several of our functions here



# Avoid useless repeated parsing of static-data function definitions
if(V2C_FUNC_DEFINED)
  return()
endif(V2C_FUNC_DEFINED)
set(V2C_FUNC_DEFINED true)

# We definitely should make use of cmake_parse_arguments() wherever possible,
# since this will relax our V2C function interface stability requirements
# (optionally available parameters simply would be skipped if not
# provided, thus a suddenly changed function featureset often would not matter).
include(CMakeParseArguments) # strong CMake version dependency (>= 2.8.3?)


# # # # #   MOST IMPORTANT HELPER FUNCTIONS   # # # # #
# (those used by all other parts)

set(V2C_CMAKE_CONFIGURE_PROMPT "[V2C] " CACHE STRING "The prompt prefix to show for any vcproj2cmake messages occurring during CMake configure time." FORCE)
mark_as_advanced(V2C_CMAKE_CONFIGURE_PROMPT)

# Zero out a variable.
macro(_v2c_var_set_empty _var_name)
  # A "set(var )" does NOT unset it - it needs an empty string literal!
  set(${_var_name} "")
endmacro(_v2c_var_set_empty _var_name)

macro(_v2c_var_set_default_if_not_set _var_name _v2c_default_setting)
  if(NOT DEFINED ${_var_name})
    set(${_var_name} "${_v2c_default_setting}")
  endif(NOT DEFINED ${_var_name})
endmacro(_v2c_var_set_default_if_not_set _var_name _v2c_default_setting)

macro(_v2c_msg_info _msg)
  message(STATUS "${V2C_CMAKE_CONFIGURE_PROMPT}${_msg}")
endmacro(_v2c_msg_info _msg)
macro(_v2c_msg_important _msg)
  message("${V2C_CMAKE_CONFIGURE_PROMPT}${_msg}")
endmacro(_v2c_msg_important _msg)
macro(_v2c_msg_warning _msg)
  message("${V2C_CMAKE_CONFIGURE_PROMPT}WARNING: ${_msg}")
endmacro(_v2c_msg_warning _msg)
macro(_v2c_msg_fixme _msg)
  message("${V2C_CMAKE_CONFIGURE_PROMPT}FIXME: ${_msg}")
endmacro(_v2c_msg_fixme _msg)
macro(_v2c_msg_fatal_error _msg)
  message(FATAL_ERROR "${V2C_CMAKE_CONFIGURE_PROMPT}${_msg}")
endmacro(_v2c_msg_fatal_error _msg)
macro(_v2c_msg_fatal_error_please_report _msg)
  _v2c_msg_fatal_error("${_msg} - please report!")
endmacro(_v2c_msg_fatal_error_please_report _msg)

# Does a file(WRITE) followed by a configure_file(),
# to avoid continuous rebuilds due to continually rewriting a file with actually unchanged content.
function(_v2c_create_build_decoupled_adhoc_file _template_name _file_location _content)
  file(WRITE "${_template_name}" "${_content}")
  configure_file("${_template_name}" "${_file_location}" COPYONLY)
endfunction(_v2c_create_build_decoupled_adhoc_file _template_name _file_location _content)

# Validate CMAKE_BUILD_TYPE setting:
if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
  if(NOT V2C_WANT_SKIP_CMAKE_BUILD_TYPE_CHECK) # user-side disabling option - user might not want this to happen...
    # We used to actively correct an unset CMAKE_BUILD_TYPE setting,
    # but this is not a good idea for several reasons:
    # - V2C may be one sub functionality within a larger tree -
    #   it's not our business to fumble a global setting
    # - setting a variable via CACHE FORCE is problematic since one needs
    #   to specify a docstring. Querying the standard docstring of CMake's
    #   CMAKE_BUILD_TYPE DOES NOT WORK - docs will only be available
    #   for _defined_ variables, thus neither FULL_DOCS nor BRIEF_DOCS
    #   return anything other than NOTFOUND.
    # See also
    # "[CMake] Understanding why CMAKE_BUILD_TYPE cannot be set"
    #   http://www.cmake.org/pipermail/cmake/2008-September/023808.html
    # "[CMake] Modifying a variable's value without resetting the docstring"
    #   http://www.cmake.org/pipermail/cmake/2012-September/052117.html
    # Thus from a modular POV the most benign handling is to provide
    # a hard error message which can be user-disabled if required.

    # Side note: this message may appear during an _initial_ configuration run
    # at least on MSVS 2005 generator. I suppose that this initial error is ok,
    # since CMake probably still needs to make up its mind as to which
    # configuration types (MinSizeRel, Debug etc.) are available.
    _v2c_msg_fatal_error("Important CMAKE_BUILD_TYPE variable was not specified - should be properly set, or actively ignored by setting V2C_WANT_SKIP_CMAKE_BUILD_TYPE_CHECK (not recommended).")
  endif(NOT V2C_WANT_SKIP_CMAKE_BUILD_TYPE_CHECK) # user might not want this to happen...
endif(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)


# Define a couple global constant settings
# (make sure to keep outside of repeatedly invoked functions below)

# There's a scope discrepancy between functions (_globally_ valid)
# and ordinary variables (valid within sub scope only), which causes
# problems when invoking certain functions from within the "wrong" scope
# (e.g. directory), since accessing pre-defined variables
# within functions will fail.
# This annoying problem needs to be "fixed" somehow,
# which can be done using either global properties (preferable)
# or internal cache variables (iff persistence
# of settings is required, i.e. user-customization needs to be preserved).
# See also "[CMake] global variable vs cache variable"
#   http://www.cmake.org/pipermail/cmake/2011-November/047676.html
# Also, let's have versioned v2c global property variables,
# to be able to detect mismatches in case of incompatible updates
# (querying deprecated variables - missing result).


_v2c_var_set_default_if_not_set(V2C_STAMP_FILES_SUBDIR "stamps")
# Enable customization (via cache entry), someone might need it.
set(V2C_STAMP_FILES_DIR "${CMAKE_BINARY_DIR}/${V2C_GLOBAL_CONFIG_RELPATH}/${V2C_STAMP_FILES_SUBDIR}" CACHE PATH "The directory to place any stamp files used by vcproj2cmake in.")
mark_as_advanced(V2C_STAMP_FILES_DIR)
file(MAKE_DIRECTORY "${V2C_STAMP_FILES_DIR}")


function(_v2c_fs_item_make_relative_to_path _in _path _out)
  # Hmm, I don't think we have a use for file(RELATIVE_PATH) here, right?
  _v2c_var_set_empty(out_)
  if(_in)
    string(SUBSTRING "${_in}" 0 1 in_leadchar_)
    set(absolute_ FALSE)
    if(in_leadchar_ STREQUAL "/" OR in_leadchar_ STREQUAL "\\")
      set(absolute_ TRUE)
    endif(in_leadchar_ STREQUAL "/" OR in_leadchar_ STREQUAL "\\")
    if(absolute_)
      set(out_ "${_in}")
    else(absolute_)
      set(out_ "${_path}/${_in}")
    endif(absolute_)
  endif(_in)
  set(${_out} "${out_}" PARENT_SCOPE)
endfunction(_v2c_fs_item_make_relative_to_path _in _path _out)

set(v2c_want_original_guid_default_setting OFF)
option(V2C_WANT_PROJECT_ORIGINAL_GUID_ASSIGNED "Activate re-use of the original GUID of a project rather than having CMake assign a newly generated random one. This can easily turn out to be a bad idea however, since one could judge an original project and its corresponding re-generated project to NOT be identical (think out-of-tree-build differences, missing attribute translations, ...)" ${v2c_want_original_guid_default_setting})

# A current SCC (Source Control Management) integration test on VS2010
# finally worked as expected, thus it can be enabled now;
# for gory details, see main doc (README).
function(_v2c_scc_do_setup)
  set(v2c_want_scc_default_setting_ ON)
  # Have a check for TUI-only (most uses of Ninja, Makefile) builds.
  set(generator_no_scc_wanted_list_ "Ninja" "Unix Makefiles")
  foreach(gen_ ${generator_no_scc_wanted_list_})
    if("${CMAKE_GENERATOR}" STREQUAL "${gen_}")
      set(v2c_want_scc_default_setting_ OFF)
      break()
    endif("${CMAKE_GENERATOR}" STREQUAL "${gen_}")
  endforeach(gen_ ${generator_no_scc_wanted_list_})
  set(V2C_WANT_SCC_SOURCE_CONTROL_IDE_INTEGRATION ${v2c_want_scc_default_setting_} CACHE BOOL "Enable re-use of any existing SCC (source control management) integration/binding info for projects (e.g. on Visual Studio)")
  if(V2C_WANT_SCC_SOURCE_CONTROL_IDE_INTEGRATION)
    string(LENGTH "${CMAKE_SOURCE_DIR}/" src_len_)
    string(SUBSTRING "${CMAKE_BINARY_DIR}/" 0 ${src_len_} bin_test_)
    set(bin_tree_somewhere_within_source_ false)
    if("${bin_test_}" STREQUAL "${CMAKE_SOURCE_DIR}/")
      set(bin_tree_somewhere_within_source_ true)
    endif("${bin_test_}" STREQUAL "${CMAKE_SOURCE_DIR}/")
    if(bin_tree_somewhere_within_source_)
      if(CMAKE_BINARY_DIR STREQUAL CMAKE_SOURCE_DIR)
        _v2c_msg_warning("CMAKE_BINARY_DIR *equal to* CMAKE_SOURCE_DIR! This is definitely *not* recommended!! (the build tree should always be in a separate directory, ideally out-of-tree)")
      endif(CMAKE_BINARY_DIR STREQUAL CMAKE_SOURCE_DIR)
    else(bin_tree_somewhere_within_source_)
      _v2c_msg_warning("CMAKE_BINARY_DIR (${CMAKE_BINARY_DIR}) is not a sub directory that's within (below) CMAKE_SOURCE_DIR (${CMAKE_SOURCE_DIR}). Normally a fully out-of-tree build is a very good idea, but Visual Studio SCC integration (TFS workspace mappings) seems to require the build tree to be somewhere below the source root. Expect source control management integration to fail!")
    endif(bin_tree_somewhere_within_source_)
  endif(V2C_WANT_SCC_SOURCE_CONTROL_IDE_INTEGRATION)
endfunction(_v2c_scc_do_setup)

_v2c_scc_do_setup()

function(_v2c_pch_do_setup)
  set(v2c_want_pch_default_setting_ ON)
  option(V2C_WANT_PCH_PRECOMPILED_HEADER_SUPPORT "Enable re-use of any existing PCH (precompiled header file) info for projects (e.g. on MSVC, gcc)" ${v2c_want_pch_default_setting_})
  if(V2C_WANT_PCH_PRECOMPILED_HEADER_SUPPORT)
    option(V2C_WANT_PCH_PRECOMPILED_HEADER_WARNINGS "Enable PCH-related compiler warnings." ON)
  endif(V2C_WANT_PCH_PRECOMPILED_HEADER_SUPPORT)
endfunction(_v2c_pch_do_setup)

_v2c_pch_do_setup()

# # # # #   COMMON HELPER FUNCTIONS   # # # # #

# Helper to yell loudly in case of unset variables.
# The input string should _not_ be the dereferenced form,
# but rather list simple _names_ of the variables.
function(_v2c_ensure_valid_variables)
  foreach(var_name_ ${ARGV})
    if(NOT DEFINED ${var_name_})
      _v2c_msg_fatal_error("important vcproj2cmake variable ${var_name_} not valid/available!?")
    endif(NOT DEFINED ${var_name_})
  endforeach(var_name_ ${ARGV})
endfunction(_v2c_ensure_valid_variables)

# Provides ON/OFF strings for the case of a non-FALSE/FALSE variable.
macro(_v2c_bool_get_status_string _var_name _out_status)
  if(${_var_name})
    set(${_out_status} "ON")
  else(${_var_name})
    set(${_out_status} "OFF")
  endif(${_var_name})
endmacro(_v2c_bool_get_status_string _var_name _out_status)

# Converts strings with whitespace and special characters
# to a flattened representation (using '_' etc.).
function(_v2c_flatten_name _in _out)
  set(special_chars_list_ " ")
  set(out_ "${_in}")
  foreach(special_char_ ${special_chars_list_})
    string(REPLACE "${special_char_}" "_" out_ "${out_}")
  endforeach(special_char_ ${special_chars_list_})
  set("${_out}" "${out_}" PARENT_SCOPE)
endfunction(_v2c_flatten_name _in _out)


function(_v2c_list_check_item_contained_exact _item _list _found_out)
  set(found_ FALSE)
  if(_list) # not empty/unset?
    if("${_list}" MATCHES ${_item}) # shortcut :)
      foreach(list_item_ ${_list})
        if(${_item} STREQUAL ${list_item_})
          set(found_ TRUE)
          break()
        endif(${_item} STREQUAL ${list_item_})
      endforeach(list_item_ ${_list})
    endif("${_list}" MATCHES ${_item})
  endif(_list)
  set(${_found_out} ${found_} PARENT_SCOPE)
endfunction(_v2c_list_check_item_contained_exact _item _list _found_out)

function(_v2c_list_locate_similar_entry _list _key _match_out)
  if(_list) # not empty/unset?
    if(_list MATCHES "${_key}")
      foreach(elem_ ${_list})
        #message("elem_ ${elem_} _key ${_key}")
        if("${elem_}" MATCHES "${_key}")
          #message("MATCH!!! ${elem_}, ${_key}")
          set(match_ "${elem_}")
          break()
        endif("${elem_}" MATCHES "${_key}")
      endforeach(elem_ ${_list})
    endif(_list MATCHES "${_key}")
  endif(_list) # not empty/unset?
  set("${_match_out}" "${match_}" PARENT_SCOPE)
endfunction(_v2c_list_locate_similar_entry _list _key _match_out)

function(_v2c_list_create_prefix_suffix_expanded_version _list _prefix _suffix _result_list)
  _v2c_var_set_empty(result_list_)
  foreach(item_ ${_list})
    list(APPEND result_list_ "${_prefix}${item_}${_suffix}")
  endforeach(item_ ${_list})
  set(${_result_list} "${result_list_}" PARENT_SCOPE)
endfunction(_v2c_list_create_prefix_suffix_expanded_version _list _prefix _suffix _result_list)

# Sets a V2C config value.
# Most input is versioned (ZZZZ_vY), to be able to do clean changes
# and detect out-of-sync impl / user.
# Uses ARGN mechanism to transparently support list variables, too
# (also, you should pass quoted strings
# when needing to preserve any space-containing content).
function(_v2c_config_set _cfg_key)
  set(cfg_values_list_ ${ARGN})
  set(cfg_key_full_ _v2c_${_cfg_key})
  set_property(GLOBAL PROPERTY ${cfg_key_full_} "${cfg_values_list_}")
endfunction(_v2c_config_set _cfg_key)

function(_v2c_config_get_unchecked _cfg_key _cfg_value_out)
  set(cfg_key_full_ _v2c_${_cfg_key})
  get_property(cfg_value_ GLOBAL PROPERTY ${cfg_key_full_})
  #message("_v2c_config_get ${_cfg_key}: ${cfg_value_}")
  set(${_cfg_value_out} "${cfg_value_}" PARENT_SCOPE)
endfunction(_v2c_config_get_unchecked _cfg_key _cfg_value_out)

function(_v2c_config_get _cfg_key _cfg_value_out)
  set(cfg_key_full_ _v2c_${_cfg_key})
  get_property(cfg_value_is_set_ GLOBAL PROPERTY ${cfg_key_full_} SET)
  if(NOT cfg_value_is_set_)
    _v2c_msg_fatal_error("_v2c_config_get: config var ${_cfg_key} not set!?")
  endif(NOT cfg_value_is_set_)
  _v2c_config_get_unchecked(${_cfg_key} cfg_value_)
  set(${_cfg_value_out} "${cfg_value_}" PARENT_SCOPE)
endfunction(_v2c_config_get _cfg_key _cfg_value_out)

function(_v2c_config_append_list_var_entry _cfg_key _cfg_value_append)
  _v2c_config_get_unchecked(${cfg_key_} cfg_value_)
  _v2c_list_check_item_contained_exact("${_cfg_value_append}" "${cfg_value_}" found_)
  if(NOT found_) # only add if not yet contained in list...
    list(APPEND cfg_value_ "${_cfg_value_append}")
    _v2c_config_set(${cfg_key_} ${cfg_value_})
  endif(NOT found_)
endfunction(_v2c_config_append_list_var_entry _cfg_key _cfg_value_append)


# Now add a one-time log helper (makes use of config helpers
# which have just been defined above).
function(_v2c_msg_important_once _magic _msg)
  _v2c_config_get_unchecked("${_magic}" _already_logged)
  if(NOT _already_logged)
    _v2c_msg_important("${_msg}")
    _v2c_config_set("${_magic}" "KO")
  endif(NOT _already_logged)
endfunction(_v2c_msg_important_once _magic _msg)

# # # # #   FEATURE CHECKS   # # # # #

# Add helper variable [non-readonly (i.e., configurable) INCLUDE_DIRECTORIES target property supported by >= 2.8.8 only]
set(_v2c_cmake_version_this "${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION}.${CMAKE_PATCH_VERSION}")

set(cmake_version_include_dirs_prop_insufficient "2.8.7")
if("${_v2c_cmake_version_this}" VERSION_GREATER "${cmake_version_include_dirs_prop_insufficient}")
  set(_v2c_feat_cmake_include_dirs_prop true)
endif("${_v2c_cmake_version_this}" VERSION_GREATER "${cmake_version_include_dirs_prop_insufficient}")


# # # # #   PROJECT INFO   # # # # #

macro(v2c_project_conversion_info_set _target _timestamp_utc _orig_environment)
  # Since timestamp format now is user-configurable, quote potential whitespace.
  set(${_target}_v2c_converted_at_utc "${_timestamp_utc}")
  set(${_target}_v2c_converted_from "${_orig_environment}")
endmacro(v2c_project_conversion_info_set _target _timestamp_utc _orig_environment)

# Assigns the original project GUID to a project
# if desired (rather than having a newly generated random GUID
# assigned by CMake).
macro(v2c_project_indicate_original_guid _target _guid)
  # TODO!! should try to establish *common* helper with *consistent* naming
  # and handling for checking target-specific enable/disable of certain
  # optional features (install, GUID, MIDL, PDB, SCC, etc.),
  # rather than doing it manually each time.
  if(V2C_WANT_PROJECT_ORIGINAL_GUID_ASSIGNED)
    set(guid_with_brackets "{${_guid}}")
    message(STATUS "${_target}: re-using its original project GUID (${guid_with_brackets}).")
    set(${_target}_GUID_CMAKE "${guid_with_brackets}" CACHE INTERNAL "Stored GUID")
  endif(V2C_WANT_PROJECT_ORIGINAL_GUID_ASSIGNED)
endmacro(v2c_project_indicate_original_guid _target _guid)


# # # # #   BUILD PLATFORM SETUP   # # # # #

function(_v2c_project_platform_append _target _build_platform)
  set(cfg_key_ ${_target}_platforms)
  _v2c_config_append_list_var_entry(${cfg_key_} "${_build_platform}")
endfunction(_v2c_project_platform_append _target _build_platform)

function(_v2c_project_platform_get_list _target _platform_list_out)
  set(cfg_key_ ${_target}_platforms)
  _v2c_config_get_unchecked(${cfg_key_} cfg_value_)
  #message("platforms: ${cfg_value_}")
  set("${_platform_list_out}" "${cfg_value_}" PARENT_SCOPE)
endfunction(_v2c_project_platform_get_list _target _platform_list_out)

function(_v2c_buildcfg_get_build_types_config_key _target _build_platform _cfg_key_out)
  _v2c_flatten_name("${_build_platform}" build_platform_flattened_)
  set(${_cfg_key_out}
  "${_target}_platform_${build_platform_flattened_}_configuration_types" PARENT_SCOPE)
endfunction(_v2c_buildcfg_get_build_types_config_key _target _build_platform _cfg_key_out)

# For a certain target (project), adds a supported platform configuration
# in combination with a list of all its config types (e.g. Debug, Release).
function(v2c_project_platform_define_build_types _target _build_platform)
  _v2c_project_platform_append(${_target} ${_build_platform})
  set(build_types_ ${ARGN})
  _v2c_buildcfg_get_build_types_config_key("${_target}" "${_build_platform}" cfg_key_)
  _v2c_config_set(${cfg_key_} ${build_types_})
endfunction(v2c_project_platform_define_build_types _target _build_platform)

function(_v2c_project_platform_get_build_types _target _build_platform _build_types_list_out)
  _v2c_buildcfg_get_build_types_config_key("${_target}" "${_build_platform}" cfg_key_)
  _v2c_config_get_unchecked(${cfg_key_} cfg_value_)
  set(${_build_types_list_out} "${cfg_value_}" PARENT_SCOPE)
endfunction(_v2c_project_platform_get_build_types _target _build_platform _build_types_list_out)

function(_v2c_buildcfg_get_magic_conditional_name _target _build_platform _build_type _var_name_out)
  if(_build_platform AND _build_type)
  else(_build_platform AND _build_type)
    _v2c_msg_warning("v2c_buildcfg_check_if_platform_buildtype_active: empty platform [${_build_platform}] or build type [${_build_type}]!?")
  endif(_build_platform AND _build_type)
  _v2c_flatten_name("${_build_platform}" build_platform_flattened_)
  _v2c_flatten_name("${_build_type}" build_type_flattened_)
  set(${_var_name_out} v2c_want_buildcfg_platform_${build_platform_flattened_}_build_type_${build_type_flattened_} PARENT_SCOPE)
endfunction(_v2c_buildcfg_get_magic_conditional_name _target _build_platform _build_type _var_name_out)

if(CMAKE_CONFIGURATION_TYPES)
  function(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
    set(val_ FALSE)
    if(V2C_BUILD_PLATFORM STREQUAL "${_build_platform}")
      set(val_ TRUE)
    endif(V2C_BUILD_PLATFORM STREQUAL "${_build_platform}")
    set(${_var_out} ${val_} PARENT_SCOPE)
  endfunction(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
else(CMAKE_CONFIGURATION_TYPES)
  function(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
    set(val_ FALSE)
    if(V2C_BUILD_PLATFORM STREQUAL "${_build_platform}")
      if(CMAKE_BUILD_TYPE STREQUAL "${_build_type}")
        set(val_ TRUE)
      endif(CMAKE_BUILD_TYPE STREQUAL "${_build_type}")
    endif(V2C_BUILD_PLATFORM STREQUAL "${_build_platform}")
    set(${_var_out} ${val_} PARENT_SCOPE)
  endfunction(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
endif(CMAKE_CONFIGURATION_TYPES)

# Sets the values of the magic variables which all the other
# platform / build type decision-making helpers rely on.
# *V2C_DOCS_POLICY_MACRO*
macro(_v2c_buildcfg_define_magic_conditionals _target)
  _v2c_project_platform_get_list("${_target}" platform_list_)
  foreach(platform_ ${platform_list_})
    _v2c_project_platform_get_build_types(${_target} "${platform_}" build_types_list_)
    foreach(build_type_ ${build_types_list_})
      _v2c_buildcfg_get_magic_conditional_name(${_target} "${platform_}" "${build_type_}" magic_conditional_name_)
      _v2c_buildcfg_define_magic_conditional(${_target} "${platform_}" "${build_type_}" value_)
      set(${magic_conditional_name_} ${value_})
    endforeach(build_type_ ${build_types_list_})
  endforeach(platform_ ${platform_list_})
endmacro(_v2c_buildcfg_define_magic_conditionals _target)

# Pragmatically spoken, it queries a boolean flag that indicates
# whether we want to include (i.e., activate) certain CMake script parts
# which are specific to certain platform / build type combinations.
# This is currently simply done by returning the value of a certain
# internal boolean marker variable.
# And here's hope that we can keep doing it this way...
# This check should actually be nicely compatible with both
# CMAKE_CONFIGURATION_TYPES-based generators and CMAKE_BUILD_TYPE
# ones.
function(v2c_buildcfg_check_if_platform_buildtype_active _target _build_platform _build_type _is_active_out)
  _v2c_buildcfg_get_magic_conditional_name("${_target}" "${_build_platform}" "${_build_type}" magic_conditional_name_)
  set(${_is_active_out} "${${magic_conditional_name_}}" PARENT_SCOPE)
endfunction(v2c_buildcfg_check_if_platform_buildtype_active _target _build_platform _build_type _is_active_out)

# On CMake generators which are not able to switch TARGET platforms
# on-demand
# (this is both non-CMAKE_CONFIGURATION_TYPES generators [Ninja, Makefile, ...]
# *and* generators for actually would-be-runtime-config-capable
# environments such as Visual Studio!),
# configures the variable indicating the platform to statically configure
# the build for,
# otherwise (for supporting generators, of which there currently are NONE)
# provide dummy.
set(_v2c_generator_has_dynamic_platform_switching FALSE)
if(_v2c_generator_has_dynamic_platform_switching)
  function(v2c_platform_build_setting_configure _target)
    # DUMMY (not needed on certain generators)
  endfunction(v2c_platform_build_setting_configure _target)
else(_v2c_generator_has_dynamic_platform_switching)
  function(_v2c_platform_determine_default _platform_names_list _platform_default_out _platform_reason_out)
    #message("CMAKE_SIZEOF_VOID_P ${CMAKE_SIZEOF_VOID_P}")
    if(CMAKE_SIZEOF_VOID_P)
      if(CMAKE_SIZEOF_VOID_P EQUAL 4)
        set(platform_key_ "32")
	set(platform_reason_ "detected 32bit platform")
      endif(CMAKE_SIZEOF_VOID_P EQUAL 4)
      if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(platform_key_ "64")
	set(platform_reason_ "detected 64bit platform")
      endif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    else(CMAKE_SIZEOF_VOID_P)
      # On several platforms (CMake platform setup modules)
      # CMAKE_SIZEOF_VOID_P isn't set at all :(
      # (Win7 x64 CMake platform setup is said to have failed to provide it,
      # and also arch 64).
      # In such pathological cases, it might be a good idea to fall back
      # to some other kind of system introspection
      # (perhaps try_compile(), execute_process()).
      _v2c_msg_fixme("CMAKE_SIZEOF_VOID_P not available - currently assuming 32bit!")
      set(platform_key_ "32")
      set(platform_reason_ "unknown platform bitwidth - fallback to 32bit")
    endif(CMAKE_SIZEOF_VOID_P)
    if(platform_key_)
      # TODO: could perhaps try to figure out things in a more precise way,
      # by intelligently evaluating both a bitwidth (32/64) input parameter
      # _and_ a platform input parameter (from CMAKE_SYSTEM, uname, ...).
      _v2c_list_locate_similar_entry("${_platform_names_list}" "${platform_key_}" platform_default_)
    endif(platform_key_)
    if(NOT platform_default_)
      # Oh well... let's fetch the first entry and use that as default...
      if(_platform_names_list)
        list(GET _platform_names_list 0 platform_default_)
        set(platform_reason_ "chose first platform entry as default")
      endif(_platform_names_list)
    endif(NOT platform_default_)
    if(NOT platform_default_)
      _v2c_msg_fatal_error_please_report("detected final failure to figure out a build platform setting (choices: [${_platform_names_list}])")
    endif(NOT platform_default_)
    if(NOT platform_reason_)
      _v2c_msg_fatal_error_please_report("No reason for platform selection given")
    endif(NOT platform_reason_)
    set(${_platform_default_out} "${platform_default_}" PARENT_SCOPE)
    set(${_platform_reason_out} "${platform_reason_}" PARENT_SCOPE)
  endfunction(_v2c_platform_determine_default _platform_names_list _platform_default_out _platform_reason_out)

  function(_v2c_buildcfg_determine_platform_var _target)
    _v2c_project_platform_get_list(${_target} platform_names_list_)
    # Check var definition (avoid rerun):
    if(V2C_BUILD_PLATFORM)
      # Hmm... preserving the reason variable content is a bit difficult
      # in light of V2C_BUILD_PLATFORM being a CACHE variable
      # (unless we make this CACHE as well).
      # Thus simply pretend it to be user-selected whenever it's read from cache.
      set(platform_reason_ "user-selected entry")
    else(V2C_BUILD_PLATFORM)
      _v2c_platform_determine_default("${platform_names_list_}" platform_default_setting_ platform_reason_)
      set(platform_doc_string_ "The TARGET (not necessarily identical to this build HOST!) platform to create the build for [possible values: [${platform_names_list_}]]")
      # Offer the main configuration cache variable to the user:
      set(V2C_BUILD_PLATFORM "${platform_default_setting_}" CACHE STRING ${platform_doc_string_})
    endif(V2C_BUILD_PLATFORM)
    _v2c_list_check_item_contained_exact("${V2C_BUILD_PLATFORM}" "${platform_names_list_}" platform_ok_)
    if(platform_ok_)
      _v2c_msg_important_once("build_platform" "${_target}: vcproj2cmake chose to adopt the following project-defined build platform setting: ${V2C_BUILD_PLATFORM} (reason: ${platform_reason_}).")
    else(platform_ok_)
      _v2c_msg_fatal_error("V2C_BUILD_PLATFORM contains invalid build platform setting (${V2C_BUILD_PLATFORM}), please correct! (valid candidates: ${platform_names_list_})")
    endif(platform_ok_)
  endfunction(_v2c_buildcfg_determine_platform_var _target)

  # *V2C_DOCS_POLICY_MACRO*
  macro(v2c_platform_build_setting_configure _target)
    _v2c_buildcfg_determine_platform_var(${_target})
    _v2c_buildcfg_define_magic_conditionals(${_target})
  endmacro(v2c_platform_build_setting_configure _target)
endif(_v2c_generator_has_dynamic_platform_switching)


# # # # #   VCPROJ2CMAKE CONVERTER REBUILDER SETUP   # # # # #

function(_v2c_config_do_setup_rebuilder)
  # Some one-time setup steps:

  # Have a user-side update_cmakelists_ALL convenience target:
  # enables updating _all_ outdated CMakeLists.txt files within a project hierarchy.
  # Providing _this_ particular target (as a dummy) is _always_ needed,
  # even if the rebuild mechanism cannot be provided (missing script, etc.).
  if(NOT TARGET update_cmakelists_ALL)
    add_custom_target(update_cmakelists_ALL)
  endif(NOT TARGET update_cmakelists_ALL)

  if(NOT RUBY_EXECUTABLE) # avoid repeated checks (see cmake --trace)
    find_package(Ruby)
    if(NOT RUBY_EXECUTABLE)
      _v2c_msg_warning("could not detect your ruby installation (perhaps forgot to set CMAKE_PREFIX_PATH?), bailing out: won't automagically rebuild CMakeLists.txt on changes...")
      return()
    endif(NOT RUBY_EXECUTABLE)
  endif(NOT RUBY_EXECUTABLE)

  set(cmakelists_rebuilder_deps_static_list_
    ${root_mappings_files_list_}
    "${project_exclude_list_file_location_}"
    "${RUBY_EXECUTABLE}"
    # TODO add any other relevant dependencies here
  )
  _v2c_config_set(cmakelists_rebuilder_deps_static_list_v1
    "${cmakelists_rebuilder_deps_static_list_}"
  )

  _v2c_config_set(cmakelists_update_check_stamp_file_v1 "${V2C_STAMP_FILES_DIR}/v2c_cmakelists_update_check_done.stamp")

  if(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)
    # See also
    # "Re: Makefile: 'abort' command? / 'elseif' to go with ifeq/else/endif?
    #   (Make newbie)" http://www.mail-archive.com/help-gnu-utils@gnu.org/msg00736.html
    if(UNIX)
      # WARNING: make sure to fetch and always use the binary's full path,
      # since otherwise we'd end up with a simple "false" string
      # which is highly conflict-prone with CMake's "false" boolean evaluation!!
      find_program(V2C_ABORT_BIN
        false
        DOC "A small program whose only purpose is to be suitable to signal failure (i.e. which provides a non-successful execution return value), usually /bin/false on UNIX; may alternatively be set to an invalid program name, too."
      )
      _v2c_ensure_valid_variables(V2C_ABORT_BIN)
      _v2c_config_set(ABORT_BIN_v1 "${V2C_ABORT_BIN}")
    else(UNIX)
      _v2c_config_set(ABORT_BIN_v1 v2c_invoked_non_existing_command_simply_to_force_build_abort)
    endif(UNIX)
    # Provide a marker file, to enable external build invokers
    # to determine whether a (supposedly entire) build
    # was aborted due to CMakeLists.txt conversion and thus they
    # should immediately resume with a new build...
    _v2c_config_set(cmakelists_update_check_did_abort_public_marker_file_v1 "${V2C_STAMP_FILES_DIR}/v2c_cmakelists_update_check_did_abort.marker")
    # This is the stamp file for the subsequent "cleanup" target
    # (oh yay, we even need to have the marker file removed on next build launch again).
    _v2c_config_set(update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1 "${V2C_STAMP_FILES_DIR}/v2c_cmakelists_update_abort_cleanup_done.stamp")

     # Provide API helper, for user-side build scripts to know how to detect
     # that a build abort occured.
     function(v2c_rebuilder_build_abort_get_marker_file _res_out)
       _v2c_config_get(update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1 update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_)
       set(${_res_out} "${update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_}" PARENT_SCOPE)
     endfunction(v2c_rebuilder_build_abort_get_marker_file _res_out)
  endif(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)
  # Provide API helper for user-side query.
  macro(v2c_rebuilder_build_abort_is_enabled _res_out)
    set(${_res_out} ${V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD})
  endmacro(v2c_rebuilder_build_abort_is_enabled _res_out)
endfunction(_v2c_config_do_setup_rebuilder)

function(_v2c_config_do_setup)
  # FIXME: should obey V2C_LOCAL_CONFIG_RELPATH setting!! Nope, this is a
  # reference to the _global_ one here...
  set(global_config_subdir_ "${V2C_GLOBAL_CONFIG_RELPATH}")

  # These files are OPTIONAL elements of the source tree!
  # (thus we shouldn't carelessly list them as target file dependencies etc.)
  # To ensure their availability (might be useful),
  # we could have touched any non-existing files,
  # but this would fumble the *source* tree, thus we decide to not do it.

  set(project_exclude_list_file_check_ "${CMAKE_SOURCE_DIR}/${global_config_subdir_}/project_exclude_list.txt")
  _v2c_var_set_empty(project_exclude_list_file_location_)
  if(EXISTS "${project_exclude_list_file_check_}")
    set(project_exclude_list_file_location_ "${project_exclude_list_file_check_}")
  endif(EXISTS "${project_exclude_list_file_check_}")
  _v2c_config_set(project_exclude_list_file_location_v1 "${project_exclude_list_file_location_}")

  set(mappings_files_expr_ "${global_config_subdir_}/*_mappings.txt")
  _v2c_config_set(mappings_files_expr_v1 "${mappings_files_expr_}")

  file(GLOB root_mappings_files_list_ "${CMAKE_SOURCE_DIR}/${mappings_files_expr_}")
  _v2c_config_set(root_mappings_files_list_v1 "${root_mappings_files_list_}")


  # Now do rebuilder setup within this function, too,
  # to have direct access to parent scope's important configuration variables.
  if(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
    _v2c_config_do_setup_rebuilder()
  endif(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)

  # Provide API helper for user-side query of rebuilder activation status.
  # Once active, further rebuilder APIs may be called.
  macro(v2c_rebuilder_enabled _res_out)
    set(${_res_out} ${V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER})
  endmacro(v2c_rebuilder_enabled _res_out)
endfunction(_v2c_config_do_setup)

_v2c_config_do_setup()

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

function(_v2c_target_file_under _target _category)
  if(TARGET ${_target})
    set(folder_name_ "vcproj2cmake")
    if(_category)
      set(folder_name_full_ "${folder_name_}/${_category}")
    else(_category)
      set(folder_name_full_ "${folder_name_}")
    endif(_category)
    set_property(TARGET ${_target} PROPERTY FOLDER "${folder_name_full_}")
  endif(TARGET ${_target})
endfunction(_v2c_target_file_under _target _category)

function(_v2c_target_mark_as_internal _target)
  _v2c_target_file_under("${_target}" "INTERNAL")
endfunction(_v2c_target_mark_as_internal _target)

# Debug-only helper!
function(_v2c_target_log_configuration _target)
  if(TARGET ${_target})
    get_property(vs_scc_projectname_ TARGET ${_target} PROPERTY VS_SCC_PROJECTNAME)
    get_property(vs_scc_localpath_ TARGET ${_target} PROPERTY VS_SCC_LOCALPATH)
    get_property(vs_scc_provider_ TARGET ${_target} PROPERTY VS_SCC_PROVIDER)
    get_property(vs_scc_auxpath_ TARGET ${_target} PROPERTY VS_SCC_AUXPATH)
    _v2c_msg_fatal_error("Properties/settings target ${_target}:\n\tvs_scc_projectname_ ${vs_scc_projectname_}\n\tvs_scc_localpath_ ${vs_scc_localpath_}\n\tvs_scc_provider_ ${vs_scc_provider_}\n\tvs_scc_auxpath_ ${vs_scc_auxpath_}")
  endif(TARGET ${_target})
endfunction(_v2c_target_log_configuration _target)

macro(_v2c_touch_file _file)
  # Let's hope file(APPEND "") successfully updates the timestamp only,
  # otherwise resort to cmake -E touch_nocreate.
  file(APPEND "${_file}" "")
endmacro(_v2c_touch_file _file)

function(_v2c_pre_touch_output_file _target_pseudo_output_file _actual_output_file _file_dependencies_list)
  # Don't inhibit a rebuild if the output file does not even exist yet:
  if(NOT EXISTS "${_actual_output_file}")
    return()
  endif(NOT EXISTS "${_actual_output_file}")
  set(needs_remake_ false)
  foreach(dep_ ${_file_dependencies_list})
    if("${dep_}" IS_NEWER_THAN "${_actual_output_file}")
      set(needs_remake_ true)
      break()
    endif("${dep_}" IS_NEWER_THAN "${_actual_output_file}")
  endforeach(dep_ ${_file_dependencies_list})
  if(NOT needs_remake_)
    # We don't need a remake, thus update the pseudo output stamp file:
    _v2c_msg_info("${_actual_output_file} is current (no remake needed).")
    _v2c_touch_file("${_target_pseudo_output_file}")
  endif(NOT needs_remake_)
endfunction(_v2c_pre_touch_output_file _target_pseudo_output_file _actual_output_file _file_dependencies_list)

function(_v2c_projects_find_valid_target _projects_list _target_out)
  _v2c_var_set_empty(target_)
  # Loop until we find an actually existing target
  # within the list of project names
  # (some projects may be header-only, thus no lib/exe targets).
  foreach(proj_ ${_projects_list})
    if(TARGET ${proj_})
      set(target_ ${proj_})
      break()
    endif(TARGET ${proj_})
  endforeach(proj_ ${_projects_list})
  set(${_target_out} ${target_} PARENT_SCOPE)
endfunction(_v2c_projects_find_valid_target _projects_list _target_out)

# Use the stamp file as the final criteria to check
# whether rebuilder setup was successful:
_v2c_config_get_unchecked(cmakelists_update_check_stamp_file_v1 v2c_cmakelists_rebuilder_available)
if(v2c_cmakelists_rebuilder_available)
  function(_v2c_cmakelists_rebuild_recursively _v2c_scripts_base_path _v2c_cmakelists_rebuilder_deps_common_list)
    set(cmakelists_target_rebuild_all_name_ update_cmakelists_rebuild_recursive_ALL)
    if(TARGET ${cmakelists_target_rebuild_all_name_})
      return() # Nothing left to do...
    endif(TARGET ${cmakelists_target_rebuild_all_name_})
    # Need to manually derive the name of the recursive script...
    set(script_recursive_ "${_v2c_scripts_base_path}/vcproj2cmake_recursive.rb")
    if(NOT EXISTS "${script_recursive_}")
      return()
    endif(NOT EXISTS "${script_recursive_}")
    _v2c_msg_info("Providing fully recursive CMakeLists.txt rebuilder target ${cmakelists_target_rebuild_all_name_}, to forcibly enact a recursive .vc[x]proj --> CMake reconversion of all source tree sub directories.")
    set(cmakelists_update_recursively_updated_stamp_file_ "${CMAKE_CURRENT_BINARY_DIR}/cmakelists_recursive_converter_done.stamp")
    set(cmakelists_rebuilder_deps_recursive_list_
      ${_v2c_cmakelists_rebuilder_deps_common_list}
      "${script_recursive_}"
    )
    # For now, we'll NOT add the "ALL" attribute
    # since this global recursive target is supposed to be
    # a _forced_, one-time explicitly user-requested operation.
    add_custom_target(${cmakelists_target_rebuild_all_name_}
      COMMAND "${RUBY_EXECUTABLE}" "${script_recursive_}"
      WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
      DEPENDS ${cmakelists_rebuilder_deps_recursive_list_}
      COMMENT "Doing recursive .vcproj --> CMakeLists.txt conversion in all source root sub directories."
    )
    # TODO: I wanted to add an extra target as an observer of the excluded projects file,
    # but this does not work properly yet -
    # ${cmakelists_target_rebuild_all_name_} should run unconditionally,
    # yet the depending observer target is supposed to be an ALL target which only triggers rerun
    # in case of that excluded projects file dependency being dirty -
    # which does not work since the rebuilder target will then _always_ run on a "make all" build.
    #set(cmakelists_update_recursively_updated_observer_stamp_file_ "${CMAKE_CURRENT_BINARY_DIR}/cmakelists_recursive_converter_observer_done.stamp")
    # _v2c_config_get(project_exclude_list_file_location_v1 project_exclude_list_file_location_v1_)
    #add_custom_command(OUTPUT "${cmakelists_update_recursively_updated_observer_stamp_file_}"
    #  COMMAND "${CMAKE_COMMAND}" -E touch "${cmakelists_update_recursively_updated_observer_stamp_file_}"
    #  DEPENDS "${project_exclude_list_file_location_v1_}"
    #)
    #add_custom_target(update_cmakelists_rebuild_recursive_ALL_observer ALL DEPENDS "${cmakelists_update_recursively_updated_observer_stamp_file_}")
    #add_dependencies(update_cmakelists_rebuild_recursive_ALL_observer ${cmakelists_target_rebuild_all_name_})
  endfunction(_v2c_cmakelists_rebuild_recursively _v2c_scripts_base_path _v2c_cmakelists_rebuilder_deps_common_list)

  # Function to automagically rebuild our converted CMakeLists.txt
  # by the original converter script in case any relevant files changed.
  function(_v2c_project_rebuild_on_update _directory_projects_list _dir_orig_proj_files_list _cmakelists_file _script _master_proj_dir)
    _v2c_ensure_valid_variables(_directory_projects_list)
    _v2c_projects_find_valid_target("${_directory_projects_list}" dependent_target_main_)
    if(NOT dependent_target_main_)
      # Oh well... we didn't manage to find a valid target,
      # but at least resort to choosing the first entry in the list.
      list(GET _directory_projects_list 0 dependent_target_main_)
    endif(NOT dependent_target_main_)
    _v2c_ensure_valid_variables(dependent_target_main_)

    _v2c_msg_info("${dependent_target_main_}: providing ${_cmakelists_file} rebuilder (watching ${_dir_orig_proj_files_list})")

    if(NOT EXISTS "${_script}")
      # Perhaps someone manually copied over a set of foreign-machine-converted CMakeLists.txt files...
      # --> make sure that this use case does not fail anyway.
      _v2c_msg_warning("${dependent_target_main_}: vcproj2cmake converter script ${_script} not found, cannot activate automatic reconversion functionality!")
      return()
    endif(NOT EXISTS "${_script}")

    # There are some uncertainties about how to locate the ruby script.
    # for now, let's just hardcode a "must have been converted from root project" requirement.
    ## canonicalize script, to be able to precisely launch it via a CMAKE_SOURCE_DIR root dir base
    #file(RELATIVE_PATH _script_rel "${CMAKE_SOURCE_DIR}" "${_script}")
    ##message(FATAL_ERROR "_script ${_script} _script_rel ${_script_rel}")

    get_filename_component(v2c_scripts_base_path_ "${_script}" PATH)
    set(v2c_scripts_lib_path_ "${v2c_scripts_base_path_}/lib/vcproj2cmake")
    # This is currently the actual implementation file which will be changed most frequently:
    set(script_core_ "${v2c_scripts_lib_path_}/v2c_core.rb")
    # Need to manually derive the name of the settings script...
    set(script_settings_ "${v2c_scripts_base_path_}/vcproj2cmake_settings.rb")
    set(script_settings_user_check_ "${v2c_scripts_base_path_}/vcproj2cmake_settings.user.rb")
    # Avoid adding a dependency on a non-existing file:
    if(EXISTS "${script_settings_user_check_}")
      set(script_settings_user_ "${script_settings_user_check_}")
    endif(EXISTS "${script_settings_user_check_}")
    # All v2c scripts, MINUS the two script frontends
    # that our specific targets happen to use.
    set(cmakelists_rebuilder_deps_v2c_common_list_
      "${script_core_}"
      "${script_settings_}"
      "${script_settings_user_}"
    )

    _v2c_config_get(cmakelists_rebuilder_deps_static_list_v1 cmakelists_rebuilder_deps_static_list_v1_)
    set(cmakelists_rebuilder_deps_common_list_
      ${cmakelists_rebuilder_deps_static_list_v1_}
      ${cmakelists_rebuilder_deps_v2c_common_list_}
    )
    # TODO add any other relevant dependencies here

    # Hrmm, this is a wee bit unclean: since we gather access to the script name
    # only in case of an invocation of this function,
    # we'll have to invoke the recursive-rebuild function _within_ here, too.
    _v2c_cmakelists_rebuild_recursively("${v2c_scripts_base_path_}" "${cmakelists_rebuilder_deps_common_list_}")

    # Collect dependencies for mappings files in current project, too:
    _v2c_config_get(mappings_files_expr_v1 mappings_files_expr_v1_)
    file(GLOB proj_mappings_files_list_ "${mappings_files_expr_v1_}")

    set(cmakelists_rebuilder_deps_list_ ${_dir_orig_proj_files_list} "${_script}" ${proj_mappings_files_list_} ${cmakelists_rebuilder_deps_common_list_})
    #message(FATAL_ERROR "cmakelists_rebuilder_deps_list_ ${cmakelists_rebuilder_deps_list_}")

    _v2c_config_get(cmakelists_update_check_stamp_file_v1 cmakelists_update_check_stamp_file_v1_)

    # Need an intermediate stamp file, otherwise "make clean" will clean
    # our live output file (CMakeLists.txt) [and there's no suitable mechanism
    # to tell CMake to skip cleaning a target, other than a drastic per-dir
    # CLEAN_NO_CUSTOM], yet we crucially need to preserve it
    # since it hosts this very CMakeLists.txt rebuilder mechanism...
    set(cmakelists_update_this_cmakelists_updated_stamp_file_ "${CMAKE_CURRENT_BINARY_DIR}/cmakelists_rebuilder_done.stamp")
    # To avoid an annoying needless rebuild of the conversion
    # after an external script conversion run,
    # update timestamp of output file if possible.
    # Wellll... on certain environments this does NOT happen in the first place.
    # Needs more investigation.
    #_v2c_pre_touch_output_file("${cmakelists_update_this_cmakelists_updated_stamp_file_}" "${_cmakelists_file}" "${_dir_orig_proj_files_list}")
    list(GET _dir_orig_proj_files_list 0 orig_proj_file_main_) # HACK
    if("${orig_proj_file_main_}" STREQUAL "${_dir_orig_proj_files_list}")
    else("${orig_proj_file_main_}" STREQUAL "${_dir_orig_proj_files_list}")
      # vcproj2cmake.rb currently only converts a single project file.
      # Need to modify it to use a proper getopts() mechanism.
      _v2c_msg_fixme("reconversion currently is not able to properly handle _multiple_ project()s (i.e. VS project files) per _single_ CMakeLists.txt file (i.e. directory).")
    endif("${orig_proj_file_main_}" STREQUAL "${_dir_orig_proj_files_list}")
    # TODO: it might be useful to provide one subsequent target which exists
    # for the sole purpose of providing a log message
    # that *all* CMakeLists.txt re-conversion activity ended successfully.
    # That subsequent target would have to be chained in such a way to ensure
    # that it gets executed after *all* conversion targets are done.
    # THE ACTUAL CONVERSION COMMAND:
    add_custom_command(OUTPUT "${cmakelists_update_this_cmakelists_updated_stamp_file_}"
      COMMAND "${RUBY_EXECUTABLE}" "${_script}" "${orig_proj_file_main_}" "${_cmakelists_file}" "${_master_proj_dir}"
      COMMAND "${CMAKE_COMMAND}" -E remove -f "${cmakelists_update_check_stamp_file_v1_}"
      COMMAND "${CMAKE_COMMAND}" -E touch "${cmakelists_update_this_cmakelists_updated_stamp_file_}"
      DEPENDS ${cmakelists_rebuilder_deps_list_}
      COMMENT "VS project settings changed, rebuilding ${_cmakelists_file}"
    )
    # TODO: do we have to set_source_files_properties(GENERATED) on ${_cmakelists_file}?

    if(NOT TARGET update_cmakelists_ALL__internal_collector)
      set(need_init_main_targets_this_time_ true)

      # This is the lower-level target which encompasses all .vcproj-based
      # sub projects (always separate this from external higher-level
      # target, to be able to implement additional mechanisms):
      add_custom_target(update_cmakelists_ALL__internal_collector)
      _v2c_target_mark_as_internal(update_cmakelists_ALL__internal_collector)
    endif(NOT TARGET update_cmakelists_ALL__internal_collector)

    # NOTE: we use update_cmakelists_[TARGET] names instead of [TARGET]_...
    # since in certain IDEs these peripheral targets will end up as user-visible folders
    # and we want to keep them darn out of sight via suitable sorting!
    # (but see also TARGET property "FOLDER"). TODO: add a clever fully compatible
    # add_custom_target() wrapper which already does the required FOLDER sorting, too.
    set(target_cmakelists_update_this_projdir_name_ update_cmakelists_DIR_${dependent_target_main_})
    #add_custom_target(${target_cmakelists_update_this_projdir_name_} DEPENDS "${_cmakelists_file}")
    add_custom_target(${target_cmakelists_update_this_projdir_name_} ALL DEPENDS "${cmakelists_update_this_cmakelists_updated_stamp_file_}")
#    add_dependencies(${target_cmakelists_update_this_projdir_name_} update_cmakelists_rebuild_happened)

    add_dependencies(update_cmakelists_ALL__internal_collector ${target_cmakelists_update_this_projdir_name_})
    # Now establish new rebuild targets for all *project* build targets,
    # to the *one common* *directory-wide* rebuilder (aborting version!!) of the config
    # which encompasses those within-dir projects:
    foreach(proj_ ${_directory_projects_list})
      set(tgt_name_ update_cmakelists_${proj_})
      add_custom_target(${tgt_name_})
      add_dependencies(${tgt_name_} ${target_cmakelists_update_this_projdir_name_})
    endforeach(proj_ ${_directory_projects_list})

    ### IMPLEMENTATION OF ABORT HANDLING ###

    # We definitely need to implement aborting the build process directly
    # whenever build activity wants to continue directly
    # after any new CMakeLists.txt files have been generated
    # (we don't want to go full steam ahead with _old_ CMakeLists.txt content).
    # Ideally processing should be aborted after _all_ sub projects
    # have been converted, but _before_ any of these progress towards
    # building - thus let's just implement it like that ;)
    # This way external build invokers can attempt to do an entire build
    # and if it fails check whether it failed due to conversion and then
    # restart the build. Without this mechanism, external build invokers
    # would _always_ have to first do a separate update_cmakelists_ALL
    # build and _then_ have an additional full build, which wastes
    # valuable seconds for each build of any single file within the
    # project.
    # Unfortunately for certain generators/environments (e.g. "Visual Studio 8 2005")
    # there's no dedicated build script which oversees that two-stage build process,
    # but rather execution of "all" targets; this then leads to a _partial_ abort
    # in the CMakeLists.txt update part, yet other build activity continues for a while.

    # FIXME: should use that V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD conditional
    # to establish (during one-time setup) a _dummy/non-dummy_ _function_ for rebuild abort handling.
    if(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)
      if(need_init_main_targets_this_time_)
        _v2c_config_get(cmakelists_update_check_did_abort_public_marker_file_v1 cmakelists_update_check_did_abort_public_marker_file_v1_)
        _v2c_config_get(update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1 update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_)
        _v2c_config_get(ABORT_BIN_v1 ABORT_BIN_v1_)
        # THE BUILD ABORT COMMAND:
        add_custom_command(OUTPUT "${cmakelists_update_check_stamp_file_v1_}"
          # Obviously we need to touch the output file (success indicator) _before_ aborting by invoking false.
          # But before doing that, we also need to touch (create!)
          # the public marker file as well.
          COMMAND "${CMAKE_COMMAND}" -E touch "${cmakelists_update_check_stamp_file_v1_}" "${cmakelists_update_check_did_abort_public_marker_file_v1_}"
          COMMAND "${CMAKE_COMMAND}" -E remove -f "${update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_}"
          COMMAND "${ABORT_BIN_v1_}"
          # ...and of course add another clever message command
          # right _after_ the abort processing,
          # to alert people whenever aborting happened to fail:
          COMMAND "${CMAKE_COMMAND}" -E echo "Huh, attempting to abort the build [via ${ABORT_BIN_v1_}] failed?? Probably this simply is an ignore-errors build run, otherwise PLEASE REPORT..."
          # Hrmm, I thought that we _need_ this dependency, otherwise at least on Ninja the
          # command will not get triggered _within_ the same build run (by the preceding target
          # removing the output file). But apparently that does not help
          # either.
#          DEPENDS "${rebuild_occurred_marker_file}"
	  # Mention that this is about V2C targets only (we obviously cannot exert influence on any targets created in non-V2C areas).
          COMMENT ">>> === Detected a rebuild of CMakeLists.txt files - forcefully aborting the current outdated build run of V2C targets [force new updated-settings configure run]! <<< ==="
        )
        add_custom_target(update_cmakelists_abort_build_after_update DEPENDS "${cmakelists_update_check_stamp_file_v1_}")

        add_custom_command(OUTPUT "${update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_}"
          COMMAND "${CMAKE_COMMAND}" -E remove -f "${cmakelists_update_check_did_abort_public_marker_file_v1_}"
          COMMAND "${CMAKE_COMMAND}" -E touch "${update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_}"
          COMMENT "removed public marker file (for newly converted CMakeLists.txt signalling)!"
        )
        # Mark this target as ALL since it's VERY important that it gets
        # executed ASAP.
        add_custom_target(update_cmakelists_abort_build_after_update_cleanup ALL
          DEPENDS "${update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_}")

        add_dependencies(update_cmakelists_ALL update_cmakelists_abort_build_after_update_cleanup)
        add_dependencies(update_cmakelists_abort_build_after_update_cleanup update_cmakelists_abort_build_after_update)
        add_dependencies(update_cmakelists_abort_build_after_update update_cmakelists_ALL__internal_collector)
      endif(need_init_main_targets_this_time_)
      add_dependencies(update_cmakelists_abort_build_after_update ${target_cmakelists_update_this_projdir_name_})
      set(target_cmakelists_ensure_rebuilt_name_ update_cmakelists_ALL)
    else(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)
      if(need_init_main_targets_this_time_)
        add_dependencies(update_cmakelists_ALL update_cmakelists_ALL__internal_collector)
      endif(need_init_main_targets_this_time_)
      set(target_cmakelists_ensure_rebuilt_name_ ${target_cmakelists_update_this_projdir_name_})
    endif(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)

    # in the list of project(s) of a directory an actual project target
    # might not be available (i.e. all are header-only project(s)).
    if(TARGET ${dependent_target_main_})
      # Make sure the CMakeLists.txt rebuild happens _before_ trying to build the actual target.
      add_dependencies(${dependent_target_main_} ${target_cmakelists_ensure_rebuilt_name_})
    endif(TARGET ${dependent_target_main_})
  endfunction(_v2c_project_rebuild_on_update _directory_projects_list _dir_orig_proj_files_list _cmakelists_file _script _master_proj_dir)
else(v2c_cmakelists_rebuilder_available)
  function(_v2c_project_rebuild_on_update _directory_projects_list _dir_orig_proj_files_list _cmakelists_file _script _master_proj_dir)
    # DUMMY!
  endfunction(_v2c_project_rebuild_on_update _directory_projects_list _dir_orig_proj_files_list _cmakelists_file _script _master_proj_dir)
endif(v2c_cmakelists_rebuilder_available)
if(v2c_cmakelists_rebuilder_available)
  # *V2C_DOCS_POLICY_MACRO*
  macro(v2c_converter_script_set_location _location)
    # user override mechanism (don't prevent specifying a custom location of this script)
    _v2c_var_set_default_if_not_set(V2C_SCRIPT_LOCATION "${_location}")
  endmacro(v2c_converter_script_set_location _location)
else(v2c_cmakelists_rebuilder_available)
  macro(v2c_converter_script_set_location _location)
    # DUMMY!
  endmacro(v2c_converter_script_set_location _location)
endif(v2c_cmakelists_rebuilder_available)

# *V2C_DOCS_POLICY_MACRO*
macro(v2c_hook_invoke _hook_file_name)
  # Prevent problematic outcome of calls with empty variable
  # (see our CMake bug #13388).
  #
  # For some very weird reason evaluating the macro parameter itself
  # (i.e., the externally defined variable) via if(var) does NOT work -
  # we need to assign to a *local* evaluation helper...
  # (also, use very specific variable naming since we're a macro
  # --> global pollution!)
  set(v2c_hook_file_name_ "${_hook_file_name}")
  if(v2c_hook_file_name_)
    include("${v2c_hook_file_name_}" OPTIONAL)
  endif(v2c_hook_file_name_)
endmacro(v2c_hook_invoke _hook_file_name)

# Configure CMAKE_MFC_FLAG etc.
# _Unfortunately_ CMake historically decided to have these very dirty global flags
# rather than a per-target property. Should eventually be fixed there.
# *V2C_DOCS_POLICY_MACRO*
macro(v2c_local_set_cmake_atl_mfc_flags _target _build_platform _build_type _atl_flag _mfc_flag)
  v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
  # If active, then _we_ are the one to define the setting,
  # otherwise some other invocation will define it.
  if(is_active_)
    # CMAKE_ATL_FLAG currently is not a (~n official) CMake variable
    set(CMAKE_ATL_FLAG ${_atl_flag})
    set(CMAKE_MFC_FLAG ${_mfc_flag})
  endif(is_active_)
endmacro(v2c_local_set_cmake_atl_mfc_flags _target _build_platform _build_type _atl_flag _mfc_flag)


# *static* conditional switch between
# old-style include_directories() and new INCLUDE_DIRECTORIES property support.
# FIXME: INCLUDE_DIRECTORIES property does NOT seem to work as expected
# (for a "BEFORE .." expression we'll end up with a nice gcc
# -IBEFORE). This might be due to list var handing issues,
# but possibly INCLUDE_DIRECTORIES prop simply does not support it.
# Should analyze it soon.
_v2c_var_set_empty(_v2c_feat_cmake_include_dirs_prop)
if(_v2c_feat_cmake_include_dirs_prop)
  function(v2c_target_include_directories _target)
    # FIXME: INCLUDE_DIRECTORIES property has a *default*
    # value which consists of parent directories' configuration.
    # We should get rid of that somehow, since we *are* a new project() scope...
    # Possibly we should:
    # 1. clear any pre-existing value
    # 2. remember all added settings in a *new* property variable
    # 3. assign the final combined value in the post-setup function
    set(include_dirs_cfg_ ${ARGN})
    set_property(TARGET ${_target} APPEND PROPERTY INCLUDE_DIRECTORIES ${include_dirs_cfg_})
  endfunction(v2c_target_include_directories _target)
else(_v2c_feat_cmake_include_dirs_prop)
  function(v2c_target_include_directories _target)
    set(include_dirs_cfg_ ${ARGN})
    include_directories(${include_dirs_cfg_})
    #get_property(inc_dirs DIRECTORY PROPERTY INCLUDE_DIRECTORIES)
    #message(FATAL_ERROR "inc_dirs ${inc_dirs}")
  endfunction(v2c_target_include_directories _target)
endif(_v2c_feat_cmake_include_dirs_prop)


if(V2C_WANT_PCH_PRECOMPILED_HEADER_SUPPORT)
  function(_v2c_pch_log_setup_status _target _header_file _pch_mode _dowarn)
    _v2c_bool_get_status_string(V2C_WANT_PCH_PRECOMPILED_HEADER_WARNINGS warnings_status_)
    _v2c_msg_info("v2c_target_add_precompiled_header: configured target ${_target} to *${_pch_mode}* ${_header_file} as PCH (compiler warnings: ${warnings_status_}).")
  endfunction(_v2c_pch_log_setup_status _target _header_file _pch_mode _dowarn)

  # Helper to hook up a precompiled header that might be enabled
  # by a project configuration.
  # See main docs for further details.
  function(v2c_target_add_precompiled_header _target _build_platform _build_type _use _header_file _pch_file)
    v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
    if(NOT is_active_)
      return()
    endif(NOT is_active_)
    if(NOT _use)
      return()
    endif(NOT _use)
    if(NOT TARGET ${_target})
      _v2c_msg_warning("v2c_target_add_precompiled_header: no target ${_target}!? Exit...")
      return()
    endif(NOT TARGET ${_target})
    # Implement non-hard failure
    # (reasoning: the project is compilable anyway, even without pch)
    # in case the file is not valid.
    set(header_file_location_ "${PROJECT_SOURCE_DIR}/${_header_file}")
    # Complicated check! [empty file (--> dir-only) _does_ check as ok]
    if(NOT _header_file OR NOT EXISTS "${header_file_location_}")
      _v2c_msg_warning("v2c_target_add_precompiled_header: header file ${_header_file} at project ${PROJECT_SOURCE_DIR} does not exist!? Skipping PCH...")
      return()
    endif(NOT _header_file OR NOT EXISTS "${header_file_location_}")

    set(_v2c_have_pch_support_ FALSE)

    # This module defines PCH functions such as add_precompiled_header().
    # It _needs_ to be included *after* a project() declaration,
    # which is why it needs to be within this project-target-referencing function.
    if(NOT PCHSupport_FOUND)
      include(V2C_PCHSupport OPTIONAL)
    endif(NOT PCHSupport_FOUND)

    if(PCHSupport_FOUND)
      if(COMMAND add_precompiled_header)
        set(_v2c_have_pch_support_ TRUE)
      endif(COMMAND add_precompiled_header)
    endif(PCHSupport_FOUND)
    if(NOT _v2c_have_pch_support_)
      _v2c_msg_important_once("PCH" "could not figure out precompiled header support - precompiled header support disabled.")
      return()
    endif(NOT _v2c_have_pch_support_)

    # FIXME: should add a target-specific precomp header
    # enable / disable / force-enable flags mechanism,
    # equivalent to what our install() helper does.

    # According to several reports and own experience,
    # ${CMAKE_CURRENT_BINARY_DIR} needs to be available as include directory
    # when adding a precompiled header configuration.
    include_directories(${CMAKE_CURRENT_BINARY_DIR})
    # FIXME: needs investigation whether use/create distinction
    # is being serviced properly by the function that the PCH module file offers.
    # Same values as used by VS7:
    set(pch_not_using_ 0)
    set(pch_create_ 1)
    set(pch_use_ 2)

    set(do_create_ FALSE)
    set(do_use_ FALSE)
    if(_use EQUAL ${pch_create_})
      set(do_create_ TRUE)
    endif(_use EQUAL ${pch_create_})
    if(_use EQUAL ${pch_use_})
      set(do_use_ TRUE)
    endif(_use EQUAL ${pch_use_})
    if(do_use_)
      _v2c_msg_warning("v2c_target_add_precompiled_header: HACK: target ${_target} configured to *Use* a header - modifying into *Create* since our per-file handling is too weak (FIXME).")
      set(do_use_ FALSE)
      set(do_create_ TRUE)
    endif(do_use_)
    _v2c_var_set_empty(do_warn_)
    if(V2C_WANT_PCH_PRECOMPILED_HEADER_WARNINGS)
      set(do_warn_ 1)
    endif(V2C_WANT_PCH_PRECOMPILED_HEADER_WARNINGS)
    if(do_create_)
      add_precompiled_header(${_target} "${header_file_location_}" "${do_warn_}")
      _v2c_pch_log_setup_status(${_target} "${_header_file}" "Create" ${V2C_WANT_PCH_PRECOMPILED_HEADER_WARNINGS})
    endif(do_create_)
    if(do_use_)
      add_precompiled_header_to_target(${_target} "${header_file_location_}" "${_pch_file}" "${do_warn_}")
      _v2c_pch_log_setup_status(${_target} "${_header_file}" "Use" ${V2C_WANT_PCH_PRECOMPILED_HEADER_WARNINGS})
    endif(do_use_)
  endfunction(v2c_target_add_precompiled_header _target _build_platform _build_type _use _header_file _pch_file)
else(V2C_WANT_PCH_PRECOMPILED_HEADER_SUPPORT)
  function(v2c_target_add_precompiled_header _target _build_platform _build_type _use _header_file _pch_file)
    # DUMMY
    _v2c_msg_important("${_target}: not configuring PCH support for header file ${_header_file} (disabled/missing support/...).")
  endfunction(v2c_target_add_precompiled_header _target _build_platform _build_type _use _header_file _pch_file)
endif(V2C_WANT_PCH_PRECOMPILED_HEADER_SUPPORT)

# Creates the upper-case name required for per-configuration
# properties.
# Note: will NOT return content in a result variable,
# but rather update a fixed-named *common* variable used for this purpose.
macro(_v2c_buildcfg_buildtype_determine_upper _build_type)
    # FIXME: for property names, possibly we need to convert
    # space to underscore, too.
    string(TOUPPER "${_build_type}" _v2c_buildcfg_build_type_upper)
endmacro(_v2c_buildcfg_buildtype_determine_upper _build_type)

function(v2c_target_config_charset_set _target _build_platform _build_type _charset)
  v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
  if(NOT is_active_)
    return()
  endif(NOT is_active_)
  # Might perhaps want to have a
  # if(COMMAND user_side_hook)
  # to query for a user-side function which does the target's charset setup,
  # since not all build environments might have a setup
  # where simply adding UNICODE/MBCS defines is sufficient.
  _v2c_var_set_empty(charset_defines_list_)
  # http://blog.m-ri.de/index.php/2007/05/31/_unicode-versus-unicode-und-so-manches-eigentuemliche/
  #   "    "Use Unicode Character Set" setzt beide Defines _UNICODE und UNICODE
  #       "Use Multi-Byte Character Set" setzt nur _MBCS.
  #           "Not set" setzt Erwartungsgemäß keinen der Defines..."
  if("${_charset}" STREQUAL "UNICODE")
    list(APPEND charset_defines_list_ "_UNICODE" "UNICODE")
  elseif("${_charset}" STREQUAL "MBCS")
    list(APPEND charset_defines_list_ "_MBCS")
  else()
    # SBCS (e.g. ASCII, old standard configuration, no defines here)
  endif("${_charset}" STREQUAL "UNICODE")
  if(charset_defines_list_)
    _v2c_buildcfg_buildtype_determine_upper("${_build_type}")
    set_property(TARGET ${_target} APPEND PROPERTY COMPILE_DEFINITIONS_${_v2c_buildcfg_build_type_upper} ${charset_defines_list_})
  endif(charset_defines_list_)
endfunction(v2c_target_config_charset_set _target _build_platform _build_type _charset)


set(v2c_midl_handling_mode_win32 "Win32")
set(v2c_midl_handling_mode_wine "Wine")
set(v2c_midl_handling_mode_stubs "EmulatedStubs")
if(WIN32)
  set(v2c_midl_handling_mode_default_setting ${v2c_midl_handling_mode_win32})
else(WIN32)
  find_program(V2C_WINE_WIDL_BIN widl
    DOC "Path to Wine's MIDL compiler binary (widl)."
  )
  if(V2C_WINE_WIDL_BIN)
    set(v2c_midl_handling_mode_default_setting ${v2c_midl_handling_mode_wine})
    # Use a nice if rather manual trick
    # to figure out the actual prefix that the Wine package
    # (and thus its usually accompanying header files - potentially
    # provided by wine-devel package) is installed at.
    # This path is required by widl to locate e.g. the oaidl.idl,
    # ocidl.idl files that user-side .idl files may include.
    set(wine_widl_standard_sub_prefix_location_ "bin/widl")
    string(REGEX REPLACE "^(.*)/${wine_widl_standard_sub_prefix_location_}$" "\\1" wine_prefix_ "${V2C_WINE_WIDL_BIN}")
    find_path(V2C_WINE_WINDOWS_INCLUDE_DIR "oaidl.idl"
      HINTS "${wine_prefix_}/include/wine/windows"
      DOC "Path to the Windows include header file directory of a Wine installation"
    )
  else(V2C_WINE_WIDL_BIN)
    _v2c_msg_warning("Could not locate an installed Wine widl IDL compiler binary (probably no wine and/or wine-devel package installed) - falling back to dummy IDL handling emulation!")
    set(v2c_midl_handling_mode_default_setting ${v2c_midl_handling_mode_stubs})
  endif(V2C_WINE_WIDL_BIN)
endif(WIN32)
set(v2c_midl_doc_string "The mode to use for handling of IDL files [one of: ${v2c_midl_handling_mode_win32} - uses builtin Win32 MIDL handling / ${v2c_midl_handling_mode_wine} - uses Wine's widl IDL compiler / ${v2c_midl_handling_mode_stubs} - tries to come up with a sufficiently complete emulation stub to at least allow a successful project build [Code Coverage!]]")
set(V2C_MIDL_HANDLING_MODE "${v2c_midl_handling_mode_default_setting}" CACHE STRING "${v2c_midl_doc_string}")

if(V2C_MIDL_HANDLING_MODE STREQUAL ${v2c_midl_handling_mode_win32})
  function(v2c_target_midl_compile _target _build_platform _build_type)
    # DUMMY - WIN32 (Visual Studio) already has its own implicit custom commands for MIDL generation
    # (plus, CMake's Visual Studio generator also already properly passes MIDL-related files to the setup...)
  endfunction(v2c_target_midl_compile _target _build_platform _build_type)
else(V2C_MIDL_HANDLING_MODE STREQUAL ${v2c_midl_handling_mode_win32})

  # Note that these functions make use of some implicitly passed variables.
  function(_v2c_target_midl_create_dummy_header_file _target _header_file_location)
    _v2c_ensure_valid_variables(_header_file_location midl_autogenerated_text_header_ rpc_includes_ c_section_begin_ c_section_end_ midl_lib_name_ midl_iid_)
    set(header_template_ "${CMAKE_CURRENT_BINARY_DIR}/midl_header_${_target}.h.in")
    # FIXME: most certainly this include guard name does not match
    # the one usually used by MIDL compilers.
    set(midl_header_include_guard_ "MIDL_STUB_${midl_lib_name_}")
    set(header_content_
"${midl_autogenerated_text_header_}
\#ifndef ${midl_header_include_guard_}
\#define ${midl_header_include_guard_}

${rpc_includes_}

${c_section_begin_}

DEFINE_GUID(LIBID_${midl_lib_name_}, ${midl_iid_});

${c_section_end_}

\#endif /* ${midl_header_include_guard_} */")
    _v2c_create_build_decoupled_adhoc_file("${header_template_}" "${_header_file_location}" "${header_content_}")
  endfunction(_v2c_target_midl_create_dummy_header_file _target _header_file_location)
  function(_v2c_target_midl_create_dummy_iid_file _target _iid_file)
    _v2c_ensure_valid_variables(_iid_file midl_autogenerated_text_header_ rpc_includes_ c_section_begin_ c_section_end_ midl_lib_name_ midl_iid_)
    set(iidfile_template_ "${CMAKE_CURRENT_BINARY_DIR}/midl_iidfile_${_target}_i.c.in")
    set(iidfile_content_
"${midl_autogenerated_text_header_}

${c_section_begin_}

${rpc_includes_}

\#ifndef __IID_DEFINED__
\#define __IID_DEFINED__

typedef struct _IID
{
    unsigned long x;
    unsigned short s1;
    unsigned short s2;
    unsigned char  c[8];
} IID;

\#endif // __IID_DEFINED__

\#ifndef CLSID_DEFINED
\#define CLSID_DEFINED
typedef IID CLSID;
\#endif // CLSID_DEFINED


\#define MIDL_DEFINE_GUID(type,name,l,w1,w2,b1,b2,b3,b4,b5,b6,b7,b8) \\
  const type name = {l,w1,w2,{b1,b2,b3,b4,b5,b6,b7,b8}}

MIDL_DEFINE_GUID(IID, LIBID_${midl_lib_name_}, ${midl_iid_});

\#undef MIDL_DEFINE_GUID

${c_section_end_}

"
    )
    set(comment_ "${_target}: creating dummy MIDL interface identifier file ${_iid_file} - objective is to merely achieve a successful build of a however quite undeployable project [Code Coverage!]")
    _v2c_msg_warning("${comment_}")
    # TODO: some of that processing should probably be moved build-time,
    # by creating a template here and then invoking a cmake -P custom
    # command creating the required OUTPUT.
    _v2c_create_build_decoupled_adhoc_file("${iidfile_template_}" "${_iid_file}" "${iidfile_content_}")
  endfunction(_v2c_target_midl_create_dummy_iid_file _target _iid_file)
  function(v2c_target_midl_compile _target _build_platform _build_type)
    v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
    if(NOT is_active_)
      return()
    endif(NOT is_active_)

    set(options VALIDATE_ALL_PARAMETERS)
    set(oneValueArgs TARGET_ENVIRONMENT IDL_FILE_NAME HEADER_FILE_NAME INTERFACE_IDENTIFIER_FILE_NAME PROXY_FILE_NAME TYPE_LIBRARY_NAME DLL_DATA_FILE_NAME)
    cmake_parse_arguments(v2c_target_midl_compile "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    _v2c_fs_item_make_relative_to_path("${v2c_target_midl_compile_IDL_FILE_NAME}" "${PROJECT_SOURCE_DIR}" idl_file_location_)
    if(NOT EXISTS "${idl_file_location_}")
      _v2c_msg_warning("IDL file ${idl_file_location_} not found - bailing out...")
      return()
    endif(NOT EXISTS "${idl_file_location_}")
    # Hrmpf, unfortunately this *generated* item is relative to project
    # *source* dir. Eventually we might want to offer a config option to
    # relocate such things to a build tree directory.
    # However this would require implicitly adding this directory
    # to a project's default include path.
    _v2c_fs_item_make_relative_to_path("${v2c_target_midl_compile_HEADER_FILE_NAME}" "${PROJECT_SOURCE_DIR}" header_file_location_)
    if(V2C_MIDL_HANDLING_MODE STREQUAL ${v2c_midl_handling_mode_wine})
      set(cmd_list_ "${V2C_WINE_WIDL_BIN}")
      _v2c_var_set_empty(v2c_widl_outputs_)
      if(header_file_location_)
	list(APPEND cmd_list_ "-h" "-H${header_file_location_}")
	list(APPEND v2c_widl_outputs_ "${header_file_location_}")
      endif(header_file_location_)
      if(EXISTS "${V2C_WINE_WINDOWS_INCLUDE_DIR}")
        list(APPEND cmd_list_ "-I" "${V2C_WINE_WINDOWS_INCLUDE_DIR}")
      else(EXISTS "${V2C_WINE_WINDOWS_INCLUDE_DIR}")
        _v2c_msg_warning("Path to Wine's Windows headers (${V2C_WINE_WINDOWS_INCLUDE_DIR}) does not exist - expect MIDL compiler build-time trouble!")
      endif(EXISTS "${V2C_WINE_WINDOWS_INCLUDE_DIR}")
      if(v2c_target_midl_compile_INTERFACE_IDENTIFIER_FILE_NAME)
        # Despite VS probably actually generating into source tree,
	# we'll use binary dir anyway since for our build
	# we definitely want to avoid fumbling the source tree
	# (TODO make this user-configurable!).
        _v2c_fs_item_make_relative_to_path("${v2c_target_midl_compile_INTERFACE_IDENTIFIER_FILE_NAME}" "${PROJECT_BINARY_DIR}" iid_file_location_)
        list(APPEND cmd_list_ "-u" "-U${iid_file_location_}")
	list(APPEND v2c_widl_outputs_ "${iid_file_location_}")
      endif(v2c_target_midl_compile_INTERFACE_IDENTIFIER_FILE_NAME)
      if(v2c_target_midl_compile_TYPE_LIBRARY_NAME)
        list(APPEND cmd_list_ "-t" "-T${v2c_target_midl_compile_TYPE_LIBRARY_NAME}")
	# Hmm, it appears that (at least certain older versions of) widl
	# does NOT generate .tlb files, thus don't add it to output list
	# since otherwise the target would keep trying to build the ghost file.
	#list(APPEND v2c_widl_outputs_ "${v2c_target_midl_compile_TYPE_LIBRARY_NAME}")
      endif(v2c_target_midl_compile_TYPE_LIBRARY_NAME)
      if(v2c_target_midl_compile_PROXY_FILE_NAME)
        list(APPEND cmd_list_ "-p" "-P${v2c_target_midl_compile_PROXY_FILE_NAME}")
	list(APPEND v2c_widl_outputs_ "${v2c_target_midl_compile_PROXY_FILE_NAME}")
      endif(v2c_target_midl_compile_PROXY_FILE_NAME)
      if(v2c_target_midl_compile_DLL_DATA_FILE_NAME)
        list(APPEND cmd_list_ "--dlldata=${v2c_target_midl_compile_DLL_DATA_FILE_NAME}")
      endif(v2c_target_midl_compile_DLL_DATA_FILE_NAME)
      if(v2c_target_midl_compile_VALIDATE_ALL_PARAMETERS)
        # Not sure at all whether v2c_target_midl_compile_VALIDATE_ALL_PARAMETERS is even
	# related to "enable pedantic warnings"...
        list(APPEND cmd_list_ "-W")
      endif(v2c_target_midl_compile_VALIDATE_ALL_PARAMETERS)
      if(v2c_target_midl_compile_TARGET_ENVIRONMENT)
        if(v2c_target_midl_compile_TARGET_ENVIRONMENT STREQUAL "Win32")
          list(APPEND cmd_list_ "--win32")
        endif(v2c_target_midl_compile_TARGET_ENVIRONMENT STREQUAL "Win32")
	# Note that we don't support "Itanium" here yet.
        if(v2c_target_midl_compile_TARGET_ENVIRONMENT STREQUAL "X64")
          list(APPEND cmd_list_ "--win64")
        endif(v2c_target_midl_compile_TARGET_ENVIRONMENT STREQUAL "X64")
      endif(v2c_target_midl_compile_TARGET_ENVIRONMENT)
      list(APPEND cmd_list_ "${idl_file_location_}")
      _v2c_msg_info("${_target}: ${v2c_widl_descr_} (command line: ${cmd_list_}, output: ${v2c_widl_outputs_}, depends: ${v2c_widl_depends_}).")
      if(v2c_widl_outputs_)
        set(v2c_widl_descr_ "${_target} (${_build_platform} ${_build_type}): using Wine's ${V2C_WINE_WIDL_BIN} to compile IDL data files (${v2c_widl_outputs_})")
        add_custom_command(OUTPUT ${v2c_widl_outputs_}
          COMMAND ${cmd_list_}
          DEPENDS ${v2c_widl_depends_}
          COMMENT "${v2c_widl_descr_}"
        )
        add_custom_target(${_target}_midl_compile DEPENDS ${v2c_widl_outputs_})
        add_dependencies(${_target} ${_target}_midl_compile)
      else(v2c_widl_outputs_)
        _v2c_msg_warning("${_target}: MIDL implementation problem - no outputs!? Bailing out...")
      endif(v2c_widl_outputs_)
    else(V2C_MIDL_HANDLING_MODE STREQUAL ${v2c_midl_handling_mode_wine})
      # The last-ditch fallback else branch selects the emulated stubs mode
      # (reason: this mode is always supportable everywhere)

      # For now, all we care about is creating some dummy files to make a target actually build
      # rather than aborting CMake configuration due to missing source files...
      # This allows us to keep this project within the active set of
      # projects, thereby increasing the amount of compiled/error-checked code
      # (Code Coverage!).

      # TODO: query all the other MIDL-related target properties
      # which possibly were configured prior to invoking this function.

      set(midl_lib_name_ "${_target}Lib")
      # Awful dummy IID, to at least try to make Typelib projects build (increase Code Coverage!)
      set(midl_iid_ "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0")
      set(midl_autogenerated_text_header_ "/*** Autogenerated by vcproj2cmake - Do not edit. ***/")
      set(rpc_includes_
"\#include <rpc.h>
\#include <rpcndr.h>")
      set(c_section_begin_
"\#ifdef __cplusplus
extern \"C\" {
\#endif
")

      set(c_section_end_
"\#ifdef __cplusplus
}
\#endif
")
      if(header_file_location_)
	_v2c_target_midl_create_dummy_header_file(${_target} "${header_file_location_}")
      endif(header_file_location_)
      if(v2c_target_midl_compile_INTERFACE_IDENTIFIER_FILE_NAME)
        _v2c_target_midl_create_dummy_iid_file(${_target} "${v2c_target_midl_compile_INTERFACE_IDENTIFIER_FILE_NAME}")
      endif(v2c_target_midl_compile_INTERFACE_IDENTIFIER_FILE_NAME)
    endif(V2C_MIDL_HANDLING_MODE STREQUAL ${v2c_midl_handling_mode_wine})
  endfunction(v2c_target_midl_compile _target _build_platform _build_type)
endif(V2C_MIDL_HANDLING_MODE STREQUAL ${v2c_midl_handling_mode_win32})

function(v2c_target_pdb_configure _target _build_platform _build_type)
  v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
  if(is_active_)
    _v2c_var_set_empty(options)
    set(oneValueArgs PDB_OUTPUT_DIRECTORY PDB_NAME)
    cmake_parse_arguments(v2c_target_pdb_configure "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # These target properties are said to be CMake >= 2.8.10 only.
    # No version check added here since setting them in vain
    # at least doesn't hurt.
    _v2c_buildcfg_buildtype_determine_upper("${_build_type}")
    if(v2c_target_pdb_configure_PDB_NAME)
      set_property(TARGET ${_target} PROPERTY PDB_NAME_${_v2c_buildcfg_build_type_upper} "${v2c_target_pdb_configure_PDB_NAME}")
    endif(v2c_target_pdb_configure_PDB_NAME)
    if(v2c_target_pdb_configure_PDB_OUTPUT_DIRECTORY)
      # AFAICT as of CMake master 20121120
      # CMake source, while *setting* PDB_OUTPUT_DIRECTORY defaults,
      # does NOT actually *get* a custom one. Doh.
      set_property(TARGET ${_target} PROPERTY PDB_OUTPUT_DIRECTORY_${_v2c_buildcfg_build_type_upper} ${_pdb_output_dir})
    endif(_pdb_output_dir)
  endif(is_active_)
endfunction(v2c_target_pdb_configure _target _build_platform _build_type)


# This function will set up target properties gathered from
# Visual Studio Source Control Management (SCM) elements.
if(V2C_WANT_SCC_SOURCE_CONTROL_IDE_INTEGRATION)
  function(v2c_target_set_properties_vs_scc _target _vs_scc_projectname _vs_scc_localpath _vs_scc_provider _vs_scc_auxpath)
    #_v2c_msg_info(
    #  "v2c_target_set_properties_vs_scc: target ${_target}"
    #  "VS_SCC_PROJECTNAME ${_vs_scc_projectname} VS_SCC_LOCALPATH ${_vs_scc_localpath}\n"
    #  "VS_SCC_PROVIDER ${_vs_scc_provider}"
    #)
    # WARNING NOTE: the previous implementation called set_target_properties()
    # with a strung-together list of properties, as an optimization.
    # However since certain input property string payload consisted of semicolons
    # (e.g. in the case of "&quot;"), this went completely haywire
    # with contents partially split off at semicolon borders.
    # IOW, definitely make sure to set each property precisely separately.
    # Well, that's not sufficient! The remaining problem was that the property
    # variables SHOULD NOT BE QUOTED, to enable passing of the content as a list,
    # thereby implicitly properly passing the original ';' content right to
    # the generated .vcproj, in fully correct form!
    # Perhaps the previous set_target_properties() code was actually doable after all... (TODO test?)
    if(_vs_scc_projectname)
      set_property(TARGET ${_target} PROPERTY VS_SCC_PROJECTNAME ${_vs_scc_projectname})
      if(_vs_scc_localpath)
        #if("${_vs_scc_localpath}" STREQUAL ".")
        #      set(_vs_scc_localpath "SAK")
        #endif("${_vs_scc_localpath}" STREQUAL ".")
        set_property(TARGET ${_target} PROPERTY VS_SCC_LOCALPATH ${_vs_scc_localpath})
      endif(_vs_scc_localpath)
      if(_vs_scc_provider)
        set_property(TARGET ${_target} PROPERTY VS_SCC_PROVIDER ${_vs_scc_provider})
      endif(_vs_scc_provider)
      if(_vs_scc_auxpath)
        set_property(TARGET ${_target} PROPERTY VS_SCC_AUXPATH ${_vs_scc_auxpath})
      endif(_vs_scc_auxpath)
    endif(_vs_scc_projectname)
  endfunction(v2c_target_set_properties_vs_scc _target _vs_scc_projectname _vs_scc_localpath _vs_scc_provider _vs_scc_auxpath)
else(V2C_WANT_SCC_SOURCE_CONTROL_IDE_INTEGRATION)
  function(v2c_target_set_properties_vs_scc _target _vs_scc_projectname _vs_scc_localpath _vs_scc_provider _vs_scc_auxpath)
    # DUMMY
  endfunction(v2c_target_set_properties_vs_scc _target _vs_scc_projectname _vs_scc_localpath _vs_scc_provider _vs_scc_auxpath)
endif(V2C_WANT_SCC_SOURCE_CONTROL_IDE_INTEGRATION)


if(NOT V2C_INSTALL_ENABLE)
  if(NOT V2C_INSTALL_ENABLE_SILENCE_WARNING)
    # You should make sure to provide install() handling
    # which is explicitly per-target
    # (by using our vcproj2cmake helper functions, or externally taking
    # care of per-target install() handling) - it is very important
    # to _explicitly_ install any targets we create in converted vcproj2cmake files,
    # and _not_ simply "copy-install" entire library directories,
    # since that would cause some target-specific CMake install handling
    # to get lost (e.g. CMAKE_INSTALL_RPATH tweaking will be done in case of
    # proper target-specific install() only!)
    #
    # V2C_INSTALL_ENABLE ideally is a variable that's being set *outside*
    # of all inner (V2C-side) scope layers, i.e. you've got a CMake-enabled
    # source tree which has a root which defines the configuration basis
    # (basic environment checks, user-side cache variables, V2C settings, ...)
    # and *then* includes the entire V2C-converted hierarchy as a sub part.
    # http://stackoverflow.com/questions/3766740/overriding-a-default-option-value-in-cmake-from-a-parent-cmakelists-txt might be helpful.
    _v2c_msg_warning("${CMAKE_CURRENT_LIST_FILE}: vcproj2cmake-supplied install handling not activated - targets _need_ to be installed properly one way or another!")
  endif(NOT V2C_INSTALL_ENABLE_SILENCE_WARNING)
endif(NOT V2C_INSTALL_ENABLE)

# Helper to cleanly evaluate target-specific setting or, failing that,
# whether target is mentioned in a global list.
# Example: V2C_INSTALL_ENABLE_${_target}, or
#          V2C_INSTALL_ENABLE_TARGETS_LIST contains ${_target}
function(_v2c_target_install_get_flag__helper _target _var_prefix _result_out)
  set(flag_result_ false)
  if(${_var_prefix}_${_target})
    set(flag_result_ true)
  else(${_var_prefix}_${_target})
    _v2c_list_check_item_contained_exact("${_target}" "${${_var_prefix}_TARGETS_LIST}" flag_result_)
  endif(${_var_prefix}_${_target})
  set(${_result_out} ${flag_result_} PARENT_SCOPE)
endfunction(_v2c_target_install_get_flag__helper _target _var_prefix _result_out)


# Determines whether a specific target is allowed to be installed.
function(_v2c_target_install_is_enabled__helper _target _install_enabled_out)
  set(install_enabled_ false)
  # v2c-based installation globally enabled?
  if(V2C_INSTALL_ENABLE)
    # First, adopt all-targets setting, then, in case all-targets setting was false,
    # check whether specific setting is enabled.
    # Finally, if we think we're allowed to install it,
    # make sure to check a skip flag _last_, to veto the operation.
    set(install_enabled_ ${V2C_INSTALL_ENABLE_ALL_TARGETS})
    if(NOT install_enabled_)
      _v2c_target_install_get_flag__helper(${_target} "V2C_INSTALL_ENABLE" install_enabled_)
    endif(NOT install_enabled_)
    if(install_enabled_)
      _v2c_target_install_get_flag__helper(${_target} "V2C_INSTALL_SKIP" v2c_install_skip_)
      if(v2c_install_skip_)
        set(install_enabled_ false)
      endif(v2c_install_skip_)
    endif(install_enabled_)
    if(NOT install_enabled_)
      _v2c_msg_important("v2c_target_install: asked to skip install of target ${_target}")
    endif(NOT install_enabled_)
  endif(V2C_INSTALL_ENABLE)
  set(${_install_enabled_out} ${install_enabled_} PARENT_SCOPE)
endfunction(_v2c_target_install_is_enabled__helper _target _install_enabled_out)

# This is the main pretty flexible install() helper function,
# as used by all vcproj2cmake-generated CMakeLists.txt.
# It is designed to provide very flexible handling of externally
# specified configuration data (global settings, or specific to each
# target).
# Within the generated CMakeLists.txt file, it is supposed to have a
# simple invocation of this function, with default behaviour here to be as
# simple/useful as possible.
# USAGE: at a minimum, you should start by enabling V2C_INSTALL_ENABLE and
# specifying a globally valid V2C_INSTALL_DESTINATION setting
# (or V2C_INSTALL_DESTINATION_EXECUTABLE and V2C_INSTALL_DESTINATION_SHARED_LIBRARY)
# at a more higher-level "configure all of my contained projects" place.
# Ideally, this is done by creating user-interface-visible/configurable
# cache variables (somewhere in your toplevel project root configuration parts)
# to hold your destination directories for libraries and executables,
# then passing down these custom settings into V2C_INSTALL_DESTINATION_* variables.
function(v2c_target_install _target)
  if(NOT TARGET ${_target})
    _v2c_msg_important("${_target} not a valid target!?")
    return()
  endif(NOT TARGET ${_target})

  # Do external configuration variables indicate
  # that we're allowed to install this target?
  _v2c_target_install_is_enabled__helper(${_target} install_enabled_)
  if(NOT install_enabled_)
    return() # bummer...
  endif(NOT install_enabled_)

  # Since install() commands are (probably rightfully) very picky
  # about incomplete/incorrect parameters, we actually need to conditionally
  # compile a list of parameters to actually feed into it.
  #
  #_v2c_var_set_empty(install_params_values_list_) # no need to unset (function scope!)

  list(APPEND install_params_values_list_ TARGETS ${_target})
  # Internal variable - lists the parameter types
  # which an install() command supports. Elements are upper-case!!
  set(install_param_list_ EXPORT DESTINATION PERMISSIONS CONFIGURATIONS COMPONENT)
  foreach(install_param_ ${install_param_list_})
    _v2c_var_set_empty(install_param_value_)

    # First, query availability of target-specific settings,
    # then query availability of common settings.
    if(V2C_INSTALL_${install_param_}_${_target})
      set(install_param_value_ "${V2C_INSTALL_${install_param_}_${_target}}")
    else(V2C_INSTALL_${install_param_}_${_target})

      # Unfortunately, DESTINATION param needs some extra handling
      # (want to support per-target-type destinations):
      if(install_param_ STREQUAL DESTINATION)
        # result is one of STATIC_LIBRARY, MODULE_LIBRARY, SHARED_LIBRARY, EXECUTABLE
        get_property(target_type_ TARGET ${_target} PROPERTY TYPE)
        #message("target ${_target} type ${target_type_}")
        if(V2C_INSTALL_${install_param_}_${target_type_})
          set(install_param_value_ "${V2C_INSTALL_${install_param_}_${target_type_}}")
        endif(V2C_INSTALL_${install_param_}_${target_type_})
      endif(install_param_ STREQUAL DESTINATION)

      if(NOT install_param_value_)
        # Adopt global setting if specified:
        if(V2C_INSTALL_${install_param_})
          set(install_param_value_ "${V2C_INSTALL_${install_param_}}")
        endif(V2C_INSTALL_${install_param_})
      endif(NOT install_param_value_)
    endif(V2C_INSTALL_${install_param_}_${_target})
    if(install_param_value_)
      list(APPEND install_params_values_list_ ${install_param_} "${install_param_value_}")
    else(install_param_value_)
      # install_param_value_ unset? bail out in case of mandatory parameters (DESTINATION)
      if(install_param_ STREQUAL DESTINATION)
        _v2c_msg_fatal_error("Variable V2C_INSTALL_${install_param_}_${_target} or V2C_INSTALL_${install_param_} not specified!")
      endif(install_param_ STREQUAL DESTINATION)
    endif(install_param_value_)
  endforeach(install_param_ ${install_param_list_})

  _v2c_msg_info("v2c_target_install: install(${install_params_values_list_})")
  install(${install_params_values_list_})
endfunction(v2c_target_install _target)

# The all-in-one helper method for post setup steps
# (install handling, VS properties, CMakeLists.txt rebuilder, ...).
function(v2c_target_post_setup _target _project_label _vs_keyword)
  if(TARGET ${_target})
    v2c_target_install(${_target})

    # Make sure to keep CMake Name/Keyword (PROJECT_LABEL / VS_KEYWORD properties) in our converted file, too...
    # Hrmm, both project() _and_ PROJECT_LABEL reference the same project_name?? WEIRD.
    set_property(TARGET ${_target} PROPERTY PROJECT_LABEL "${_project_label}")
    if(NOT _vs_keyword STREQUAL V2C_NOT_PROVIDED)
      # I don't know WTH the difference between VS_KEYWORD and VS_GLOBAL_KEYWORD
      # would be - neither any public patch mail nor their docs is meaningful
      # (git blame seems to suggest that it was pure duplication - ouch).
      # http://public.kitware.com/Bug/view.php?id=12586
      # Thus let's just set both to the very same thing, to not miss out
      # on the Keyword element in the VS10 (vs. VS7) case.
      set_property(TARGET ${_target} PROPERTY VS_KEYWORD "${_vs_keyword}")
      set_property(TARGET ${_target} PROPERTY VS_GLOBAL_KEYWORD "${_vs_keyword}")
    endif(NOT _vs_keyword STREQUAL V2C_NOT_PROVIDED)
    # DEBUG/LOG helper - enable to verify correct transfer of target properties etc.:
    #_v2c_target_log_configuration(${_target})
  endif(TARGET ${_target})
endfunction(v2c_target_post_setup _target _project_label _vs_keyword)

# Unfortunately there's no CMake DIRECTORY property to list all
# project()s defined within a dir, thus we have to keep track of
# this information on our own. OTOH we wouldn't be able to discern
# V2C-side project()s from non-V2C ones anyway...
function(_v2c_directory_get_projects_list _projects_list_out)
  get_property(directory_projects_list_ DIRECTORY PROPERTY V2C_PROJECTS_LIST)
  set(${_projects_list_out} "${directory_projects_list_}" PARENT_SCOPE)
endfunction(_v2c_directory_get_projects_list _projects_list_out)

function(_v2c_directory_register_project _target)
  _v2c_directory_get_projects_list(projects_list_)
  list(APPEND projects_list_ ${_target})
  set_property(DIRECTORY PROPERTY V2C_PROJECTS_LIST "${projects_list_}")
  #_v2c_directory_get_projects_list(projects_list_)
  #message("projects list now: ${projects_list_}")
endfunction(_v2c_directory_register_project _target)

# This function enhances a list var in each CMakeLists.txt (e.g. a per-DIRECTORY property)
# mentioning the projects that this file contains,
# to be passed to the final directory-global
# vcproj2cmake.rb converter rebuilder invocation.
function(v2c_project_post_setup _project _orig_proj_files_list)
  _v2c_directory_register_project(${_project})
  _v2c_var_set_empty(orig_proj_files_w_source_dir_list_)
  _v2c_list_create_prefix_suffix_expanded_version("${_orig_proj_files_list}" "${CMAKE_CURRENT_SOURCE_DIR}/" "" orig_proj_files_w_source_dir_list_)
  # Some projects are header-only and thus don't add an actual target
  # where our target-related properties could be set at,
  # thus we unfortunately need to resort to hooking these things
  # to a DIRECTORY property instead...
  set_property(DIRECTORY PROPERTY V2C_PROJECT_${_project}_ORIG_PROJ_FILES_LIST "${orig_proj_files_w_source_dir_list_}")
  # Better make sure to include a hook _after_ all other local preparations
  # are already available.
  v2c_hook_invoke("${V2C_HOOK_POST}")
endfunction(v2c_project_post_setup _project _orig_proj_files_list)

function(v2c_directory_post_setup)
  _v2c_directory_get_projects_list(directory_projects_list_)
  _v2c_ensure_valid_variables(directory_projects_list_)
  foreach(proj_ ${directory_projects_list_})
    # Implement this to be a _list_ variable of possibly multiple
    # original converted-from files (.vcproj or .vcxproj or some such).
    get_property(orig_proj_files_list_ DIRECTORY PROPERTY V2C_PROJECT_${proj_}_ORIG_PROJ_FILES_LIST)
    list(APPEND dir_orig_proj_files_list_ ${orig_proj_files_list_})
  endforeach(proj_ ${directory_projects_list_})
  # Implementation note: the last argument to
  # _v2c_project_rebuild_on_update() should be as much of a 1:1 passthrough of
  # the input argument to the CMakeLists.txt converter ruby script execution as possible/suitable,
  # since invocation arguments of this script on rebuild should be (roughly) identical.
  _v2c_project_rebuild_on_update("${directory_projects_list_}" "${dir_orig_proj_files_list_}" "${CMAKE_CURRENT_LIST_FILE}" "${V2C_SCRIPT_LOCATION}" "${V2C_MASTER_PROJECT_SOURCE_DIR}")
  v2c_hook_invoke("${V2C_HOOK_DIRECTORY_POST}")
endfunction(v2c_directory_post_setup)
