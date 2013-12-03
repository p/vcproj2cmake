#!/usr/bin/env ruby

class CommandExecutionError < StandardError
  def initialize(str_cmdline, exitstatus, output)
    @str_cmdline = str_cmdline
    @exitstatus = exitstatus
    @output = output
  end
  def message
    "Command execution failed. Command line #{@str_cmdline}, exit status #{@exitstatus.to_s}, output #{@output}."
  end
end

def execute_command(arr_cmdline)
  str_cmdline = arr_cmdline.join(' ')
  puts "Executing command line #{str_cmdline}"
  output = `#{str_cmdline}`
  puts "success #{$?.success?}"
  if not $?.success?
    raise CommandExecutionError.new(str_cmdline, $?.exitstatus, output)
  end
end

script_dir_rel = File.dirname(__FILE__)
script_dir = File.expand_path(script_dir_rel)

### converter run step ###

conv_bin = File.join(script_dir, '../scripts/vcproj2cmake_recursive.rb')

cmake_source_dir = script_dir

execute_command([ conv_bin,cmake_source_dir, '2>&1' ])

cmake_build_dir = "#{cmake_source_dir}/../st.build"

def test_step_cmake_configure_run(cmake_source_dir, cmake_binary_dir, cmake_args)
  begin
    Dir.mkdir(cmake_binary_dir)
  rescue Errno::EEXIST
    # ignore it
  end
  puts "Created build root #{cmake_binary_dir}"
  exec_args = [ 'cmake' ]
  exec_args.concat(cmake_args)
  exec_args.push(cmake_source_dir)
  Dir.chdir(cmake_binary_dir) do |path|
    execute_command(exec_args)
  end
end

### CMake configure run step ###

test_step_cmake_configure_run(cmake_source_dir, cmake_build_dir, [ '-DCMAKE_BUILD_TYPE=Debug' ])

Dir.chdir(cmake_build_dir) do |path|
  # FIXME: tap into CMAKE_MAKE_PROGRAM. Could move the mechanism used by our
  # installer script into a common module.
  execute_command([ 'make' ])
  execute_command([ './projects_full/vcxproj_full_1/vcxproj_full_1' ])
end
