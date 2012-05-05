if(NOT v2ci_scripts_plugins_install_subdir)
  set(v2ci_scripts_plugins_install_subdir "${v2ci_scripts_install_subdir}/v2c_plugins")
endif(NOT v2ci_scripts_plugins_install_subdir)

install(FILES
  v2c_parser_vs7_vcproj.rb
  DESTINATION "${v2ci_scripts_plugins_install_subdir}"
)
