# This file is part of the vcproj2cmake build converter (vcproj2cmake.sf.net)

# Some helper functions to be used by all converted projects in the tree

# This vcproj2cmake-specific CMake module should be installed
# at least to your root project (i.e., PROJECT/cmake/Modules/,
# an additionally configured local CMake module path).
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
# - prefer _upper-case_ V2C prefix for _cache variables_ such as V2C_RUBY_BIN,
#   to ensure that they're all sorted under The One True upper-case "V2C" prefix
#   in "grouped view" mode of CMake GUI

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



# First, include main file (to be customized by user as needed),
# to have important vcproj2cmake configuration settings
# re-defined per each new vcproj-converted project.
include(vcproj2cmake_defs)


# Avoid useless repeated parsing of static-data function definitions
if(V2C_FUNC_DEFINED)
  return()
endif(V2C_FUNC_DEFINED)
set(V2C_FUNC_DEFINED true)


# Sanitize CMAKE_BUILD_TYPE setting:
if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
  # Hohumm - need to actively preserve the cache variable documentation string
  # when doing CACHE FORCE... :-\
  # DOES NOT WORK - docs will only be available for _defined_ variables,
  # thus neither FULL_DOCS nor BRIEF_DOCS return anything other than
  # NOTFOUND. Hrmm.
  #get_property(cmake_build_type_full_docs CACHE PROPERTY CMAKE_BUILD_TYPE FULL_DOCS)
  # Oh well... try to adopt a sufficiently original string:
  set(cmake_build_type_full_docs "Choose the type of build, options are: None(CMAKE_CXX_FLAGS or CMAKE_C_FLAGS used) Debug Release RelWithDebInfo MinSizeRel Maintainer.")
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "${cmake_build_type_full_docs}" FORCE)
  # Side note: this message may appear during _initial_ configuration run
  # (MSVS 2005 generator). I suppose that this is perfectly ok,
  # since CMake probably still needs to make up its mind as to which
  # configuration types (MinSizeRel, Debug etc.) are available.
  message("WARNING: CMAKE_BUILD_TYPE was not specified - defaulting to ${CMAKE_BUILD_TYPE} setting!")
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


if(NOT V2C_STAMP_FILES_SUBDIR)
  set(V2C_STAMP_FILES_SUBDIR "stamps")
endif(NOT V2C_STAMP_FILES_SUBDIR)
# Enable customization (via cache entry), someone might need it.
set(V2C_STAMP_FILES_DIR "${CMAKE_BINARY_DIR}/${v2c_global_config_subdir_my}/${V2C_STAMP_FILES_SUBDIR}" CACHE PATH "The directory to place any stamp files used by vcproj2cmake in.")
mark_as_advanced(V2C_STAMP_FILES_DIR)
file(MAKE_DIRECTORY "${V2C_STAMP_FILES_DIR}")


# # # # #   COMMON HELPER FUNCTIONS   # # # # #

function(_v2c_fatal_error_please_report _msg)
  message(FATAL_ERROR "${_msg} - please report!")
endfunction(_v2c_fatal_error_please_report _msg)

# Helper to yell loudly in case of unset variables.
# The input string should _not_ be the dereferenced form,
# but rather a simple _name_ of the variable.
function(_v2c_ensure_valid_variables _var_names_list)
  foreach(var_name_ ${_var_names_list})
    if(NOT ${var_name_})
      message(FATAL_ERROR "important vcproj2cmake variable ${var_name_} not valid/available!?")
    endif(NOT ${var_name_})
  endforeach(var_name_ ${_var_names_list})
endfunction(_v2c_ensure_valid_variables _var_names_list)

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
    message(FATAL_ERROR "_v2c_config_get: config var ${_cfg_key} not set!?")
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
    message("WARNING: v2c_buildcfg_check_if_platform_buildtype_active: empty platform [${_build_platform}] or build type [${_build_type}]!?")
  endif(_build_platform AND _build_type)
  _v2c_flatten_name("${_build_platform}" build_platform_flattened_)
  _v2c_flatten_name("${_build_type}" build_type_flattened_)
  set(${_var_name_out} v2c_want_buildcfg_platform_${build_platform_flattened_}_build_type_${build_type_flattened_} PARENT_SCOPE)
endfunction(_v2c_buildcfg_get_magic_conditional_name _target _build_platform _build_type _var_name_out)

if(CMAKE_CONFIGURATION_TYPES)
  function(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
    if(V2C_BUILD_PLATFORM STREQUAL "${_build_platform}")
      set(val_ TRUE)
    endif(V2C_BUILD_PLATFORM STREQUAL "${_build_platform}")
    set(${_var_out} ${val_} PARENT_SCOPE)
  endfunction(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
else(CMAKE_CONFIGURATION_TYPES)
  function(_v2c_buildcfg_define_magic_conditional _target _build_platform _build_type _var_out)
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
      message("FIXME: CMAKE_SIZEOF_VOID_P not available - currently assuming 32bit!")
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
      _v2c_fatal_error_please_report("detected final failure to figure out a build platform setting (choices: [${_platform_names_list}])")
    endif(NOT platform_default_)
    if(NOT platform_reason_)
      _v2c_fatal_error_please_report("No reason for platform selection given")
    endif(NOT platform_reason_)
    set(${_platform_default_out} "${platform_default_}" PARENT_SCOPE)
    set(${_platform_reason_out} "${platform_reason_}" PARENT_SCOPE)
  endfunction(_v2c_platform_determine_default _platform_names_list _platform_default_out _platform_reason_out)

  function(_v2c_buildcfg_determine_platform_var _target)
    _v2c_project_platform_get_list(${_target} platform_names_list_)
    if(NOT V2C_BUILD_PLATFORM) # avoid rerun
      _v2c_platform_determine_default("${platform_names_list_}" platform_default_setting_ platform_reason_)
      set(platform_doc_string_ "The TARGET (not necessarily identical to HOST!) platform to build for [possible values: [${platform_names_list_}]]")
      # Offer the main configuration cache variable to the user:
      set(V2C_BUILD_PLATFORM "${platform_default_setting_}" CACHE STRING ${platform_doc_string_})
    else(NOT V2C_BUILD_PLATFORM)
      # Hmm... preserving the reason variable content is a bit difficult
      # in light of V2C_BUILD_PLATFORM being a CACHE variable
      # (unless we make this CACHE as well).
      # Thus simply pretend it to be user-selected whenever it's read from cache.
      set(platform_reason_ "user-selected entry")
    endif(NOT V2C_BUILD_PLATFORM)
    _v2c_list_check_item_contained_exact("${V2C_BUILD_PLATFORM}" "${platform_names_list_}" platform_ok_)
    if(platform_ok_)
      # FIXME: should provide a variable to do first-time-only printing of
      # this setting. Possibly could even devise a common reusable mechanism for
      # all kinds of first-time-only printings...
      message("vcproj2cmake chose to adopt the following project-defined build platform setting: ${V2C_BUILD_PLATFORM} (reason: ${platform_reason_}).")
    else(platform_ok_)
      message(FATAL_ERROR "V2C_BUILD_PLATFORM contains invalid build platform setting (${V2C_BUILD_PLATFORM}), please correct!")
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

  # Have an update_cmakelists_ALL convenience target
  # to be able to update _all_ outdated CMakeLists.txt files within a project hierarchy
  # Providing _this_ particular target (as a dummy) is _always_ needed,
  # even if the rebuild mechanism cannot be provided (missing script, etc.).
  if(NOT TARGET update_cmakelists_ALL)
    add_custom_target(update_cmakelists_ALL)
  endif(NOT TARGET update_cmakelists_ALL)

  if(NOT V2C_RUBY_BIN) # avoid repeated checks (see cmake --trace)
    find_program(V2C_RUBY_BIN NAMES ruby)
    if(NOT V2C_RUBY_BIN)
      message("could not detect your ruby installation (perhaps forgot to set CMAKE_PREFIX_PATH?), aborting: won't automagically rebuild CMakeLists.txt on changes...")
      return()
    endif(NOT V2C_RUBY_BIN)
  endif(NOT V2C_RUBY_BIN)

  set(cmakelists_rebuilder_deps_static_list_
    ${root_mappings_files_list_}
    "${project_exclude_list_file_location_}"
    "${V2C_RUBY_BIN}"
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
      # WARNING: make sure to fetch a full path, since otherwise we'd
      # end up with a simple "false" which is highly conflict-prone
      # with CMake's "false" boolean value!!
      find_program(V2C_ABORT_BIN false)
      _v2c_ensure_valid_variables(V2C_ABORT_BIN)
      _v2c_config_set(abort_BIN_v1 "${V2C_ABORT_BIN}")
    else(UNIX)
      _v2c_config_set(abort_BIN_v1 v2c_invoked_non_existing_command_simply_to_force_build_abort)
    endif(UNIX)
    # Provide a marker file, to enable external build invokers
    # to determine whether a (supposedly entire) build
    # was aborted due to CMakeLists.txt conversion and thus they
    # should immediately resume with a new build...
    _v2c_config_set(cmakelists_update_check_did_abort_public_marker_file_v1 "${V2C_STAMP_FILES_DIR}/v2c_cmakelists_update_check_did_abort.marker")
    # This is the stamp file for the subsequent "cleanup" target
    # (oh yay, we even need to have the marker file removed on next build launch again).
    _v2c_config_set(update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1 "${V2C_STAMP_FILES_DIR}/v2c_cmakelists_update_abort_cleanup_done.stamp")
  endif(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)
endfunction(_v2c_config_do_setup_rebuilder)

function(_v2c_config_do_setup)
  # FIXME: should obey V2C_LOCAL_CONFIG_DIR setting!! Nope, this is a
  # reference to the _global_ one here... Hmm, is there a config variable for
  # that? At least set a local variable here for now.
  set(global_config_subdir_ "cmake/vcproj2cmake")

  set(project_exclude_list_file_location_ "${CMAKE_SOURCE_DIR}/${global_config_subdir_}/project_exclude_list.txt")
  _v2c_config_set(project_exclude_list_file_location_v1 "${project_exclude_list_file_location_}")

  set(mappings_files_expr_ "${global_config_subdir_}/*_mappings.txt")
  _v2c_config_set(mappings_files_expr_v1 "${mappings_files_expr_}")

  file(GLOB root_mappings_files_list_ "${CMAKE_SOURCE_DIR}/${mappings_files_expr_}")
  _v2c_config_set(root_mappings_files_list_v1 "${root_mappings_files_list_}")


  # Now do rebuilder setup within this function, too,
  # to have direct access to important configuration variables.
  if(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
    _v2c_config_do_setup_rebuilder()
  endif(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
endfunction(_v2c_config_do_setup)

_v2c_config_do_setup()


# Debug-only helper!
function(_v2c_target_log_configuration _target)
  if(TARGET ${_target})
    get_property(vs_scc_projectname_ TARGET ${_target} PROPERTY VS_SCC_PROJECTNAME)
    get_property(vs_scc_localpath_ TARGET ${_target} PROPERTY VS_SCC_LOCALPATH)
    get_property(vs_scc_provider_ TARGET ${_target} PROPERTY VS_SCC_PROVIDER)
    get_property(vs_scc_auxpath_ TARGET ${_target} PROPERTY VS_SCC_AUXPATH)
    message(FATAL_ERROR "Properties/settings target ${_target}:\n\tvs_scc_projectname_ ${vs_scc_projectname_}\n\tvs_scc_localpath_ ${vs_scc_localpath_}\n\tvs_scc_provider_ ${vs_scc_provider_}\n\tvs_scc_auxpath_ ${vs_scc_auxpath_}")
  endif(TARGET ${_target})
endfunction(_v2c_target_log_configuration _target)


if(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
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
    message(STATUS "Providing fully recursive CMakeLists.txt rebuilder target ${cmakelists_target_rebuild_all_name_}, to forcibly enact a recursive .vcproj --> CMake reconversion of all source tree sub directories.")
    set(cmakelists_update_recursively_updated_stamp_file_ "${CMAKE_CURRENT_BINARY_DIR}/cmakelists_recursive_converter_done.stamp")
    set(cmakelists_rebuilder_deps_recursive_list_
      ${_v2c_cmakelists_rebuilder_deps_common_list}
      "${script_recursive_}"
    )
    # For now, we'll NOT add the "ALL" attribute
    # since this global recursive target is supposed to be
    # a _forced_, one-time explicitly user-requested operation.
    add_custom_target(${cmakelists_target_rebuild_all_name_}
      COMMAND "${V2C_RUBY_BIN}" "${script_recursive_}"
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
  function(_v2c_project_rebuild_on_update _dependent_target _vcproj_file _cmakelists_file _script _master_proj_dir)
    message(STATUS "${_dependent_target}: providing ${_cmakelists_file} rebuilder (watching ${_vcproj_file})")

    if(NOT EXISTS "${_script}")
      # Perhaps someone manually copied over a set of foreign-machine-converted CMakeLists.txt files...
      # --> make sure that this use case does not fail anyway.
      message("WARN: ${_dependent_target}: vcproj2cmake converter script ${_script} not found, cannot activate automatic reconversion functionality!")
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

    set(cmakelists_rebuilder_deps_list_ "${_vcproj_file}" "${_script}" ${proj_mappings_files_list_} ${cmakelists_rebuilder_deps_common_list_})
    #message(FATAL_ERROR "cmakelists_rebuilder_deps_list_ ${cmakelists_rebuilder_deps_list_}")

    _v2c_config_get(cmakelists_update_check_stamp_file_v1 cmakelists_update_check_stamp_file_v1_)

    # Need an intermediate stamp file, otherwise "make clean" will clean
    # our live output file (CMakeLists.txt), yet we crucially need to preserve it
    # since it hosts this very CMakeLists.txt rebuilder mechanism...
    set(cmakelists_update_this_proj_updated_stamp_file_ "${CMAKE_CURRENT_BINARY_DIR}/cmakelists_rebuilder_done.stamp")
    add_custom_command(OUTPUT "${cmakelists_update_this_proj_updated_stamp_file_}"
      COMMAND "${V2C_RUBY_BIN}" "${_script}" "${_vcproj_file}" "${_cmakelists_file}" "${_master_proj_dir}"
      COMMAND "${CMAKE_COMMAND}" -E remove -f "${cmakelists_update_check_stamp_file_v1_}"
      COMMAND "${CMAKE_COMMAND}" -E touch "${cmakelists_update_this_proj_updated_stamp_file_}"
      DEPENDS ${cmakelists_rebuilder_deps_list_}
      COMMENT "vcproj settings changed, rebuilding ${_cmakelists_file}"
    )
    # TODO: do we have to set_source_files_properties(GENERATED) on ${_cmakelists_file}?

    if(NOT TARGET update_cmakelists_ALL__internal_collector)
      set(need_init_main_targets_this_time_ true)

      # This is the lower-level target which encompasses all .vcproj-based
      # sub projects (always separate this from external higher-level
      # target, to be able to implement additional mechanisms):
      add_custom_target(update_cmakelists_ALL__internal_collector)
    endif(NOT TARGET update_cmakelists_ALL__internal_collector)

#    if(need_init_main_targets_this_time_)
#      # Define a "rebuild of any CMakeLists.txt file occurred" marker
#      # file. This will be used to trigger subsequent targets which will
#      # abort the build.
#      set(rebuild_occurred_marker_file "${V2C_STAMP_FILES_DIR}/v2c_cmakelists_rebuild_occurred.marker")
#      add_custom_command(OUTPUT "${rebuild_occurred_marker_file}"
#        COMMAND "${CMAKE_COMMAND}" -E touch "${rebuild_occurred_marker_file}"
#      )
#      add_custom_target(update_cmakelists_rebuild_happened DEPENDS "${rebuild_occurred_marker_file}")
#    endif(need_init_main_targets_this_time_)

    # NOTE: we use update_cmakelists_[TARGET] names instead of [TARGET]_...
    # since in certain IDEs these peripheral targets will end up as user-visible folders
    # and we want to keep them darn out of sight via suitable sorting!
    set(target_cmakelists_update_this_proj_name_ update_cmakelists_${_dependent_target})
    #add_custom_target(${target_cmakelists_update_this_proj_name_} DEPENDS "${_cmakelists_file}")
    add_custom_target(${target_cmakelists_update_this_proj_name_} ALL DEPENDS "${cmakelists_update_this_proj_updated_stamp_file_}")
#    add_dependencies(${target_cmakelists_update_this_proj_name_} update_cmakelists_rebuild_happened)

    add_dependencies(update_cmakelists_ALL__internal_collector ${target_cmakelists_update_this_proj_name_})

    # We definitely need to implement aborting the build process directly
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
        _v2c_config_get(abort_BIN_v1 abort_BIN_v1_)
        _v2c_ensure_valid_variables(abort_BIN_v1_)
        add_custom_command(OUTPUT "${cmakelists_update_check_stamp_file_v1_}"
          # Obviously we need to touch the output file (success indicator) _before_ aborting by invoking false.
          # Also, we need to touch the public marker file as well.
          COMMAND "${CMAKE_COMMAND}" -E touch "${cmakelists_update_check_stamp_file_v1_}" "${cmakelists_update_check_did_abort_public_marker_file_v1_}"
          COMMAND "${CMAKE_COMMAND}" -E remove -f "${update_cmakelists_abort_build_after_update_cleanup_stamp_file_v1_}"
          COMMAND "${abort_BIN_v1_}"
          # ...and of course add another clever message command
          # right _after_ the abort processing,
          # to alert people whenever aborting happened to fail:
          COMMAND "${CMAKE_COMMAND}" -E echo "Huh, attempting to abort the build [via ${abort_BIN_v1_}] failed?? Probably this simply is an ignore-errors build run, otherwise PLEASE REPORT..."
          # Hrmm, I thought that we _need_ this dependency, otherwise at least on Ninja the
          # command will not get triggered _within_ the same build run (by the preceding target
          # removing the output file). But apparently that does not help
          # either.
#          DEPENDS "${rebuild_occurred_marker_file}"
          COMMENT ">>> === Detected a rebuild of CMakeLists.txt files - forcefully aborting the current outdated build run [force new updated-settings configure run]! <<< ==="
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
      add_dependencies(update_cmakelists_abort_build_after_update ${target_cmakelists_update_this_proj_name_})
      set(target_cmakelists_ensure_rebuilt_name_ update_cmakelists_ALL)
    else(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)
      if(need_init_main_targets_this_time_)
        add_dependencies(update_cmakelists_ALL update_cmakelists_ALL__internal_collector)
      endif(need_init_main_targets_this_time_)
      set(target_cmakelists_ensure_rebuilt_name_ ${target_cmakelists_update_this_proj_name_})
    endif(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD)

    if(TARGET ${_dependent_target}) # in some projects an actual target might not exist (i.e. we simply got passed the project name)
      # Make sure the CMakeLists.txt rebuild happens _before_ trying to build the actual target.
      add_dependencies(${_dependent_target} ${target_cmakelists_ensure_rebuilt_name_})
    endif(TARGET ${_dependent_target})
  endfunction(_v2c_project_rebuild_on_update _dependent_target _vcproj_file _cmakelists_file _script _master_proj_dir)
else(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
  function(_v2c_project_rebuild_on_update _dependent_target _vcproj_file _cmakelists_file _script _master_proj_dir)
    # dummy!
  endfunction(_v2c_project_rebuild_on_update _dependent_target _vcproj_file _cmakelists_file _script _master_proj_dir)
endif(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
if(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
  # *V2C_DOCS_POLICY_MACRO*
  macro(v2c_converter_script_set_location _location)
    # user override mechanism (don't prevent specifying a custom location of this script)
    if(NOT V2C_SCRIPT_LOCATION)
      set(V2C_SCRIPT_LOCATION "${_location}")
    endif(NOT V2C_SCRIPT_LOCATION)
  endmacro(v2c_converter_script_set_location _location)
else(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
  macro(v2c_converter_script_set_location _location)
    # DUMMY!
  endmacro(v2c_converter_script_set_location _location)
endif(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)

# *V2C_DOCS_POLICY_MACRO*
macro(v2c_hook_invoke _hook_file_name)
  include("${_hook_file_name}" OPTIONAL)
endmacro(v2c_hook_invoke _hook_file_name)

# Configure CMAKE_MFC_FLAG etc.
# _Unfortunately_ CMake historically decided to have these very dirty global flags
# rather than a per-target property. Should eventually be fixed there.
# *V2C_DOCS_POLICY_MACRO*
macro(v2c_local_set_cmake_atl_mfc_flags _target _build_type _build_platform _atl_flag _mfc_flag)
  v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
  # If active, then _we_ are the one to define the setting,
  # otherwise some other invocation will define it.
  if(is_active_)
    # CMAKE_ATL_FLAG currently is not a (~n official) CMake variable
    set(CMAKE_ATL_FLAG ${_atl_flag})
    set(CMAKE_MFC_FLAG ${_mfc_flag})
  endif(is_active_)
endmacro(v2c_local_set_cmake_atl_mfc_flags _target _build_type _build_platform _atl_flag _mfc_flag)

# Helper to hook up a precompiled header that might be enabled
# by a project configuration.
# Functionality taken from "Support for precompiled headers"
#   http://www.cmake.org/Bug/view.php?id=1260
# (vcproj2cmake can now be considered inofficial "upstream"
# of this functionality, since there probably is nobody else
# who's actively improving the module file)
# Please note that IMHO precompiled headers are not always a good idea.
# See "Precompiled Headers? Do we really need them" reply at
#   http://stackoverflow.com/a/1138356
# for a good explanation.
# PCH may become a SPOF (Single Point Of Failure) for some of the more chaotic
# projects (libraries), namely those which fail to have a clear mission
# and try to implement / reference the entire universe
# (throwing together spaghetti code which handles file handling / serialization,
# threading, GUI layout, string handling, algorithms, communication, ...).
# Consequently such a project ends up including many different toolkits
# in its main header, causing all source files to include that monster header
# despite only needing a tiny subset of that functionality each.
# Admittedly this is the worst case (which should be avoidable),
# but it does happen and it's not pretty.
function(v2c_target_add_precompiled_header _target _build_platform _build_type _use _header_file)
  v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
  if(NOT is_active_)
    return()
  endif(NOT is_active_)
  if(NOT _use)
    return()
  endif(NOT _use)
  # Need to always re-include() this module,
  # since it currently defines some non-cache variables in outer non-macro scope
  # (FIXME robustify it!),
  # thus invoking pre-defined macros from foreign scope would be missing
  # these vars.
  include(V2C_PCHSupport OPTIONAL)
  if(COMMAND add_precompiled_header)
    if(NOT TARGET ${_target})
      message("v2c_target_add_precompiled_header: no target ${_target}!? Exit...")
      return()
    endif(NOT TARGET ${_target})
    set(header_file_location_ "${PROJECT_SOURCE_DIR}/${_header_file}")
    # Complicated check! [empty file (--> dir-only) _does_ check as ok]
    if(NOT _header_file OR NOT EXISTS "${header_file_location_}")
      message("v2c_target_add_precompiled_header: header file ${_header_file} at project ${PROJECT_SOURCE_DIR} does not exist!? Exit...")
      return()
    endif(NOT _header_file OR NOT EXISTS "${header_file_location_}")
    # FIXME: should add a target-specific precomp header
    # enable / disable / force-enable flags mechanism,
    # equivalent to what our install() helper does.

    # According to several reports and own experience,
    # ${CMAKE_CURRENT_BINARY_DIR} needs to be available as include directory
    # when adding a precompiled header configuration.
    include_directories(${CMAKE_CURRENT_BINARY_DIR})
    # FIXME: needs investigation whether use/create distinction
    # is being serviced properly by the function that the module file offers.
    # Same values as used by VS7:
    set(pch_not_using_ 0)
    set(pch_create_ 1)
    set(pch_use_ 2)
    if(_use EQUAL ${pch_create_} OR _use EQUAL ${pch_use_})
      add_precompiled_header(${_target} "${header_file_location_}")
      message(STATUS "v2c_target_add_precompiled_header: added header ${_header_file} to target ${_target}")
    endif(_use EQUAL ${pch_create_} OR _use EQUAL ${pch_use_})
  else(COMMAND add_precompiled_header)
    message("could not figure out add_precompiled_header() function (missing module file?) - precompiled header support disabled.")
  endif(COMMAND add_precompiled_header)
endfunction(v2c_target_add_precompiled_header _target _build_platform _build_type _use _header_file)


if(WIN32)
  function(v2c_target_midl_specify_files _target _build_type _build_platform _header_file_name _iface_id_file_name _type_library_name)
    # DUMMY - WIN32 (Visual Studio) already has its own implicit custom commands for MIDL generation
    # (plus, CMake's Visual Studio generator also already properly passes MIDL-related files to the setup...)
  endfunction(v2c_target_midl_specify_files _target _build_type _build_platform _header_file_name _iface_id_file_name _type_library_name)
else(WIN32)
  function(_v2c_target_midl_create_dummy_file _midl_file _description)
    _v2c_ensure_valid_variables(_midl_file _description)
    set(comment_ "WARNING: creating dummy MIDL ${_description} file ${_midl_file}")
    add_custom_command(OUTPUT "${_midl_file}"
      COMMAND "${CMAKE_COMMAND}" -E echo "${comment_}"
      COMMAND "${CMAKE_COMMAND}" -E touch "${_midl_file}"
      COMMENT "${comment_}"
    )
  endfunction(_v2c_target_midl_create_dummy_file _file _description)
  function(v2c_target_midl_specify_files _target _build_type _build_platform _header_file_name _iface_id_file_name _type_library_name)
    v2c_buildcfg_check_if_platform_buildtype_active(${_target} "${_build_platform}" "${_build_type}" is_active_)
    if(NOT is_active_)
      return()
    endif(NOT is_active_)

    # For now, all we care about is creating some dummy files to make a target actually build
    # rather than aborting CMake configuration due to missing source files...

    # TODO: query all the other MIDL-related target properties
    # which possibly were configured prior to invoking this function.

    if(_header_file_name)
      _v2c_target_midl_create_dummy_file("${_header_file_name}" "header")
    endif(_header_file_name)
    if(_iface_id_file_name)
      _v2c_target_midl_create_dummy_file("${_iface_id_file_name}" "interface identifier")
    endif(_iface_id_file_name)
  endfunction(v2c_target_midl_specify_files _target _build_type _build_platform _header_file_name _iface_id_file_name _type_library_name)
endif(WIN32)


# This function will set up target properties gathered from
# Visual Studio Source Control Management (SCM) elements.
function(v2c_target_set_properties_vs_scc _target _vs_scc_projectname _vs_scc_localpath _vs_scc_provider _vs_scc_auxpath)
  # Since I was unable to make it work with some more experimentation
  # (on VS2005), we better disable it cleanly for now, since otherwise VS
  # will resort to awfully annoying nagging.
  # I slightly suspect that even CMake itself is not up to the task,
  # since a .sln usually contains Scc* tags, which the CMake generator does not provide.
  # Or perhaps VS_SCC_LOCALPATH does not reference the source directory properly (in case of original "." statement this should probably be corrected to point to the project source and not to the possibly referenced project _binary_ dir).
  # The way to go about it is to use generated solutions and try to fix _that_ up within VS until it's actually properly registered. But when trying to do so I had problems with project import always referencing the source root dir (TODO investigate more).
  message("project ${_target} found to contain VS SCC configuration properties, but VS integration does not seem to work yet - disabled! (FIXME)")
  return()
  #message(STATUS
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
    message("WARNING: ${CMAKE_CURRENT_LIST_FILE}: vcproj2cmake-supplied install handling not activated - targets _need_ to be installed properly one way or another!")
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
      message("v2c_target_install: asked to skip install of target ${_target}")
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
    message("${_target} not a valid target!?")
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
  #set(install_params_values_list_ ) # no need to unset (function scope!)

  list(APPEND install_params_values_list_ TARGETS ${_target})
  # Internal variable - lists the parameter types
  # which an install() command supports. Elements are upper-case!!
  set(install_param_list_ EXPORT DESTINATION PERMISSIONS CONFIGURATIONS COMPONENT)
  foreach(install_param_ ${install_param_list_})
    set(install_param_value_ )

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
        message(FATAL_ERROR "Variable V2C_INSTALL_${install_param_}_${_target} or V2C_INSTALL_${install_param_} not specified!")
      endif(install_param_ STREQUAL DESTINATION)
    endif(install_param_value_)
  endforeach(install_param_ ${install_param_list_})

  message(STATUS "v2c_target_install: install(${install_params_values_list_})")
  install(${install_params_values_list_})
endfunction(v2c_target_install _target)

function(v2c_target_post_setup _target _project_label _vs_keyword)
  if(TARGET ${_target})
    v2c_target_install(${_target})

    # Make sure to keep CMake Name/Keyword (PROJECT_LABEL / VS_KEYWORD properties) in our converted file, too...
    # Hrmm, both project() _and_ PROJECT_LABEL reference the same project_name?? WEIRD.
    set_property(TARGET ${_target} PROPERTY PROJECT_LABEL "${_project_label}")
    if(NOT _vs_keyword STREQUAL V2C_NOT_PROVIDED)
      set_property(TARGET ${_target} PROPERTY VS_KEYWORD "${_vs_keyword}")
    endif(NOT _vs_keyword STREQUAL V2C_NOT_PROVIDED)
  endif(TARGET ${_target})
  # DEBUG/LOG helper - enable to verify correct transfer of target properties etc.:
  #_v2c_target_log_configuration(${_target})

endfunction(v2c_target_post_setup _target _project_label _vs_keyword)

# The all-in-one helper method for post setup steps
# (install handling, VS properties, CMakeLists.txt rebuilder, ...).
# This function is expected to be _very_ volatile, with frequent signature and content changes
# (--> vcproj2cmake.rb and vcproj2cmake_func.cmake versions should always be kept in sync)
function(v2c_project_post_setup _target _vcproj_file _cmake_current_list_file)
  # Implementation note: the last argument to
  # _v2c_project_rebuild_on_update() should be as much of a 1:1 passthrough of
  # the input argument to the CMakeLists.txt converter ruby script execution as possible/suitable,
  # since invocation arguments of this script on rebuild should be (roughly) identical.
  _v2c_project_rebuild_on_update(${_target} "${_vcproj_file}" "${_cmake_current_list_file}" "${V2C_SCRIPT_LOCATION}" "${V2C_MASTER_PROJECT_DIR}")
  include("${V2C_HOOK_POST}" OPTIONAL)
endfunction(v2c_project_post_setup _target _vcproj_file _cmake_current_list_file)
