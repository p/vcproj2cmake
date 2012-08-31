# NOTE: this CMakeLists.txt file is NOT a "sample" file -
# its purpose is to install the actual collection of sample files
# located within this directory.

# Provide a switch for installation of samples.
# The default setting will definitely be OFF -
# these samples might end up overwriting existing custom files
# in a user's project otherwise...
set(v2ci_install_samples_default_setting OFF)
option(v2ci_install_samples "Install sample files (project hooks, ...), too? MAY OVERWRITE POSSIBLY EXISTING CUSTOMIZED FILES." ${v2ci_install_samples_default_setting})
if(NOT v2ci_install_samples)
  return()
endif(NOT v2ci_install_samples)

function(v2ci_install_populate_hook_files_dir _destination_dir _component)
  set(hook_post_filename_ "hook_post.txt")
  set(hook_project_filename_ "hook_project.txt")
  set(project_exclude_list_filename_ "project_exclude_list.txt")

  set(v2ci_samples_files_install_list_
    "${hook_post_filename_}"
    "${hook_project_filename_}"
    "${project_exclude_list_filename_}"
  )
  install(FILES
    ${v2ci_samples_files_install_list_}
    DESTINATION "${_destination_dir}"
    COMPONENT "${_component}"
  )
endfunction(v2ci_install_populate_hook_files_dir _destination_dir _component)

set(v2ci_file_type_descr "V2C hook files")

set(v2ci_samples_install_subdir_doc_string "Sub directory to install ${v2ci_file_type_descr} to")
# Pre-assign possible default setting by higher layer:
set(v2ci_samples_install_subdir "${v2ci_samples_install_subdir}" CACHE STRING ${v2ci_samples_install_subdir_doc_string})

if(v2ci_samples_install_subdir)
  if(NOT samples_component) # Specified by parent layer?
    set(samples_component "Hooks_Files_Samples")
  endif(NOT samples_component)
  #cpack_add_component("${samples_component}" DESCRIPTION "Sample ${v2ci_file_type_descr} (per-project() hooks)")
  v2ci_install_populate_hook_files_dir("${v2ci_samples_install_subdir}" "${samples_component}")
else(v2ci_samples_install_subdir)
  message(STATUS "v2ci_samples_install_subdir not set - skipping install of ${v2ci_file_type_descr}.")
endif(v2ci_samples_install_subdir)
