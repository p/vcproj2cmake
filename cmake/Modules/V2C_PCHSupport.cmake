# Support Precompiled Headers (PCH).
# Code taken from upstream PCH development tracker item
# "0001260: Support for precompiled headers"
#   http://www.cmake.org/Bug/view.php?id=1260
#
# TODO (sorted in order of importance):
# - COMPILE_FLAGS of a target are being _reset_: http://www.cmake.org/Bug/view.php?id=1260#c23633
# - lots of whitespace escaping missing: http://www.cmake.org/Bug/view.php?id=1260#c27263
# - catch build-type-dependent things like -DQT_DEBUG: http://www.cmake.org/Bug/view.php?id=1260#c12563
# - support general COMPILE_DEFINITIONS property: http://www.cmake.org/Bug/view.php?id=1260#c14470
# - merge possibly existing customizations of PCHSupport_rodlima.cmake?
#   http://www.cmake.org/Bug/view.php?id=1260#c10865
#
#
#
# - Try to find precompiled headers support for GCC 3.4 and 4.x
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

# Provide PCH_WANT_DEBUG for quick debug enable by user - to be set externally or edited here.
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

	SET(_PCH_include_prefix_setting "-I")

ELSE(CMAKE_COMPILER_IS_GNUCXX)
	IF(WIN32)
		SET(PCHSupport_FOUND_setting TRUE) # for experimental msvc support
		SET(_PCH_include_prefix_setting "/I")
	ELSE(WIN32)
		SET(PCHSupport_FOUND_setting FALSE)
	ENDIF(WIN32)
ENDIF(CMAKE_COMPILER_IS_GNUCXX)

# We configure some variables as CACHE -
# otherwise macros in this file would break since non-cache variables
# (e.g. _PCH_include_prefix in our case)
# would not be available on foreign scope (unrelated directories etc.).
# Rationale: CMake functions provided by a CMake module
# will be accessible everywhere,
# thus any variables referenced by these functions **should** be as well!!
# Rationale #2: compiler settings will _also_ be stored as cache variables,
# thus it's only consistent to have pre-determined compiler flags in cache, too.
# Well, that's not the whole story after all:
# Official CMake Find modules never have their _FOUND variable as CACHE.
# This is quite important since a module *should* always actively get parsed
# at least once (to define its functions), no matter what the user checks for.
# Or put differently, since function instances are not persistent between
# CMake configure runs, such basic variables shouldn't be either.
# HOWEVER, a compiler flag *is* a persistent setting (especially since the
# user may choose to customize it), thus it needs to be CACHE.
set(_PCH_include_prefix "${_PCH_include_prefix_setting}" CACHE STRING "Compiler-specific flag used to include a PCH [precompiled header]. Internal setting, should not need modification")
mark_as_advanced(_PCH_include_prefix)
set(PCHSupport_FOUND ${PCHSupport_FOUND_setting})


MACRO(_PCH_GET_COMPILE_FLAGS _out_compile_flags)


  STRING(TOUPPER "CMAKE_CXX_FLAGS_${CMAKE_BUILD_TYPE}" _flags_var_name)
  SET(${_out_compile_flags} ${${_flags_var_name}} )

  IF(CMAKE_COMPILER_IS_GNUCXX)

    GET_TARGET_PROPERTY(_targetType ${_PCH_current_target} TYPE)
    IF(${_targetType} STREQUAL SHARED_LIBRARY)
      LIST(APPEND ${_out_compile_flags} "${${_out_compile_flags}} -fPIC")
    ENDIF(${_targetType} STREQUAL SHARED_LIBRARY)

  ELSE(CMAKE_COMPILER_IS_GNUCXX)
    ## TODO ... ? or does it work out of the box
  ENDIF(CMAKE_COMPILER_IS_GNUCXX)

  GET_DIRECTORY_PROPERTY(DIRINC INCLUDE_DIRECTORIES )
  if(NOT _PCH_include_prefix)
    _pch_msg_fatal_error("empty _PCH_include_prefix!?")
  endif(NOT _PCH_include_prefix)
  FOREACH(item ${DIRINC})
    LIST(APPEND ${_out_compile_flags} "${_PCH_include_prefix}${item}")
  ENDFOREACH(item)

  GET_DIRECTORY_PROPERTY(_directory_flags DEFINITIONS)
  _pch_msg_debug("_directory_flags ${_directory_flags}" )
  LIST(APPEND ${_out_compile_flags} ${_directory_flags})
  LIST(APPEND ${_out_compile_flags} ${CMAKE_CXX_FLAGS} )

  SEPARATE_ARGUMENTS(${_out_compile_flags})

ENDMACRO(_PCH_GET_COMPILE_FLAGS)


MACRO(_PCH_WRITE_PCHDEP_CXX _targetName _include_file _dephelp)

  SET(${_dephelp} ${CMAKE_CURRENT_BINARY_DIR}/${_targetName}_pch_dephelp.cxx)
  FILE(WRITE  ${${_dephelp}}.in
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
  configure_file(${${_dephelp}}.in ${${_dephelp}} COPYONLY)

ENDMACRO(_PCH_WRITE_PCHDEP_CXX )

MACRO(_PCH_GET_COMPILE_COMMAND out_command _input _output)

	FILE(TO_NATIVE_PATH ${_input} _native_input)
	FILE(TO_NATIVE_PATH ${_output} _native_output)


	IF(CMAKE_COMPILER_IS_GNUCXX)
          IF(CMAKE_CXX_COMPILER_ARG1)
	    # remove leading space in compiler argument
            STRING(REGEX REPLACE "^ +" "" pchsupport_compiler_cxx_arg1 ${CMAKE_CXX_COMPILER_ARG1})

	    SET(${out_command}
	      ${CMAKE_CXX_COMPILER} ${pchsupport_compiler_cxx_arg1} ${_compile_FLAGS}	-x c++-header -o ${_output} ${_input}
	      )
	  ELSE(CMAKE_CXX_COMPILER_ARG1)
	    SET(${out_command}
	      ${CMAKE_CXX_COMPILER}  ${_compile_FLAGS}	-x c++-header -o ${_output} ${_input}
	      )
          ENDIF(CMAKE_CXX_COMPILER_ARG1)
	ELSE(CMAKE_COMPILER_IS_GNUCXX)

		SET(_dummy_str "#include <${_input}>")
		FILE(WRITE ${CMAKE_CURRENT_BINARY_DIR}/pch_dummy.cpp ${_dummy_str})

		SET(${out_command}
			${CMAKE_CXX_COMPILER} ${_compile_FLAGS} /c /Fp${_native_output} /Yc${_native_input} pch_dummy.cpp
		)
		#/out:${_output}

	ENDIF(CMAKE_COMPILER_IS_GNUCXX)

ENDMACRO(_PCH_GET_COMPILE_COMMAND )



MACRO(_PCH_GET_TARGET_COMPILE_FLAGS _cflags  _header_name _pch_path _dowarn )

  FILE(TO_NATIVE_PATH ${_pch_path} _native_pch_path)

  IF(CMAKE_COMPILER_IS_GNUCXX)
    # for use with distcc and gcc >4.0.1 if preprocessed files are accessible
    # on all remote machines set
    # PCH_ADDITIONAL_COMPILER_FLAGS to -fpch-preprocess
    # if you want warnings for invalid header files (which is very inconvenient
    # if you have different versions of the headers for different build types
    # you may set _dowarn
    IF (_dowarn)
      SET(${_cflags} "${PCH_ADDITIONAL_COMPILER_FLAGS} -include ${CMAKE_CURRENT_BINARY_DIR}/${_header_name} -Winvalid-pch " )
    ELSE (_dowarn)
      SET(${_cflags} "${PCH_ADDITIONAL_COMPILER_FLAGS} -include ${CMAKE_CURRENT_BINARY_DIR}/${_header_name} " )
    ENDIF (_dowarn)
  ELSE(CMAKE_COMPILER_IS_GNUCXX)

    set(${_cflags} "/Fp${_native_pch_path} /Yu${_header_name}" )

  ENDIF(CMAKE_COMPILER_IS_GNUCXX)

ENDMACRO(_PCH_GET_TARGET_COMPILE_FLAGS )

MACRO(GET_PRECOMPILED_HEADER_OUTPUT _targetName _input _output)
  GET_FILENAME_COMPONENT(_name ${_input} NAME)
  GET_FILENAME_COMPONENT(_path ${_input} PATH)
  SET(_output "${CMAKE_CURRENT_BINARY_DIR}/${_name}.gch/${_targetName}_${CMAKE_BUILD_TYPE}.h++")
ENDMACRO(GET_PRECOMPILED_HEADER_OUTPUT _targetName _input)


MACRO(ADD_PRECOMPILED_HEADER_TO_TARGET _targetName _input _pch_output_to_use )

  # to do: test whether compiler flags match between target  _targetName
  # and _pch_output_to_use
  GET_FILENAME_COMPONENT(_name ${_input} NAME)

  IF( "${ARGN}" STREQUAL "0")
    SET(_dowarn 0)
  ELSE( "${ARGN}" STREQUAL "0")
    SET(_dowarn 1)
  ENDIF("${ARGN}" STREQUAL "0")


  _PCH_GET_TARGET_COMPILE_FLAGS(_target_cflags ${_name} ${_pch_output_to_use} ${_dowarn})
     _pch_msg_debug("Add flags ${_target_cflags} to ${_targetName} " )
  SET_TARGET_PROPERTIES(${_targetName}
    PROPERTIES
    COMPILE_FLAGS ${_target_cflags}
    )

  ADD_CUSTOM_TARGET(pch_Generate_${_targetName}
    DEPENDS	${_pch_output_to_use}
    )

  ADD_DEPENDENCIES(${_targetName} pch_Generate_${_targetName} )

ENDMACRO(ADD_PRECOMPILED_HEADER_TO_TARGET)

MACRO(ADD_PRECOMPILED_HEADER _targetName _input)

  SET(_PCH_current_target ${_targetName})

  IF(NOT CMAKE_BUILD_TYPE)
    _pch_msg_fatal_error(
      "This is the ADD_PRECOMPILED_HEADER macro. "
      "You must set CMAKE_BUILD_TYPE!"
      )
  ENDIF(NOT CMAKE_BUILD_TYPE)

  IF( "${ARGN}" STREQUAL "0")
    SET(_dowarn 0)
  ELSE( "${ARGN}" STREQUAL "0")
    SET(_dowarn 1)
  ENDIF("${ARGN}" STREQUAL "0")


  GET_FILENAME_COMPONENT(_name ${_input} NAME)
  GET_FILENAME_COMPONENT(_path ${_input} PATH)
  GET_PRECOMPILED_HEADER_OUTPUT( ${_targetName} ${_input} _output)

  GET_FILENAME_COMPONENT(_outdir ${_output} PATH )

  GET_TARGET_PROPERTY(_targetType ${_PCH_current_target} TYPE)
   _PCH_WRITE_PCHDEP_CXX(${_targetName} ${_input} _pch_dephelp_cxx)

  IF(${_targetType} STREQUAL SHARED_LIBRARY)
    ADD_LIBRARY(${_targetName}_pch_dephelp SHARED ${_pch_dephelp_cxx} )
  ELSE(${_targetType} STREQUAL SHARED_LIBRARY)
    ADD_LIBRARY(${_targetName}_pch_dephelp STATIC ${_pch_dephelp_cxx})
  ENDIF(${_targetType} STREQUAL SHARED_LIBRARY)

  FILE(MAKE_DIRECTORY ${_outdir})


  _PCH_GET_COMPILE_FLAGS(_compile_FLAGS)

  _pch_msg_debug("_compile_FLAGS: ${_compile_FLAGS}")
  _pch_msg_debug("COMMAND ${CMAKE_CXX_COMPILER}	${_compile_FLAGS} -x c++-header -o ${_output} ${_input}")
  SET_SOURCE_FILES_PROPERTIES(${CMAKE_CURRENT_BINARY_DIR}/${_name} PROPERTIES GENERATED 1)
  ADD_CUSTOM_COMMAND(
   OUTPUT	${CMAKE_CURRENT_BINARY_DIR}/${_name}
   COMMAND ${CMAKE_COMMAND} -E copy  ${_input} ${CMAKE_CURRENT_BINARY_DIR}/${_name} # ensure same directory! Required by gcc
   DEPENDS ${_input}
  )

  _pch_msg_debug("_command  ${_input} ${_output}")
  _PCH_GET_COMPILE_COMMAND(_command  ${CMAKE_CURRENT_BINARY_DIR}/${_name} ${_output} )

  _pch_msg_debug("_input ${_input}\n_output ${_output}" )

  ADD_CUSTOM_COMMAND(
    OUTPUT ${_output}
    COMMAND ${_command}
    DEPENDS ${_input}   ${CMAKE_CURRENT_BINARY_DIR}/${_name} ${_targetName}_pch_dephelp
    VERBATIM
   )


  ADD_PRECOMPILED_HEADER_TO_TARGET(${_targetName} ${_input}  ${_output} ${_dowarn})
ENDMACRO(ADD_PRECOMPILED_HEADER)


# Generates the use of a precompiled header in a target,
# without using dependency targets (2 extra for each target)
# Using Visual, must also add ${_targetName}_pch to sources
# Not needed by Xcode

MACRO(GET_NATIVE_PRECOMPILED_HEADER _targetName _input)

	if(CMAKE_GENERATOR MATCHES Visual*)

		SET(_dummy_str "#include \"${_input}\"\n"
										"// This is required to suppress LNK4221.  Very annoying.\n"
										"void *g_${_targetName}Dummy = 0\;\n")

		# Use of cxx extension for generated files (as Qt does)
		SET(${_targetName}_pch ${CMAKE_CURRENT_BINARY_DIR}/${_targetName}_pch.cxx)
		if(EXISTS ${${_targetName}_pch})
			# Check if contents is the same, if not rewrite
			# todo
		else(EXISTS ${${_targetName}_pch})
			FILE(WRITE ${${_targetName}_pch} ${_dummy_str})
		endif(EXISTS ${${_targetName}_pch})
	endif(CMAKE_GENERATOR MATCHES Visual*)

ENDMACRO(GET_NATIVE_PRECOMPILED_HEADER)


MACRO(ADD_NATIVE_PRECOMPILED_HEADER _targetName _input)

	IF( "${ARGN}" STREQUAL "0")
		SET(_dowarn 0)
	ELSE( "${ARGN}" STREQUAL "0")
		SET(_dowarn 1)
	ENDIF("${ARGN}" STREQUAL "0")

	if(CMAKE_GENERATOR MATCHES Visual*)
		# Auto include the precompile (useful for moc processing, since the use of
		# precompiled is specified at the target level
		# and I don't want to specifiy /F- for each moc/res/ui generated files (using Qt)

		GET_TARGET_PROPERTY(oldProps ${_targetName} COMPILE_FLAGS)
		if (${oldProps} MATCHES NOTFOUND)
			SET(oldProps "")
		endif(${oldProps} MATCHES NOTFOUND)

		SET(newProperties "${oldProps} /Yu\"${_input}\" /FI\"${_input}\"")
		SET_TARGET_PROPERTIES(${_targetName} PROPERTIES COMPILE_FLAGS "${newProperties}")

		#also inlude ${oldProps} to have the same compile options
		SET_SOURCE_FILES_PROPERTIES(${${_targetName}_pch} PROPERTIES COMPILE_FLAGS "${oldProps} /Yc\"${_input}\"")

	else(CMAKE_GENERATOR MATCHES Visual*)

		if (CMAKE_GENERATOR MATCHES Xcode)
			# For Xcode, cmake needs my patch to process
			# GCC_PREFIX_HEADER and GCC_PRECOMPILE_PREFIX_HEADER as target properties

			GET_TARGET_PROPERTY(oldProps ${_targetName} COMPILE_FLAGS)
			if (${oldProps} MATCHES NOTFOUND)
				SET(oldProps "")
			endif(${oldProps} MATCHES NOTFOUND)

			# When buiding out of the tree, precompiled may not be located
			# Use full path instead.
			GET_FILENAME_COMPONENT(fullPath ${_input} ABSOLUTE)

			SET_TARGET_PROPERTIES(${_targetName} PROPERTIES XCODE_ATTRIBUTE_GCC_PREFIX_HEADER "${fullPath}")
			SET_TARGET_PROPERTIES(${_targetName} PROPERTIES XCODE_ATTRIBUTE_GCC_PRECOMPILE_PREFIX_HEADER "YES")

		else (CMAKE_GENERATOR MATCHES Xcode)

			#Fallback to the "old" precompiled suppport
			#ADD_PRECOMPILED_HEADER(${_targetName} ${_input} ${_dowarn})
		endif(CMAKE_GENERATOR MATCHES Xcode)
	endif(CMAKE_GENERATOR MATCHES Visual*)

ENDMACRO(ADD_NATIVE_PRECOMPILED_HEADER)
