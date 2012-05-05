set(v2ci_modules_source_dir "${CMAKE_CURRENT_SOURCE_DIR}")

function(v2ci_install_populate_module_path _destination_dir)
  if(NOT _destination_dir)
    message(FATAL_ERROR "${CMAKE_CURRENT_LIST_FILE}: invalid destination directory!")
  endif(NOT _destination_dir)

  message(STATUS "Will install vcproj2cmake-specific CMake modules into ${_destination_dir}.")
  set(v2ci_module_files_list
    # NOTE: new convention is to use V2C_*.cmake for module files
    # since this is specific enough and short
    # (and many CMake Module files start with upper-case, too).
    V2C_PCHSupport.cmake
    vcproj2cmake_defs.cmake
    vcproj2cmake_func.cmake
  )
  foreach(module_file ${v2ci_module_files_list})
    install(FILES "${v2ci_modules_source_dir}/${module_file}"
      DESTINATION "${_destination_dir}"
    )
  endforeach(module_file ${v2ci_module_files_list})
endfunction(v2ci_install_populate_module_path _destination_dir)

set(v2ci_file_type_descr "V2C CMake Modules files")

set(v2ci_module_path_install_subdir_doc_string "Sub directory to install ${v2ci_file_type_descr} to")
# Pre-assign possible default setting by higher layer:
set(v2ci_module_path_install_subdir "${v2ci_module_path_install_subdir}" CACHE STRING ${v2ci_module_path_install_subdir_doc_string})

if(v2ci_module_path_install_subdir)
  v2ci_install_populate_module_path("${v2ci_module_path_install_subdir}")
else(v2ci_module_path_install_subdir)
  message(STATUS "v2ci_module_path_install_subdir not set - skipping install of ${v2ci_file_type_descr}.")
endif(v2ci_module_path_install_subdir)
