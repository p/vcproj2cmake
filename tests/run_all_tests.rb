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
  #puts "Executing command line #{str_cmdline}"
  output = `#{str_cmdline}`
  if not $?.success?
    raise CommandExecutionError.new(str_cmdline, $?.exitstatus, output)
  end
end

script_dir_rel = File.dirname(__FILE__)
script_dir = File.expand_path(script_dir_rel)

conv_bin = File.join(script_dir, '../scripts/vcproj2cmake_recursive.rb')

cmake_source_dir = script_dir

output_convert = `#{conv_bin} #{cmake_source_dir} 2>&1`

if not $?.success?
  test_failed_st_reason = "script indicated failure (exit code: #{$?.exitstatus})"
end

cmake_build_dir = "#{cmake_source_dir}/../st.build"
begin
  Dir.mkdir(cmake_build_dir)
rescue Errno::EEXIST
  # ignore it
end

Dir.chdir(cmake_build_dir) do |path|
  execute_command([ 'cmake', '-DCMAKE_BUILD_TYPE=Debug', cmake_source_dir ])
  # FIXME: tap into CMAKE_MAKE_PROGRAM. Could move the mechanism used by our
  # installer script into a common module.
  execute_command([ 'make' ])
  execute_command([ './projects_full/vcxproj_full_1/vcxproj_full_1' ])
end
