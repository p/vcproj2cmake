# compat module to abstract away the fileutils / ftools unreliable
# dependency.
# fileutils not available on Ruby 1.6.8 (RHEL3),
# but ftools exists.
# fileutils is provided starting from 1.8.0 or some such.
#
# TODO: do some dynamic probing of dependency availability.
# . require 'rubygems' if RUBY_VERSION < "1.9"
# . http://stackoverflow.com/questions/6048059/how-can-i-trap-loaderror-exceptions-in-ruby-1-9-and-1-8
# . "Fixed : 2788 - ftools missing in Ruby 1.9" http://groups.google.com/group/puppet-dev/browse_thread/thread/b65958cfe0cd04a7
# . http://brettterpstra.com/gvoice-command-line-sms-revisited/
# . http://titusd.co.uk/2010/04/07/a-beginners-sinatra-tutorial/
# . http://stackoverflow.com/questions/6830510/problem-when-doing-heroku-rake-dbmigrate-to-rails-app
# . do dynamic method detection:
#   . http://stackoverflow.com/questions/5774947/get-all-local-variables-or-available-methods-from-irb
#   . http://mlomnicki.com/ruby/tricks-and-quirks/2011/01/26/ruby-tricks1.html
#   . http://stackoverflow.com/questions/175655/how-to-find-where-a-ruby-method-is-defined-at-runtime


have_ftools = true
begin
  require 'ftools'
rescue LoadError
  have_ftools = false
  require 'fileutils'
  #include FileUtils::Verbose
end


# http://wiki.ruby-portal.de/Modul

# Unfortunately it seems modules cannot include a "base" module
# (to split off common functionality into a base) -
# see http://rubylearning.com/satishtalim/modules_mixins.html
# Will thus simply make use of ftools/fileutils ternaries
# (now updated to use different module variants) for now
# until I actually know what to do...

module UtilFileCommon
  def chmod(mode, *files)
    return File.chmod(mode, *files)
  end
  module_function :chmod
end

if have_ftools
module V2C_Util_File # ftools variant
  def chmod(mode, *files)
    UtilFileCommon.chmod(mode, *files)
  end
  module_function :chmod
  def cmp(a, b)
    File.cmp(a, b)
  end
  module_function :cmp

  def mkdir_p(list)
    File.makedirs(list)
  end
  module_function :mkdir_p
  def move(from, to, verbose = false)
    File.move(from, to, verbose)
  end
  alias mv move
  module_function :mv
end
else
module V2C_Util_File # FileUtils variant
  def chmod(mode, *files)
    UtilFileCommon.chmod(mode, *files)
  end
  module_function :chmod
  def cmp(a, b)
    FileUtils.compare_file(a, b)
  end
  module_function :cmp

  def mkdir_p(list)
    FileUtils.mkdir_p(list)
  end
  module_function :mkdir_p
  def move(from, to, verbose = false)
    # Side note: FileUtils on ruby 1.9.1p429 mingw32 does not have
    # a move() alias, despite official Ruby 1.9.1 docs saying so.
    # Hmm, or perhaps it failed due to 3-param invocation with an
    # incompatible bool as 3rd param...
    FileUtils.mv(from, to)
  end
  alias mv move
  module_function :mv
end
end
