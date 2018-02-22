#!/usr/bin/ruby -w

# This file is part of the vcproj2cmake build converter (vcproj2cmake.sf.net)
#

# For certain central documentation, see relevant central location (implementation files).

require 'pathname'
require 'find' # Find.find()

# http://devblog.vworkapp.com/post/910714976/best-practice-for-rubys-require

# HACK: have $script_dir as global variable currently
$script_dir = File.dirname(__FILE__)

def v2cc_load_path_extend_for_own_libs
  script_dir_lookup = $script_dir.clone

  script_dir_lookup += '/.'
  $LOAD_PATH.unshift(script_dir_lookup) unless $LOAD_PATH.include?(script_dir_lookup)
  script_dir_lookup += '/lib'
  $LOAD_PATH.unshift(script_dir_lookup) unless $LOAD_PATH.include?(script_dir_lookup)

  #puts "LOAD_PATH: #{$LOAD_PATH.inspect}\n" # nice debugging
end

v2cc_load_path_extend_for_own_libs()

require 'vcproj2cmake/v2c_core' # (currently) large amount of random "core" functionality

################
#     MAIN     #
################

script_name = $0

# Usage: vcproj2cmake.rb <input.vc[x]proj> [<output CMakeLists.txt>] [<master project directory>]

#*******************************************************************************************************
# Check for command-line input errors
# -----------------------------------
cl_error = ''

vcproj_filename = nil

if ARGV.length < 1
   cl_error = "*** Too few arguments\n"
else
   str_vcproj_filename = ARGV.shift
   #puts "First arg is #{str_vcproj_filename}"

   # Discovered Ruby 1.8.7(?) BUG: kills extension on duplicate slashes: ".//test.ext"
   # OK: ruby-1.8.5-5.el5_4.8, KO: u10.04 ruby1.8 1.8.7.249-2 and ruby1.9.1 1.9.1.378-1
   # http://redmine.ruby-lang.org/issues/show/3882
   # TODO: add a version check to conditionally skip this cleanup effort?
   vcproj_filename_full = Pathname.new(str_vcproj_filename).cleanpath
   vcproj_filename_full = vcproj_filename_full.expand_path

   $arr_plugin_parser.each { |plugin_parser_curr|
     vcproj_filename_test = obj_deep_copy(vcproj_filename_full)
     parser_extension = ".#{plugin_parser_curr.extension_name}"
     if File.extname(vcproj_filename_test) == parser_extension
       vcproj_filename = vcproj_filename_test
       break
     else
        # The first argument on the command-line did not have
        # any of the project file extensions which
        # the current parser supports.
        # If the local directory contains file "ARGV[0].<project_extension>" then use it, else error.
        # (Note:  Only '+' works here for concatenation, not '<<'.)
        vcproj_filename_test += parser_extension

        #puts "Looking for #{vcproj_filename}"
        if FileTest.exist?(vcproj_filename_test)
          vcproj_filename = vcproj_filename_test
          break
        end
     end
   }
end

if vcproj_filename.nil?
  str_parser_descrs = ''
  $arr_plugin_parser.each { |plugin_parser_named|
    str_parser_descr_elem = ".#{plugin_parser_named.extension_name} [#{plugin_parser_named.parser_name}]"
    str_parser_descrs += str_parser_descr_elem + ', '
  }
  cl_error = "*** The first argument must be the project name / file (supported parsers: #{str_parser_descrs})\n"
end

if ARGV.length > 3
   cl_error = cl_error << "*** Too many arguments\n"
end

unless cl_error == ''
   puts %{\
*** Input Error *** #{script_name}
#{cl_error}

Usage: vcproj2cmake.rb <project input file> [<output CMakeLists.txt>] [<master project directory>]

project input file can e.g. have .vcproj or .vcxproj extension.
}

   exit 1
end

# Process the optional command-line arguments
# -------------------------------------------
# FIXME:  Variables 'output_file_location' and 'master_project_dir' are position-dependent on the
# command-line, if they are entered.  The script does not have a way to distinguish whether they
# were input in the wrong order.  A potential fix is to associate flags with the arguments, like
# '-i <input.vcproj> [-o <output CMakeLists.txt>] [-d <master project directory>]' and then parse
# them accordingly.  This lets them be entered in any order and removes ambiguity.
# -------------------------------------------
output_file_location = ARGV.shift

output_dir = nil
output_filename = nil
if output_file_location
  p_output_file_location = Pathname.new(output_file_location)
  output_dir = p_output_file_location.dirname
  output_filename = p_output_file_location.basename
else
  output_dir = File.dirname(vcproj_filename)
  output_filename = CMake_Syntax_Filesystem::CMAKELISTS_FILE_NAME
end

# Master (root) project dir defaults to current dir--useful for simple, single-.vcproj conversions.
master_project_dir = ARGV.shift
if not master_project_dir
  master_project_dir = '.'
end

arr_parser_proj_files = [ vcproj_filename ]
v2c_convert_local_projects_outer(
  script_name,
  master_project_dir,
  arr_parser_proj_files,
  output_dir,
  output_filename,
  true)
v2c_convert_finished()
