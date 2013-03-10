#!/usr/bin/env ruby

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

# NOTE: the git calls below may FAIL
# (fatal: Not a git repository: '.git')
# in case cwd has been changed!
# Oh well, that whole handling is a hellhole,
# see context around
# http://stackoverflow.com/a/1386350
#mypwd = `pwd`; puts "pwd: #{mypwd}"

#files_changed = `git ls-files --cached --modified`.split("\n")
# http://stackoverflow.com/a/3068990
files_changed = `git diff --cached --name-only --diff-filter=ACM`.split("\n")
#puts "files_changed #{files_changed.inspect}"

REGEX_FILE_RUBY = %r{.*\.rb$}
files_ruby = files_changed.collect do |file|
  next if not file.match(REGEX_FILE_RUBY)
  file
end
files_ruby.compact!

Problematic_keyword = Struct.new(:regex, :msg)

def problem_needs_ruby_19(keyword)
  "Needs >= Ruby 1.9: #{keyword}"
end

REGEX_PROBLEMATIC = [
   Problematic_keyword.new(%r{\bstart_with\?}, problem_needs_ruby_19('String.start_with (use .match(/^.../) instead)')),
   Problematic_keyword.new(%r{\bend_with\?}, problem_needs_ruby_19('String.end_with (use .match(/...$/) instead)'))
]

files_ruby.each do |rb_file|
  IO.foreach(rb_file) do |line_raw|
    # Split off irrelevant comment parts:
    line, comment = line_raw.chomp.split('#')

    REGEX_PROBLEMATIC.each do |keyword|
      if keyword.regex.match(line)
        git_hook_fail "Found forbidden line:\n#{line}\nin file #{rb_file}: #{keyword.msg}"
      end
    end
  end
end

#git_hook_fail_pseudo

git_hook_ok "Test run of converter successful!"
