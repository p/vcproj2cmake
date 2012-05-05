# NOTE: this CMakeLists.txt file is NOT a "sample" file -
# its purpose is to install the actual collection of sample files
# located within this directory.

function(v2ci_install_populate_hook_files_dir _destination_dir)
  set(hook_post_filename_ "hook_post.txt")
  set(hook_project_filename_ "hook_project.txt")
  set(project_exclude_list_filename_ "project_exclude_list.txt")

  install(FILES
    "${hook_post_filename_}"
    "${hook_project_filename_}"
    "${project_exclude_list_filename_}"
    DESTINATION "${_destination_dir}"
  )
endfunction(v2ci_install_populate_hook_files_dir _destination_dir)

set(v2ci_file_type_descr "V2C sample files")

set(v2ci_samples_install_subdir_doc_string "Sub directory to install ${v2ci_file_type_descr} to")
# Pre-assign possible default setting by higher layer:
set(v2ci_samples_install_subdir "${v2ci_samples_install_subdir}" CACHE STRING ${v2ci_samples_install_subdir_doc_string})

if(v2ci_samples_install_subdir)
  v2ci_install_populate_hook_files_dir("${v2ci_samples_install_subdir}")
else(v2ci_samples_install_subdir)
  message(STATUS "v2ci_samples_install_subdir not set - skipping install of ${v2ci_file_type_descr}.")
endif(v2ci_samples_install_subdir)
