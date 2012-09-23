# Support Precompiled Headers (PCH).
# Code taken from upstream PCH development tracker item
# "0001260: Support for precompiled headers"
#   http://www.cmake.org/Bug/view.php?id=1260
#
#
# - Try to find precompiled headers (PCH) support for GCC 3.4 and 4.x
# Once done this will define:
#
# Variable:
#   PCHSupport_FOUND
#
# Macro:
#   ADD_PRECOMPILED_HEADER  _targetName _input  _dowarn
#   ADD_PRECOMPILED_HEADER_TO_TARGET _targetName _input _pch_output_to_use _dowarn
#   ADD_NATIVE_PRECOMPILED_HEADER _targetName _input _dowarn
#   GET_NATIVE_PRECOMPILED_HEADER _targetName _input


# Note that the current implementation may currently have trouble
# with older CMake versions (e.g. 2.4.x, or possibly even 2.6.x).
# I have to admit that I don't really care too much,
# since those versions were near-unusable anyway.
# Anyway, a report about breakage would be very nice, thanks!


# TODO (sorted in order of importance):
# + lots of whitespace escaping missing: http://www.cmake.org/Bug/view.php?id=1260#c27263
# - catch build-type-dependent things like -DQT_DEBUG: http://www.cmake.org/Bug/view.php?id=1260#c12563
# - merge possibly existing customizations of PCHSupport_rodlima.cmake?
#   http://www.cmake.org/Bug/view.php?id=1260#c10865
#
# * COMPILE_FLAGS of a target are being _reset_: http://www.cmake.org/Bug/view.php?id=1260#c23633
# * support general COMPILE_DEFINITIONS property: http://www.cmake.org/Bug/view.php?id=1260#c14470
#
# Development rationale:
# - try to have some mid-level functions(/macros)
#   which are compiler-independent and implement generic handling
#   of PCH mechanisms, with a multitude of function arguments (very flexible)
# - have some low-level functions which are compiler-dependent
#   and offer results to mid-level APIs
# - have some high-level APIs which are public (user-facing), long-lived APIs


# Provide PCH_WANT_DEBUG for quick debug enable by user - to be provided externally or edited here.
#set(PCH_WANT_DEBUG true)
if(PCH_WANT_DEBUG)
  macro(_pch_msg_debug _msg)
    message("V2C_PCHSupport module: ${_msg}")
  endmacro(_pch_msg_debug _msg)
else(PCH_WANT_DEBUG)
  macro(_pch_msg_debug _msg)
    # DUMMY
  endmacro(_pch_msg_debug _msg)
endif(PCH_WANT_DEBUG)

# Internal shortcut helper offering conveniently enhanced FATAL_ERROR messages.
macro(_pch_msg_fatal_error _msg)
  message(FATAL_ERROR "V2C_PCHSupport module: ${_msg}")
endmacro(_pch_msg_fatal_error _msg)

# Helper to yell loudly in case of unset variables.
# The input string should _not_ be the dereferenced form,
# but rather list simple _names_ of the variables.
function(_pch_ensure_valid_variables)
  foreach(var_name_ ${ARGV})
    if(NOT ${var_name_})
      _pch_msg_fatal_error("important variable ${var_name_} not valid/available!?")
    endif(NOT ${var_name_})
  endforeach(var_name_ ${ARGV})
endfunction(_pch_ensure_valid_variables)

# Helper to explicitly quote a variable's content if needed.
# Should probably only be used in cases where trying
# to achieve better automatic handling is hopeless.
macro(_pch_quote_manually_if_needed _var)
  # TODO: should detect already existing quoting of the content
  # (either via '"' or via ''').
  if(${${_var}} MATCHES " ")
    set(${_var} "\"${${_var}}\"")
  endif(${${_var}} MATCHES " ")
endmacro(_pch_quote_manually_if_needed _var)

if(NOT PCH_SKIP_CHECK_VALID_PROJECT)
  if(NOT PROJECT_NAME)
    # WARNING: the CMAKE_COMPILER_IS_GNUCXX variable will be properly set
    # *after* a project() line only!
    _pch_msg_fatal_error("Precompiled header (PCH) compiler support detection only works subsequent to a project() line.")
  endif(NOT PROJECT_NAME)
endif(NOT PCH_SKIP_CHECK_VALID_PROJECT)

_pch_msg_debug("CMAKE_COMPILER_IS_GNUCXX ${CMAKE_COMPILER_IS_GNUCXX}")

IF(CMAKE_COMPILER_IS_GNUCXX)

    EXEC_PROGRAM(
        ${CMAKE_CXX_COMPILER}
        ARGS 	${CMAKE_CXX_COMPILER_ARG1} -dumpversion
        OUTPUT_VARIABLE gcc_compiler_version)
    # WARNING: -dumpversion sometimes outputs a 2-digit number ("4.6") only!
    _pch_msg_debug("GCC Version: ${gcc_compiler_version}")
    set(gcc4_pch_regex "4\\.[0-9](\\.[0-9])?")
    IF(gcc_compiler_version MATCHES "${gcc4_pch_regex}")
        SET(PCHSupport_FOUND_setting TRUE)
    ELSE(gcc_compiler_version MATCHES "${gcc4_pch_regex}")
        set(gcc3_pch_regex "3\\.4\\.[0-9]")
        IF(gcc_compiler_version MATCHES "${gcc3_pch_regex}")
            SET(PCHSupport_FOUND_setting TRUE)
        ENDIF(gcc_compiler_version MATCHES "${gcc3_pch_regex}")
    ENDIF(gcc_compiler_version MATCHES "${gcc4_pch_regex}")

	SET(_PCH_include_flag_prefix_setting "-I")
	SET(_PCH_definitions_flag_prefix_setting "-D")

ELSE(CMAKE_COMPILER_IS_GNUCXX)
	IF(WIN32)
		SET(PCHSupport_FOUND_setting TRUE) # for experimental MSVC support
		SET(_PCH_include_flag_prefix_setting "/I")
	        SET(_PCH_definitions_flag_prefix_setting "/D")
	ELSE(WIN32)
		SET(PCHSupport_FOUND_setting FALSE)
	ENDIF(WIN32)
ENDIF(CMAKE_COMPILER_IS_GNUCXX)

# We configure some variables as CACHE -
# otherwise macros in this file would break since non-CACHE variables
# (e.g. _PCH_include_flag_prefix in our case)
# would not be available on foreign scope (unrelated directories etc.).
# Rationale: CMake functions/macros provided by a CMake module
# will be accessible everywhere,
# thus any variables referenced by these functions **should** be as well!!
# Rationale #2: some compiler settings will _also_ be stored as CACHE variables,
# thus it's only consistent to have pre-determined compiler flags in cache, too.
# Well, that's not the whole story after all:
# Official CMake Find modules never have their _FOUND variable as CACHE.
# This is quite important since a module *should* always actively get parsed
# at least once (to define its functions), no matter what the user checks for.
# Or put differently, since function instances are not persistent between
# CMake configure runs, such basic variables shouldn't be either.
# HOWEVER, a user-facing compiler flag *is* a persistent setting
# (especially since the user may choose to customize it),
# thus it needs to be CACHE.
set(_PCH_definitions_flag_prefix "${_PCH_definitions_flag_prefix_setting}" CACHE STRING "Compiler-specific flag used to add a define. Internal setting, should not need modification.")
set(_PCH_include_flag_prefix "${_PCH_include_flag_prefix_setting}" CACHE STRING "Compiler-specific flag used to include a PCH [precompiled header]. Internal setting, should not need modification.")
mark_as_advanced(_PCH_definitions_flag_prefix _PCH_include_flag_prefix)
set(PCHSupport_FOUND ${PCHSupport_FOUND_setting})

# Appends a string containing various space-separated items
# to an existing otherwise *non-manipulated* list,
# thereby preserving payload specifics of existing items in that list.
macro(_pch_append_string_items_to_list _list_var_name _string_var_name)
  set(pch_list_conversion_var_ "${${_string_var_name}}")
  separate_arguments(pch_list_conversion_var_)
  list(APPEND ${_list_var_name} ${pch_list_conversion_var_})
endmacro(_pch_append_string_items_to_list _list_var_name _string)

# Preconditions: expects _PCH_current_target to be set.
MACRO(_PCH_GATHER_EXISTING_COMPILE_FLAGS_FROM_SCOPE _out_compile_flags_list)

  set(pch_all_compile_flags_list_ "")
  STRING(TOUPPER "CMAKE_CXX_FLAGS_${CMAKE_BUILD_TYPE}" _flags_var_name)
  _pch_append_string_items_to_list(pch_all_compile_flags_list_ ${_flags_var_name})

  IF(CMAKE_COMPILER_IS_GNUCXX)

    GET_TARGET_PROPERTY(_targetType ${_PCH_current_target} TYPE)
    IF(${_targetType} STREQUAL SHARED_LIBRARY)
      LIST(APPEND pch_all_compile_flags_list_ "-fPIC")
    ENDIF(${_targetType} STREQUAL SHARED_LIBRARY)

  ELSE(CMAKE_COMPILER_IS_GNUCXX)
    ## TODO ... ? or does it work out of the box
  ENDIF(CMAKE_COMPILER_IS_GNUCXX)

  GET_DIRECTORY_PROPERTY(DIRINC INCLUDE_DIRECTORIES )
  _pch_ensure_valid_variables(_PCH_include_flag_prefix)
  FOREACH(item_ ${DIRINC})
    _pch_msg_debug("dir include item_: ${item_}")
    # Handle space-containing args!! This definitely needs to end up
    # properly quoted on the compiler side!
    _pch_quote_manually_if_needed(item_)
    LIST(APPEND pch_all_compile_flags_list_ "${_PCH_include_flag_prefix}${item_}")
  ENDFOREACH(item_)

  # FIXME: should get directory *flags* not definitions,
  # but CMake does not offer that.
  #GET_DIRECTORY_PROPERTY(_directory_definitions DEFINITIONS)
  #_pch_msg_debug("_directory_flags '${_directory_flags}'" )
  #LIST(APPEND pch_all_compile_flags_list_ ${_directory_flags})
  _pch_append_string_items_to_list(pch_all_compile_flags_list_ CMAKE_CXX_FLAGS)

  # This separate_arguments() call actively destroys embedded space
  # within arguments (e.g. include directories), thus it should NOT
  # be used (at this point we should have a properly separated list already
  # anyway).
  #SEPARATE_ARGUMENTS(pch_all_compile_flags_list_)

  SET(${_out_compile_flags_list} ${pch_all_compile_flags_list_})
  _pch_msg_debug("_out_compile_flags_list ${${_out_compile_flags_list}}")

ENDMACRO(_PCH_GATHER_EXISTING_COMPILE_FLAGS_FROM_SCOPE)

MACRO(_PCH_GATHER_EXISTING_COMPILE_DEFINITIONS_FROM_SCOPE _out_compile_defs_list)
  set(pch_all_compile_defs_list_ "")
  # COMPILE_DEFINITIONS prop lists definitions *without* compiler-specific
  # -D prefix (which is exactly what I expect a compiler-abstracted part to do!!).
  GET_DIRECTORY_PROPERTY(dir_defs_ COMPILE_DEFINITIONS)
  _pch_msg_debug("CMAKE_CURRENT_LIST_DIR ${CMAKE_CURRENT_LIST_DIR}")
  _pch_normalize_notfound_var_content(dir_defs_)
  _pch_msg_debug("dir_defs_ ${dir_defs_}")
  _pch_append_string_items_to_list(pch_all_compile_defs_list_ dir_defs_)
  GET_TARGET_PROPERTY(target_defs_ ${_PCH_current_target} COMPILE_DEFINITIONS)
  _pch_normalize_notfound_var_content(target_defs_)
  _pch_msg_debug("target_defs_ ${target_defs_}")
  _pch_append_string_items_to_list(pch_all_compile_defs_list_ target_defs_)
  _pch_msg_debug("pch_all_compile_defs_list_ ${pch_all_compile_defs_list_}")
  set(${_out_compile_defs_list} "${pch_all_compile_defs_list_}")
  _pch_msg_debug("_out_compile_defs_list ${${_out_compile_defs_list}}")
ENDMACRO(_PCH_GATHER_EXISTING_COMPILE_DEFINITIONS_FROM_SCOPE _out_compile_defs_list)

MACRO(_PCH_WRITE_PCHDEP_CXX _targetName _include_file _out_dephelp)

  SET(pch_dephelp_fqpn_ ${CMAKE_CURRENT_BINARY_DIR}/${_targetName}_pch_dephelp.cxx)
  FILE(WRITE  ${pch_dephelp_fqpn_}.in
"#include \"${_include_file}\"
int testfunction()
{
    return 0;
}
"
    )
  # use configure_file() to avoid re-touching the live file
  # _every_ time thus causing eternal rebuilds
  # (configure_file() does know to skip if unchanged)
  configure_file(${pch_dephelp_fqpn_}.in ${pch_dephelp_fqpn_} COPYONLY)

  SET(${_out_dephelp} ${pch_dephelp_fqpn_})

ENDMACRO(_PCH_WRITE_PCHDEP_CXX )

# Returns the compile flags required to *Create* a PCH, and only those.
MACRO(_PCH_GET_COMPILE_FLAGS_PCH_CREATE _out_cflags _header _pch _pch_creator_cxx)
	set(cflags_pch_create_ "")

	IF(CMAKE_COMPILER_IS_GNUCXX)
	  # gcc does not build the PCH via a .cpp builder file,
	  # thus this argument is not used... right!? 
	  SET(cflags_pch_create_ -x c++-header -o ${_pch} ${_header})
	ELSE(CMAKE_COMPILER_IS_GNUCXX)
		SET(cflags_pch_create_ /c /Fp${_pch} /Yc${_header} ${_pch_creator_cxx}
		)
		#/out:${_pch}

	ENDIF(CMAKE_COMPILER_IS_GNUCXX)

	SET(${_out_cflags} ${cflags_pch_create_})

ENDMACRO(_PCH_GET_COMPILE_FLAGS_PCH_CREATE _out_cflags _header _pch _pch_creator_cxx)

# Returns the compile flags required to *Use* a PCH, and only those.
MACRO(_PCH_GET_COMPILE_FLAGS_PCH_USE _out_cflags _header_name _pch_path_arg _dowarn )

  set(cflags_pch_use_ "")

  IF(CMAKE_COMPILER_IS_GNUCXX)
    # gcc does not seem to need/use _pch_path arg.

    # For use with distcc and gcc >4.0.1.
    # If preprocessed files are accessible on all remote machines,
    # set PCH_ADDITIONAL_COMPILER_FLAGS to -fpch-preprocess.
    # If you want warnings for invalid header files (which is very inconvenient
    # if you have different versions of the headers for different build types)
    # you may set _dowarn.
    set(pch_gcc_pch_warn_flag_ "") # Provide empty default
    IF(${_dowarn})
      set(pch_gcc_pch_warn_flag_ "-Winvalid-pch")
    ENDIF(${_dowarn})
    _pch_msg_debug("_dowarn ${_dowarn}, flag ${pch_gcc_pch_warn_flag_}")
    set(pch_header_location_ "${CMAKE_CURRENT_BINARY_DIR}/${_header_name}")
    # Unfortunately the compile flags variable is a *string*
    # (due to COMPILE_FLAGS property string-only limitation),
    # thus we need to use explicit manual quoting rather than possibly
    # relying on CMake-side quoting mechanisms of individual list elements. 
    _pch_quote_manually_if_needed(pch_header_location_)
    SET(cflags_pch_use_ "${PCH_ADDITIONAL_COMPILER_FLAGS} -include ${pch_header_location_} ${pch_gcc_pch_warn_flag_} " )

    # Currently there seems to be an annoyance on gcc side where headers
    # without include guards lead to duplicate inclusion, whereas on MSVC
    # stdafx.h is NOT required to have include guards or #pragma once.
    # Maybe it's simply due to our setup not being sophisticated enough. FIXME.
    # Possibly helpful links:
    # http://stackoverflow.com/questions/3162510/how-to-make-gcc-search-for-headers-in-a-directory-before-the-current-source-file
    # http://stackoverflow.com/questions/9580058/in-gcc-can-precompiled-headers-be-included-from-other-headers?rq=1

  ELSE(CMAKE_COMPILER_IS_GNUCXX)

    if(_pch_path_arg)
      set(cflags_pch_use_ "${cflags_pch_use_} /Fp${_pch_path_arg}")
    endif(_pch_path_arg)
    set(cflags_pch_use_ "${cflags_pch_use_} /Yu${_header_name}" )

  ENDIF(CMAKE_COMPILER_IS_GNUCXX)

  set(${_out_cflags} ${cflags_pch_use_})

ENDMACRO(_PCH_GET_COMPILE_FLAGS_PCH_USE )

MACRO(_PCH_GET_COMPILE_COMMAND_PCH_CREATE _out_command _input _output _pch_creator_cxx)

        # Let's assume that native paths are useful for both MSVC and now gcc, too.
	FILE(TO_NATIVE_PATH ${_input} _native_input)
	FILE(TO_NATIVE_PATH ${_output} _native_output)

        set(pch_compiler_cxx_arg1_ "") # Provide empty default
        set(pch_creator_cxx_ "${_pch_creator_cxx}")
	IF(CMAKE_COMPILER_IS_GNUCXX)
          IF(CMAKE_CXX_COMPILER_ARG1)
	    # remove leading space in compiler argument
            STRING(REGEX REPLACE "^ +" "" pch_compiler_cxx_arg1_ ${CMAKE_CXX_COMPILER_ARG1})

          ENDIF(CMAKE_CXX_COMPILER_ARG1)
	ELSE(CMAKE_COMPILER_IS_GNUCXX)

	  # MSVC uses a .cpp to create the PCH,
	  # thus provide an ad-hoc instance of it if needed.
	  if(NOT pch_creator_cxx_)
	    SET(pch_creator_cxx_ pch_creator_dummy.cpp)
	    _pch_write_pch_creator_cxx(${CMAKE_CURRENT_BINARY_DIR}/${pch_creator_cxx_} "2")
	  endif(NOT pch_creator_cxx_)
	ENDIF(CMAKE_COMPILER_IS_GNUCXX)

	_PCH_GET_COMPILE_FLAGS_PCH_CREATE(_compile_FLAGS_PCH "${_native_input}" "${_native_output}" "${pch_creator_cxx_}")

	# FIXME: why the ******[CENSORED] do we feel the need
	# to fumble together a manual compiler invocation here,
	# rather than generating a standard compiler-abstracted *target*
	# for creating the PCH!?
	# I could accept this being externally required to be done this way,
	# but then at the very least a detailed comment is sorely missing here...
	SET(${_out_command} ${CMAKE_CXX_COMPILER} ${pch_compiler_cxx_arg1_} ${_compile_FLAGS} ${_compiler_decorated_DEFS} ${_compile_FLAGS_PCH})
ENDMACRO(_PCH_GET_COMPILE_COMMAND_PCH_CREATE )


macro(_pch_get_default_output_location_name _targetName _input _out_output)
  GET_FILENAME_COMPONENT(_name ${_input} NAME)
  GET_FILENAME_COMPONENT(_path ${_input} PATH)
  SET(${_out_output} "${CMAKE_CURRENT_BINARY_DIR}/${_name}.gch/${_targetName}_${CMAKE_BUILD_TYPE}.h++")
  _pch_msg_debug("created default PCH output name: ${${_out_output}}")
endmacro(_pch_get_default_output_location_name _targetName _input _out_output)

# Existing legacy public API (unfortunate naming).
MACRO(GET_PRECOMPILED_HEADER_OUTPUT _targetName _input _output)
  _pch_get_default_output_location_name(${_targetName} ${_input} output_)
  set(${_output} ${output_})
ENDMACRO(GET_PRECOMPILED_HEADER_OUTPUT _targetName _input _output)

# Detects "<var>-NOTFOUND" content, erases it.
macro(_pch_normalize_notfound_var_content _var_name)
  if("${${_var_name}}" MATCHES NOTFOUND)
    _pch_msg_debug("variable ${_var_name} was NOTFOUND.")
    SET(${_var_name} "")
  endif("${${_var_name}}" MATCHES NOTFOUND)
endmacro(_pch_normalize_notfound_var_content _var_name)

macro(_pch_target_compile_flags_get _targetName _out_cflags_string)
  GET_TARGET_PROPERTY(cflags_ ${_targetName} COMPILE_FLAGS)
  _pch_normalize_notfound_var_content(cflags_)
  set(${_out_cflags_string} "${cflags_}")
endmacro(_pch_target_compile_flags_get _targetName _out_cflags_string)

# Small helper to ensure that adding COMPILE_FLAGS will NOT lose the old ones.
macro(_pch_target_compile_flags_add _targetName _cflags_string)
  _pch_target_compile_flags_get(${_targetName} cflags_old_)
  _pch_msg_debug("Add flags ${_cflags_string} to ${_targetName} (pre-existing: ${cflags_old_})" )
  SET(cflags_new_ "${cflags_old_} ${_cflags_string}")
  SET_TARGET_PROPERTIES(${_targetName} PROPERTIES COMPILE_FLAGS "${cflags_new_}")
endmacro(_pch_target_compile_flags_add _targetName _cflags_string)


MACRO(ADD_PRECOMPILED_HEADER_TO_TARGET _targetName _input _pch_output_to_use )

  # to do: test whether compiler flags match between target  _targetName
  # and _pch_output_to_use
  GET_FILENAME_COMPONENT(_name ${_input} NAME)

  # BUG FIX: a non-option invocation will cause ARGN def to be skipped!!
  set(dowarn_ 0)
  if(${ARGN})
    IF( "${ARGN}" STREQUAL "0")
    ELSE( "${ARGN}" STREQUAL "0")
      SET(dowarn_ 1)
    ENDIF("${ARGN}" STREQUAL "0")
  endif(${ARGN})


  FILE(TO_NATIVE_PATH ${_pch_output_to_use} _pch_output_to_use_native)

  _PCH_GET_COMPILE_FLAGS_PCH_USE(_target_cflags_use ${_name} ${_pch_output_to_use_native} ${dowarn_})
  _pch_target_compile_flags_add(${_targetName} ${_target_cflags_use})

  ADD_CUSTOM_TARGET(pch_Generate_${_targetName}
    DEPENDS	${_pch_output_to_use}
    )

  ADD_DEPENDENCIES(${_targetName} pch_Generate_${_targetName} )

ENDMACRO(ADD_PRECOMPILED_HEADER_TO_TARGET)

MACRO(ADD_PRECOMPILED_HEADER _targetName _input)

  SET(_PCH_current_target ${_targetName})

  # This check is VERY debatable.
  # This function here is used for multi-config setups as well
  # yet CMAKE_BUILD_TYPE should NOT be set there.
  # Also, what I think is the case is that our PCH stuff
  # queries CMAKE_BUILD_TYPE for file naming purposes and stuff,
  # and does not tolerate it not being set.
  # Obviously the problem is in our own handling,
  # since we should be having our own CACHE variable
  # to mimick a CMAKE_BUILD_TYPE whenever it's not set(table).
  # Again, setting a specific (and automatically wrong) CMAKE_BUILD_TYPE
  # on multi-config (CMAKE_CONFIGURATION_TYPES available) is not a good thing to do.
  IF(NOT CMAKE_BUILD_TYPE)
    _pch_msg_fatal_error(
      "This is the ADD_PRECOMPILED_HEADER macro. "
      "You must set CMAKE_BUILD_TYPE!"
      )
  ENDIF(NOT CMAKE_BUILD_TYPE)

  # BUG FIX: a non-option invocation will cause ARGN def to be skipped!!
  set(dowarn_ 0)
  if(${ARGN})
    IF( "${ARGN}" STREQUAL "0")
    ELSE( "${ARGN}" STREQUAL "0")
      SET(dowarn_ 1)
    ENDIF("${ARGN}" STREQUAL "0")
  endif(${ARGN})

  GET_FILENAME_COMPONENT(_name ${_input} NAME)
  GET_FILENAME_COMPONENT(_path ${_input} PATH)
  _pch_get_default_output_location_name( ${_targetName} ${_input} output_)

  GET_FILENAME_COMPONENT(_outdir ${output_} PATH)

  _PCH_WRITE_PCHDEP_CXX(${_targetName} ${_input} _pch_dephelp_cxx)
  GET_TARGET_PROPERTY(_targetType ${_PCH_current_target} TYPE)
  IF(${_targetType} STREQUAL SHARED_LIBRARY)
    set(lib_type_arg_ "SHARED")
  ELSE(${_targetType} STREQUAL SHARED_LIBRARY)
    set(lib_type_arg_ "STATIC")
  ENDIF(${_targetType} STREQUAL SHARED_LIBRARY)
  ADD_LIBRARY(${_targetName}_pch_dephelp ${lib_type_arg_} ${_pch_dephelp_cxx})

  FILE(MAKE_DIRECTORY ${_outdir})


  _PCH_GATHER_EXISTING_COMPILE_FLAGS_FROM_SCOPE(_compile_FLAGS)
  _PCH_GATHER_EXISTING_COMPILE_DEFINITIONS_FROM_SCOPE(_compile_DEFS)

  _pch_ensure_valid_variables(_PCH_definitions_flag_prefix)
  set(_compiler_decorated_DEFS "")
  foreach(def_ ${_compile_DEFS})
    list(APPEND _compiler_decorated_DEFS "${_PCH_definitions_flag_prefix}${def_}")
  endforeach(def_ ${_compile_DEFS})

  # NOTE: for older CMake:s, we might need to append a ${CMAKE_CFG_INTDIR}
  # to CMAKE_CURRENT_BINARY_DIR (now implicitly included).
  # [provide a helper macro to do such things]
  # For details see CMake issue 0009219
  # "CMAKE_CFG_INTDIR docs says it expands to IntDir, but it expands to OutDir".
  set(header_file_copy_in_binary_dir_ ${CMAKE_CURRENT_BINARY_DIR}/${_name})
  SET_SOURCE_FILES_PROPERTIES(${header_file_copy_in_binary_dir_} PROPERTIES GENERATED 1)
  ADD_CUSTOM_COMMAND(
   OUTPUT	${header_file_copy_in_binary_dir_}
   COMMAND ${CMAKE_COMMAND} -E copy  ${_input} ${header_file_copy_in_binary_dir_} # ensure same directory! Required by gcc
   DEPENDS ${_input}
  )

  _PCH_GET_COMPILE_COMMAND_PCH_CREATE(_compile_command_pch_create  ${header_file_copy_in_binary_dir_} ${output_} "")

  _pch_msg_debug("_compile_FLAGS: ${_compile_FLAGS}\n_compiler_decorated_DEFS: ${_compiler_decorated_DEFS}")
  _pch_msg_debug("_input ${_input}\noutput_ ${output_}" )
  _pch_msg_debug("COMMAND ${_compile_command_pch_create}")

  ADD_CUSTOM_COMMAND(
    OUTPUT ${output_}
    COMMAND ${_compile_command_pch_create}
    DEPENDS ${_input}   ${header_file_copy_in_binary_dir_} ${_targetName}_pch_dephelp
    VERBATIM
   )


  ADD_PRECOMPILED_HEADER_TO_TARGET(${_targetName} ${_input} ${output_} ${dowarn_})
ENDMACRO(ADD_PRECOMPILED_HEADER)

# Added a unified helper for writing the various differing PCH creator files...
# FIXME: I don't quite believe that this requires two different variants
# (writing quote vs. brackets includes, correct linker error) here,
# most likely it should be merged to be one and the same
# (especially the PCH header #include is always done with quotes on MSVC,
# not default-include-path-type brackets).
macro(_pch_write_pch_creator_cxx _pch_creator_cxx _variant)
  if("${_variant}" EQUAL "1")
    # I suspected that this LNK4221 workaround might trigger
    # an "unused variable" warning (should do the usual "(void) var;" trick),
    # but that's not the case (due to compile-unit-external variable?).
    SET(dummy_file_content_ "#include \"${_input}\"\n"
      "// This is required to suppress LNK4221.  Very annoying.\n"
      "void *g_${_targetName}Dummy = 0\;\n")
  else("${_variant}" EQUAL "1")
    SET(dummy_file_content_ "#include <${_header}>")
  endif("${_variant}" EQUAL "1")

  if(EXISTS ${_pch_creator_cxx})
  	# Check if contents is the same, if not rewrite
  	# todo
  else(EXISTS ${_pch_creator_cxx})
  	FILE(WRITE ${_pch_creator_cxx} ${dummy_file_content_})
  endif(EXISTS ${_pch_creator_cxx})
endmacro(_pch_write_pch_creator_cxx _pch_creator_cxx _variant)

MACRO(_PCH_GET_NATIVE_PRECOMPILED_HEADER _targetName _input _out_pch_creator_cxx)

	if(CMAKE_GENERATOR MATCHES Visual*)
		# Use of cxx extension for generated files (as Qt does)
		SET(this_pch_creator_cxx_ ${CMAKE_CURRENT_BINARY_DIR}/${_targetName}_pch.cxx)
		_pch_write_pch_creator_cxx(${this_pch_creator_cxx_} "1")
		set(${_out_pch_creator} ${this_pch_creator_cxx_})
	endif(CMAKE_GENERATOR MATCHES Visual*)

ENDMACRO(_PCH_GET_NATIVE_PRECOMPILED_HEADER _targetName _input _out_pch_creator_cxx)

# Generates the use of a precompiled header (PCH) in a target,
# without using dependency targets (2 extra for each target)
# Using Visual, must also add ${_targetName}_pch_creator_cxx to sources
# Not needed by Xcode

MACRO(GET_NATIVE_PRECOMPILED_HEADER _targetName _input)
  _PCH_GET_NATIVE_PRECOMPILED_HEADER(${_targetName} ${_input} ${_targetName}_pch_creator_cxx)

  # Provide interim legacy user-side support - keep offering ${_targetName}_pch
  # TODO_FEATURE_REMOVAL_TIME_2014
  # (Argh, this variable was a terrible misnomer!
  # We're talking about the .cpp-based *creator* of the PCH binary,
  # not the PCH itself!!):
  set(pch_legacy_variable_name_ ${_targetName}_pch)
  set(${pch_legacy_variable_name_} ${${_targetName}_pch_creator_cxx})
ENDMACRO(GET_NATIVE_PRECOMPILED_HEADER)


MACRO(ADD_NATIVE_PRECOMPILED_HEADER _targetName _input)

  	# BUG FIX: a non-option invocation will cause ARGN def to be skipped!!
  	set(dowarn_ 0)
  	if(${ARGN})
    	  IF( "${ARGN}" STREQUAL "0")
    	  ELSE( "${ARGN}" STREQUAL "0")
      	    SET(dowarn_ 1)
    	  ENDIF("${ARGN}" STREQUAL "0")
  	endif(${ARGN})

	if(CMAKE_GENERATOR MATCHES Visual*)
		# Auto include the precompile (useful for moc processing,
		# since the use of PCH is specified at the target level
		# and I don't want to specify /F-
		# for each moc/res/ui generated file (using Qt))

		# Hmm, cannot make use of _pch_target_compile_flags_add() here
		# (need oldFlags here - for source properties, too).
		_pch_target_compile_flags_get(${_targetName} oldFlags)

		SET(newFlags "${oldFlags} /Yu\"${_input}\" /FI\"${_input}\"")
		SET_TARGET_PROPERTIES(${_targetName} PROPERTIES COMPILE_FLAGS "${newFlags}")

		#also include ${oldFlags} to have the same compile options
		SET_SOURCE_FILES_PROPERTIES(${${_targetName}_pch_creator_cxx} PROPERTIES COMPILE_FLAGS "${oldFlags} /Yc\"${_input}\"")

	else(CMAKE_GENERATOR MATCHES Visual*)

		if (CMAKE_GENERATOR MATCHES Xcode)
			# For Xcode, CMake needs my patch to process
			# GCC_PREFIX_HEADER and GCC_PRECOMPILE_PREFIX_HEADER as target properties

			# Ermm, we didn't use any flags here!? --> disabled!
		        #_pch_target_compile_flags_get(${_targetName} oldFlags)

			# When building out-of-tree, PCH may not be located -
			# use full path instead.
			GET_FILENAME_COMPONENT(fullPath ${_input} ABSOLUTE)

			SET_TARGET_PROPERTIES(${_targetName} PROPERTIES XCODE_ATTRIBUTE_GCC_PREFIX_HEADER "${fullPath}")
			SET_TARGET_PROPERTIES(${_targetName} PROPERTIES XCODE_ATTRIBUTE_GCC_PRECOMPILE_PREFIX_HEADER "YES")

		else (CMAKE_GENERATOR MATCHES Xcode)

			#Fallback to the "old" PCH support
			#ADD_PRECOMPILED_HEADER(${_targetName} ${_input} ${dowarn_})
		endif(CMAKE_GENERATOR MATCHES Xcode)
	endif(CMAKE_GENERATOR MATCHES Visual*)

ENDMACRO(ADD_NATIVE_PRECOMPILED_HEADER)
