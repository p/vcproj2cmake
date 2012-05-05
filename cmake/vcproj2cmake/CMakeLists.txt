set(v2ci_vcproj2cmake_mappings_source_dir "${CMAKE_CURRENT_SOURCE_DIR}")

function(v2ci_install_populate_vcproj2cmake_mappings_dir _destination_dir)
  if(NOT _destination_dir)
    message(FATAL_ERROR "${CMAKE_CURRENT_LIST_FILE}: invalid destination directory!")
  endif(NOT _destination_dir)

  message(STATUS "Will install vcproj2cmake-specific define/dependency/include mappings files (sample files!) into ${_destination_dir}.")
  set(v2ci_mappings_files_list
    define_mappings.txt
    dependency_mappings.txt
    include_mappings.txt
    lib_dirs_dep_mappings.txt
    lib_dirs_mappings.txt
  )
  foreach(mappings_file ${v2ci_mappings_files_list})
    list(APPEND v2ci_mappings_files_install_list "${v2ci_vcproj2cmake_mappings_source_dir}/${mappings_file}")
  endforeach(mappings_file ${v2ci_mappings_files_list})
  install(FILES ${v2ci_mappings_files_install_list}
    DESTINATION "${_destination_dir}"
  )
endfunction(v2ci_install_populate_vcproj2cmake_mappings_dir _destination_dir)

set(v2ci_file_type_descr "V2C mappings files")

set(v2ci_mappings_install_subdir_doc_string "Sub directory to install ${v2ci_file_type_descr} to")
# Pre-assign possible default setting by higher layer:
set(v2ci_mappings_install_subdir "${v2ci_mappings_install_subdir}" CACHE STRING ${v2ci_mappings_install_subdir_doc_string})

if(v2ci_mappings_install_subdir)
  v2ci_install_populate_vcproj2cmake_mappings_dir("${v2ci_mappings_install_subdir}")
else(v2ci_mappings_install_subdir)
  message(STATUS "v2ci_mappings_install_subdir not set - skipping install of ${v2ci_file_type_descr}.")
endif(v2ci_mappings_install_subdir)
