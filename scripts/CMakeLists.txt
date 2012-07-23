if(NOT v2ci_scripts_install_subdir)
  message(FATAL_ERROR "no installation sub directory for scripts given!")
endif(NOT v2ci_scripts_install_subdir)

# Specify QUIET since it will print an annoying message
# in case of an executable-only Ruby install
# (we _do_ need the Ruby executable only)
find_package(Ruby QUIET)
if(NOT RUBY_EXECUTABLE)
  message(FATAL_ERROR "vcproj2cmake ${v2ci_project_file_types_string} conversion script currently is Ruby-based, thus your system needs to have a Ruby package installed, aborting!")
endif(NOT RUBY_EXECUTABLE)

set(v2ci_script_converter "vcproj2cmake.rb")
set(v2ci_script_converter_recursive "vcproj2cmake_recursive.rb")
set(v2ci_script_converter_settings "vcproj2cmake_settings.rb")

install(PROGRAMS
  "${v2ci_script_converter}"
  "${v2ci_script_converter_recursive}"
  DESTINATION "${v2ci_scripts_install_subdir}"
)
install(FILES
  "${v2ci_script_converter_settings}"
  DESTINATION "${v2ci_scripts_install_subdir}"
)


# A subdir precisely named "lib/" is a standard Ruby mechanism
# to automatically locate local modules.
set(v2ci_scripts_modules_subdir "lib")

# http://devblog.vworkapp.com/post/910714976/best-practice-for-rubys-require
# strongly recommends a "namespace" subdir within local module load path.
set(v2ci_scripts_modules_namespace "vcproj2cmake")

set(v2ci_scripts_modules_full_subdir "${v2ci_scripts_modules_subdir}/${v2ci_scripts_modules_namespace}")


set(v2ci_script_converter_module_util_file
  "${v2ci_scripts_modules_full_subdir}/util_file.rb"
)

set(v2ci_script_converter_module_v2c_core
  "${v2ci_scripts_modules_full_subdir}/v2c_core.rb"
)

function(v2ci_scripts_determine_minimum_cmake_version)
  set(cmake_compat_req_regex_prefix_ "str_cmake_minimum_version[ \\t]*=")
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/${v2ci_script_converter_module_v2c_core}"
    cmake_compat_req_line_ REGEX "${cmake_compat_req_regex_prefix_}"
  )
  #message("cmake_compat_req_line_ ${cmake_compat_req_line_}")
  string(REGEX REPLACE
    ".*${cmake_compat_req_regex_prefix_} '([1-9]+.[0-9]+)'.*" "\\1"
    cmake_compat_req_ "${cmake_compat_req_line_}"
  )
  if(NOT cmake_compat_req_)
    set(version_result_suspect_ true)
  endif(NOT cmake_compat_req_)
  set(expected_regex_ "[1-9]+.[0-9]+")
  if(NOT cmake_compat_req_ MATCHES "${expected_regex_}")
    set(version_result_suspect_ true)
  endif(NOT cmake_compat_req_ MATCHES "${expected_regex_}")
  if(version_result_suspect_)
    message(FATAL_ERROR "cmake_compat_req_ ${cmake_compat_req_} seems to be broken, please report!")
  endif(version_result_suspect_)
  set(v2ci_scripts_cmake_minimum_version "${cmake_compat_req_}" CACHE STRING INTERNAL)
endfunction(v2ci_scripts_determine_minimum_cmake_version)

v2ci_scripts_determine_minimum_cmake_version()

function(v2ci_scripts_fetch_minimum_cmake_version _cmake_minimum_version_out)
  # We advertise that our vcproj2cmake tools (not this install handler!)
  # need at least this version...
  # Perhaps even gather (via "file(STRINGS ...)") the version value directly
  # from our scripts...
  if(NOT v2ci_scripts_cmake_minimum_version)
    message(FATAL_ERROR "could not determine minimum CMake version required by V2C scripts!")
  endif(NOT v2ci_scripts_cmake_minimum_version)
  set(${_cmake_minimum_version_out} ${v2ci_scripts_cmake_minimum_version} PARENT_SCOPE)
endfunction(v2ci_scripts_fetch_minimum_cmake_version _cmake_minimum_version_out)

set(v2ci_scripts_modules_install_subdir
  "${v2ci_scripts_install_subdir}/${v2ci_scripts_modules_full_subdir}"
)

install(FILES
  "${v2ci_script_converter_module_util_file}"
  "${v2ci_script_converter_module_v2c_core}"
  DESTINATION "${v2ci_scripts_modules_install_subdir}"
)

# This function will be invoked _post_-install of the project.
function(v2ci_scripts_convert_project_recursive _proj_source_root)
  set(stamp_file_dir "${CMAKE_CURRENT_BINARY_DIR}/stamps")
  file(MAKE_DIRECTORY "${stamp_file_dir}")
  set(conversion_stamp "${stamp_file_dir}/vcproj_converted.stamp")
  # Should have this conversion target properly re-run
  # after each potential change due to CMake configure run:
  file(REMOVE "${conversion_stamp}")
  set(v2ci_vcproj2cmake_recursive_bin "${CMAKE_INSTALL_PREFIX}/${v2ci_scripts_install_subdir}/vcproj2cmake_recursive.rb")
  add_custom_command(OUTPUT "${conversion_stamp}"
    COMMAND "${RUBY_EXECUTABLE}" "${v2ci_vcproj2cmake_recursive_bin}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${conversion_stamp}"
    DEPENDS "${v2ci_vcproj2cmake_recursive_bin}" "${RUBY_EXECUTABLE}"
    WORKING_DIRECTORY "${_proj_source_root}"
    COMMENT "Executing recursive vcproj2cmake conversion of the ${v2ci_project_file_types_string}-based project below ${v2ci_vcproj_proj_source_root}, using ${v2ci_vcproj2cmake_recursive_bin}"
  )
  add_custom_target(convert_source_root_recursive DEPENDS "${conversion_stamp}")
endfunction(v2ci_scripts_convert_project_recursive _proj_source_root)

add_subdirectory(v2c_plugins)
