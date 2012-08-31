project(v2c_installer NONE)

# Helper variables
set(v2ci_project_file_types_string ".vc[x]proj") # centrally lists the project file types we support.

# Helper functions

# Helper to yell loudly in case of unset variables.
# The input string should _not_ be the dereferenced form,
# but rather list simple _names_ of the variables.
function(v2ci_ensure_valid_variables)
  foreach(var_name_ ${ARGV})
    if(NOT ${var_name_})
      message(FATAL_ERROR "important vcproj2cmake variable ${var_name_} not valid/available!?")
    endif(NOT ${var_name_})
  endforeach(var_name_ ${ARGV})
endfunction(v2ci_ensure_valid_variables)


message(STATUS "Welcome to the installation handler of vcproj2cmake!")

# Provide a config option to let people choose to automatically
# download and convert/compile a very nice demo .vc[x]proj app from somewhere...
option(v2ci_vcproj_load_demo_app "Do you want to install/process this converter on a demo tree downloaded from the Internet?" ON)
if(v2ci_vcproj_load_demo_app)
  set(v2ci_vcproj_proj_source_root_doc_string "Path to the root directory of the Visual Studio ${v2ci_project_file_types_string}-based source project that you would like to CMake-enable")

  # TODO: perhaps move into a v2ci_scm_helpers.cmake module.
  function(v2ci_svn_checkout _repo_url _name _dir)
    find_package(Subversion)
    if(NOT Subversion_FOUND)
      message(FATAL_ERROR "the ${v2ci_project_file_types_string}-based demo application ${_name} needs to be fetched via Subversion, which is not installed - please install a Subversion package!")
    endif(NOT Subversion_FOUND)
    set(stamp_file_checkout_ "${_dir}/svn_checkout_${_name}.stamp")
    # need to specify stamp file as output and NOT the directory itself
    # since even an UNSUCCESSFUL svn run (think DNS issues, or so)
    # would leave that directory created.
    set(command_output_ "${stamp_file_checkout_}")
    add_custom_command(OUTPUT "${command_output_}"
      COMMAND "${Subversion_SVN_EXECUTABLE}" checkout "${_repo_url}" "${_dir}"
      COMMAND "${CMAKE_COMMAND}" -E touch "${stamp_file_checkout_}"
      DEPENDS "${Subversion_SVN_EXECUTABLE}"
      COMMENT "fetching SVN repository of ${_name} into ${_dir}"
    )
    add_custom_target(svn_checkout_${_name} ALL DEPENDS "${command_output_}")
  endfunction(v2ci_svn_checkout _repo_url _name _dir)
  function(v2ci_fetch_demo_app_osdab _demo_app_root_dir)
    set(demo_app_name_ "osdab")
    set(demo_app_repo_url_ "http://osdab.googlecode.com/svn/trunk/")
    v2ci_svn_checkout("${demo_app_repo_url_}" "${demo_app_name_}" "${_demo_app_root_dir}")
  endfunction(v2ci_fetch_demo_app_osdab _demo_app_root_dir)

  function(v2ci_fetch_demo_app_sebclient _demo_app_root_dir)
    set(demo_app_name_ "SebWindowsClient")
    set(demo_app_repo_url_ "https://seb.svn.sourceforge.net/svnroot/seb/trunk/win/SebWindowsPackage/SebWindowsClient")
    v2ci_svn_checkout("${demo_app_repo_url_}" "${demo_app_name_}" "${_demo_app_root_dir}")
  endfunction(v2ci_fetch_demo_app_sebclient _demo_app_root_dir)

  function(v2ci_fetch_demo_app_coinmp _demo_app_root_dir)
    # CoinMP sez:
    # "To build the 'CoinMP.dll', start MS Visual Studio 8 (2005) or 9 (2008),
    #  open the solution file 'CoinMP.sln' in the CoinMP\MSVisualStudio\v8
    #  folder and select 'Build Solution' from the 'Build' menu."
    set(demo_app_name_ "CoinMP")
    set(demo_app_repo_url_ "https://projects.coin-or.org/svn/CoinMP/trunk")
    v2ci_svn_checkout("${demo_app_repo_url_}" "${demo_app_name_}" "${_demo_app_root_dir}")
  endfunction(v2ci_fetch_demo_app_coinmp _demo_app_root_dir)

  function(v2ci_get_temp_dir _temp_dir_out)
    # "[CMake] Fwd: Finding the "Temp" directory code"
    #   http://www.cmake.org/pipermail/cmake/2009-November/033316.html

    # obey TMPDIR, TEMP, TMP env variable conventions:
    if(WIN32)
      set(env_var_list_ TEMP TMP)
      set(fallback_dir_ "C:\\windows\\temp")
    else(WIN32)
      set(env_var_list_ TMPDIR)
      set(fallback_dir_ "/tmp")
    endif(WIN32)
    foreach(env_var_ ${env_var_list_})
      set(tmpdir_ "$ENV{${env_var_}}")
      if(IS_DIRECTORY "${tmpdir_}")
        break()
      endif(IS_DIRECTORY "${tmpdir_}")
    endforeach(env_var_ ${env_var_list_})
    if(NOT IS_DIRECTORY "${tmpdir_}")
      set(tmpdir_ "${fallback_dir_}")
      message("No tempdir environment variables definitions found - thus trying to use ${tmpdir_} as fallback.")
    endif(NOT IS_DIRECTORY "${tmpdir_}")
    set(${_temp_dir_out} "${tmpdir_}" PARENT_SCOPE)
  endfunction(v2ci_get_temp_dir _temp_dir_out)
  v2ci_get_temp_dir(tmpdir)
  set(v2ci_demo_app_root "${tmpdir}/vcproj2cmake_demo_app")
  # CoinMP might be a more useful project than osdab?
  #v2ci_fetch_demo_app_coinmp("${v2ci_demo_app_root}")
  v2ci_fetch_demo_app_osdab("${v2ci_demo_app_root}")
  # Ouch, sebclient is _very_ large (139MB) - thus do not offer it as a publicly visible default.
  #v2ci_fetch_demo_app_sebclient("${v2ci_demo_app_root}")

  set(v2ci_vcproj_proj_source_root "${v2ci_demo_app_root}" CACHE PATH "${v2ci_vcproj_proj_source_root_doc_string}" FORCE)
  # Originally we had some broken mark_as_advanced() mechanism to hide
  # the source root from the user in case of an app download,
  # but that's stupid since the user should _learn_ where it will get
  # downloaded to.
else(v2ci_vcproj_load_demo_app)
  set(v2ci_vcproj_proj_source_root "" CACHE PATH "${v2ci_vcproj_proj_source_root_doc_string}")
endif(v2ci_vcproj_load_demo_app)
message(STATUS "root directory of project source configured to ${v2ci_vcproj_proj_source_root}")

set(v2ci_vcproj2cmake_install_subdir_doc_string "Relative location of the newly created vcproj2cmake tools path within your project")
set(v2ci_vcproj2cmake_install_subdir_default_setting "cmake/vcproj2cmake")
set(v2ci_vcproj2cmake_install_subdir "${v2ci_vcproj2cmake_install_subdir_default_setting}" CACHE STRING ${v2ci_vcproj2cmake_install_subdir_doc_string})

set(v2ci_module_path_install_subdir_doc_string "Relative location of the newly created CMake module path within your project")
set(v2ci_module_path_install_subdir_default_setting "cmake/Modules")
set(v2ci_module_path_install_subdir "${v2ci_module_path_install_subdir_default_setting}" CACHE STRING ${v2ci_module_path_install_subdir_doc_string})
mark_as_advanced(v2ci_module_path_install_subdir)

set(v2ci_vcproj_proj_do_convert_default_setting ON)
option(v2ci_vcproj_proj_do_convert "Should we automatically run a recursive conversion of projects to CMakeLists.txt within the source root directory of your ${v2ci_project_file_types_string}-based project?" ${v2ci_vcproj_proj_do_convert_default_setting})

# We don't want the user to see any default-supplied CMAKE_INSTALL_PREFIX -
# the user should be configuring our specific source root dir
# of a .vc[x]proj project.
# We don't want the user to see CMAKE_BUILD_TYPE since we don't need it at all...
mark_as_advanced(CMAKE_INSTALL_PREFIX CMAKE_BUILD_TYPE)

if(v2ci_vcproj_proj_source_root)
  # Validate source root, but only in case of a
  # supposedly already existing manually assigned project
  # (demo apps will be downloaded later).
  if(NOT v2ci_vcproj_load_demo_app)
    set(v2ci_missing_source_root_is_fatal true)
  endif(NOT v2ci_vcproj_load_demo_app)
else(v2ci_vcproj_proj_source_root)
  message(FATAL_ERROR "invalid/empty source root directory string ${v2ci_vcproj_proj_source_root}!")
endif(v2ci_vcproj_proj_source_root)

if(IS_DIRECTORY "${v2ci_vcproj_proj_source_root}")
  set(v2ci_installable true)
else(IS_DIRECTORY "${v2ci_vcproj_proj_source_root}")
  if(v2ci_missing_source_root_is_fatal)
    message(FATAL_ERROR "ERROR: directory ${v2ci_vcproj_proj_source_root} (the source root of the ${v2ci_project_file_types_string}-based project that you would like to CMake-enable) is not valid, please correct!")
  endif(v2ci_missing_source_root_is_fatal)
endif(IS_DIRECTORY "${v2ci_vcproj_proj_source_root}")

set(v2ci_minimum_cmake_version 2.6) # let's assume our installer code needs 2.6
set(v2ci_minimum_cmake_version_combined ${v2ci_minimum_cmake_version})

# If configuration appears to be valid, then we can define
# CMAKE_INSTALL_PREFIX and include subdirs which will install some
# v2c infrastructure.
if(v2ci_installable)
  # All install() instructions in subsequent directories
  # of course obey the usual convention of specifying relative paths,
  # to be installed to CMAKE_INSTALL_PREFIX.

  set(CMAKE_INSTALL_PREFIX "${v2ci_vcproj_proj_source_root}")


  set(v2ci_mappings_install_subdir "${v2ci_vcproj2cmake_install_subdir}")
  add_subdirectory(cmake)


  set(v2ci_samples_install_subdir "${v2ci_vcproj2cmake_install_subdir}")
  add_subdirectory(samples)


  set(v2ci_scripts_install_subdir "${v2ci_vcproj2cmake_install_subdir}/scripts")
  add_subdirectory(scripts)


  # Nice trick to forward CMake requirements
  # of our v2c converter infrastructure to this installer :-)
  v2ci_scripts_fetch_minimum_cmake_version(v2ci_scripts_minimum_cmake_version)
  set(v2ci_minimum_cmake_version_combined ${v2ci_scripts_minimum_cmake_version})
  if(v2ci_minimum_cmake_version_combined VERSION_LESS v2ci_scripts_minimum_cmake_version)
    set(v2ci_minimum_cmake_version_combined ${v2ci_scripts_minimum_cmake_version})
  endif(v2ci_minimum_cmake_version_combined VERSION_LESS v2ci_scripts_minimum_cmake_version)

  if(v2ci_vcproj_proj_do_convert)
    v2ci_scripts_convert_project_recursive("${v2ci_vcproj_proj_source_root}")
  endif(v2ci_vcproj_proj_do_convert)
endif(v2ci_installable)

# FIXME: perhaps this is not customer-friendly - we should check manually
# and launch a FATAL_ERROR with wording specific to vcproj2cmake tools).
cmake_minimum_required(VERSION ${v2ci_minimum_cmake_version_combined} FATAL_ERROR)
