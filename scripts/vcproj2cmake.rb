#!/usr/bin/ruby -w

# Given a Visual Studio project (.vcproj, .vcxproj),
# create a CMakeLists.txt file which optionally allows
# for ongoing side-by-side operation (e.g. on Linux, Mac)
# together with the existing static .vc[x]proj project on the Windows side.
# Provides good support for simple DLL/Static/Executable projects,
# but custom build steps and build events are currently ignored.

# Author: Jesper Eskilson
# Email: jesper [at] eskilson [dot] se
# Author 2: Andreas Mohr
# Email: andi [at] lisas [period] de
# Large list of extensions:
# list _all_ configuration types, add indenting, add per-platform configuration
# of definitions, dependencies and includes, add optional includes
# to provide static content, thus allowing for a nice on-the-fly
# generation mode of operation _side-by-side_ existing and _updated_ .vcproj files,
# fully support recursive handling of all .vcproj file groups (filters).

# If you add code, please try to keep this file generic and modular,
# to enable other people to hook into a particular part easily
# and thus keep any additions specific to the requirements of your local project _separate_.

# TODO/NOTE:
# Always make sure that a simple vcproj2cmake.rb run will result in a
# fully working almost completely _self-contained_ CMakeLists.txt,
# no matter how small the current vcproj2cmake config environment is
# (i.e., it needs to work even without a single specification file
# other than vcproj2cmake_func.cmake)
#
# Useful check: use different versions of this project, then diff resulting
# changes in generated CMakeLists.txt content - this should provide a nice
# opportunity to spot bugs which crept in from version to version.
#
# Tracing (ltrace -s255 -S -tt -f ruby) reveals that overall execution time
# of this script horribly dwarfs ruby startup time (0.3s vs. 1.9s, on 1.8.7).
# There's nothing much we can do about it, other than making sure to
# only have one Ruby process (avoid a huge number of wasteful Ruby startups).

# TODO:
# - perhaps there's a way to provide more precise/comfortable hook script handling?
# - possibly add parser or generator functionality
#   for build systems other than .vcproj/.vcxproj/CMake? :)
# - try to come up with an ingenious way to near-_automatically_ handle
#   those pesky repeated dependency requirements of several sub projects
#   (e.g. the component-based Boost Find scripts, etc.) instead of having to manually
#   write custom hook script content (which cannot be kept synchronized
#   with changes _automatically_!!) each time due to changing components and libraries.

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
     vcproj_filename_test = vcproj_filename_full.clone
     parser_extension = ".#{plugin_parser_curr.extension_name}"
     if File.extname(vcproj_filename_test) == parser_extension
       vcproj_filename = vcproj_filename_test
       break
     else
        # The first argument on the command-line did not have any the project file extension which the current parser supports.
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
  output_filename = CMAKELISTS_FILE_NAME
end

# Master (root) project dir defaults to current dir--useful for simple, single-.vcproj conversions.
master_project_dir = ARGV.shift
if not master_project_dir
  master_project_dir = '.'
end

arr_parser_proj_files = [ vcproj_filename ]
v2c_convert_local_projects_outer(script_name, master_project_dir, arr_parser_proj_files, output_dir, output_filename)
v2c_convert_finished()
