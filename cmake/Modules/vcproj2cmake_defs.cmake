# This file is part of the vcproj2cmake build converter (vcproj2cmake.sf.net)
#
# Reset common variables used by all converted CMakeLists.txt files
# (these are supposed to be defined anew by each subproject based on a
# converted CMakeLists.txt)
set(V2C_LIBS )
set(V2C_LIB_DIRS )
set(V2C_SOURCES )


macro(_v2cd_add_deprecated_standard_variable_mapping _old_var _new_var _todo_feature_removal_time)
  # Add another dummy function param, to enforce stating feature removal time :)
  # (TODO_FEATURE_REMOVAL_TIME_20xx).
  # 
  set(${_old_var} "${${_new_var}}")
endmacro(_v2cd_add_deprecated_standard_variable_mapping _old_var _new_var _todo_feature_removal_time)

macro(_v2cd_add_deprecated_cache_variable_mapping _old_var _new_var _todo_feature_removal_time)
  # Add another dummy function param, to enforce stating feature removal time :)
  # (TODO_FEATURE_REMOVAL_TIME_20xx).
  # 
  set(${_old_var} "${${_new_var}}" CACHE STRING "Automated mapping to deprecated old-style variable - please always use ${_new_var} instead." FORCE)
  # We'll NOT mark deprecated CACHE vars as advanced since a user is supposed to visibly realize that there's a problem.
  #mark_as_advanced(${_old_var})
endmacro(_v2cd_add_deprecated_cache_variable_mapping _old_var _new_var _todo_feature_removal_time)

_v2cd_add_deprecated_standard_variable_mapping(V2C_MASTER_PROJECT_DIR V2C_MASTER_PROJECT_SOURCE_DIR TODO_FEATURE_REMOVAL_TIME_2014)


set(v2c_config_dirs_default_setting cmake/vcproj2cmake)
# For these paths, we intentionally specify STRING rather than PATH (path chooser),
# since they're a semi-virtual _relative_ path _string_.
set(V2C_GLOBAL_CONFIG_RELPATH "${v2c_config_dirs_default_setting}" CACHE STRING "Relative path to vcproj2cmake-specific global content, located within the root project/solution.")
set(V2C_LOCAL_CONFIG_RELPATH "${v2c_config_dirs_default_setting}" CACHE STRING "Relative path to vcproj2cmake-specific local content, located within every sub-project")
_v2cd_add_deprecated_cache_variable_mapping(V2C_LOCAL_CONFIG_DIR V2C_LOCAL_CONFIG_RELPATH TODO_FEATURE_REMOVAL_TIME_2014)

# Add a filter variable for someone to customize in case he/she doesn't want
# a rebuild somewhere for some reason (such as having multiple builds
# operate simultaneously on a single source tree,
# thus fiddling with source tree content during build would be a big No-No
# in such case).
option(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER "Automatically rebuild converted CMakeLists.txt files upon updates on .vcproj side?" ON)

# In case automatic CMakeLists.txt rebuilds are enabled,
# should we also have an additional mechanism to abort running builds
# after re-conversion of any CMakeLists.txt files has been finished?
if(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)
  set(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD_default_setting ON)
  set(ninja_generator_name "Ninja")
  if(CMAKE_GENERATOR STREQUAL "${ninja_generator_name}")
    # Cannot use abort mechanism on Ninja currently since there's a
    # grave problem there: Ninja (at least my current git build)
    # does not care to execute subsequent targets
    # which got dirtied (i.e. to be remade) by predecessors
    # _within the same build session_ - only the following session will
    # execute it, which is not what one wants.
    # And this still seems to be the case... (should try another update soon)
    set(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD_default_setting OFF)
  endif(CMAKE_GENERATOR STREQUAL "${ninja_generator_name}")
  option(V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD "Add a force-abort target to force abort of a build run in case any CMakeLists.txt files have been automatically rebuilt?" ${V2C_CMAKELISTS_REBUILDER_ABORT_AFTER_REBUILD_default_setting})
endif(V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER)

# Global Install Enable flag, to indicate whether one wants
# to make use of pretty flexible vcproj2cmake-supplied helper functions,
# to provide installation functionality for .vcproj projects.
# We don't enable it as default setting, since the user should first get a build
# nicely running before having to worry about installation-related troubles...
set(v2c_install_enable_default_setting false)
option(V2C_INSTALL_ENABLE "Enable flexible vcproj2cmake-supplied installation handling of converted targets?" ${v2c_install_enable_default_setting})

# In case installation is allowed, should we install all targets by default?
set(V2C_INSTALL_ENABLE_ALL_TARGETS true)


# Pre-define hook include filenames
# (may be redefined/overridden by local content!)
set(V2C_HOOK_PROJECT "${V2C_LOCAL_CONFIG_RELPATH}/hook_project.txt")
set(V2C_HOOK_POST_SOURCES "${V2C_LOCAL_CONFIG_RELPATH}/hook_post_sources.txt")
set(V2C_HOOK_POST_DEFINITIONS "${V2C_LOCAL_CONFIG_RELPATH}/hook_post_definitions.txt")
set(V2C_HOOK_POST_TARGET "${V2C_LOCAL_CONFIG_RELPATH}/hook_post_target.txt")
set(V2C_HOOK_POST "${V2C_LOCAL_CONFIG_RELPATH}/hook_post.txt")
set(V2C_HOOK_DIRECTORY_POST "${V2C_LOCAL_CONFIG_RELPATH}/hook_directory_post.txt")
