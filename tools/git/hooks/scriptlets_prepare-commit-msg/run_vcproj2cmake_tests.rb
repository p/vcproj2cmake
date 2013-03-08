#!/usr/bin/env ruby

def git_hook_get_repo_root()
  `git rev-parse --show-toplevel`.chomp
end

def git_hook_fail(msg)
  puts "#{$0}: #{msg}"
  exit 1
end

# For testing (to keep content repeatedly committable rather than committing it)
def git_hook_fail_pseudo()
  git_hook_fail("Pseudo failure, for testing")
end

def git_hook_ok(msg)
  puts "#{$0}: #{msg}"
  # NO exit here!
end

git_repo_root_dir = git_hook_get_repo_root()

tests_dir = "#{git_repo_root_dir}/tests/st"

converter_bin = "#{git_repo_root_dir}/scripts/vcproj2cmake_recursive.rb"

# Simply run vcproj2cmake_recursive.rb and let its exit code
# decide whether to fail the git hook.
# TODO: should probably create test scripts specific to (within) that area,
# which are then responsible for doing a clean reproducible test run each.

pwd_prev = Dir.pwd
Dir.chdir(tests_dir)
output = `#{converter_bin} . 2>&1`

test_failed_st_reason = nil
if not $?.success?
  test_failed_st_reason = "script indicated failure (exit code: #{$?.exitstatus})"
end

Dir.chdir(pwd_prev)

if not test_failed_st_reason.nil?
  git_hook_fail(test_failed_st_reason)
end

#puts "OUTPUT IS: #{output}"

Problematic_keyword = Struct.new(:regex, :msg)

RUBY_WARNING_MARKER = ': warning: '
REGEX_PROBLEMATIC = [
  Problematic_keyword.new(%r{#{RUBY_WARNING_MARKER}}, 'Warning generated by Ruby')
]

REGEX_OK = [
  %r{#{RUBY_WARNING_MARKER}.*\bdefault_dir\b},
  %r{#{RUBY_WARNING_MARKER}.*\bdefault_bindir\b},
]

def git_ruby_output_whitelist(candidate)
  REGEX_OK.each do |regex|
    return true if regex.match(candidate)
  end
  false
end

# On successful run, check whether content was suspicious:
output.split("\n").each do |line|
  REGEX_PROBLEMATIC.each do |keyword|
    if keyword.regex.match(line)
      # Some parts are legitimate
      # (e.g. warnings due to system-originating code parts)
      if not git_ruby_output_whitelist(line)
        git_hook_fail "Test run of converter #{converter_bin} below #{tests_dir} failed - found forbidden line (#{keyword.msg}):\n#{line}"
      end
    end
  end
end

#git_hook_fail_pseudo

git_hook_ok "Test run of converter successful!"