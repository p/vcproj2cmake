#!/usr/bin/ruby

# Q&D downloader -
# downloads a random selection of .vcproj/.vcxproj files from Google Search.
# Extremely useful for stress testing of the converter.

require 'nokogiri'
require 'open-uri'

require 'find'

def url_liberate_from_google(href_raw)
  href = href_raw
  #puts "HREF #{href_raw}"
  href = href_raw.sub(%r{\/url\?q=(.*?)\&.*?=.*}, '\1')
  #puts "href #{href}"
  href
end

# Helper to try to ensure as best as we can
# that we always hit a "blob" URL
# rather than some kind of undesired HTML content URL
# ("augmented" file view, diff, ...).
def url_transform_to_blob_variant(url)
  if url.match(/^https:\/\/github\.com/) or url.match(/\/gitlab\//)
    url = url.sub(%r{\/blob\/}, '/raw/')
  end
  if url.match(/^https:\/\/bitbucket\.org/)
    url = url.sub(%r{\/src\/}, '/raw/')
  end
  if url.match(/^http:\/\/gitorious\.org/)
    url = url.sub(%r{\/blobs\/}, '/blobs/raw/')
  end
  # http://sourceforge.net/apps/trac/mpc-hc/changeset/3213/trunk/src/apps/mplayerc/mpcresources/mpcresources.vcxproj
  # http://trac.mysvn.ru/ghazan/myranda/changeset/1990/trunk/plugins/AVS/avs_10.vcxproj
  # http://iguanaworks.net/projects/IguanaIR/changeset/714/tags/software/usb_ir-0.30/win32/usb_ir.vcproj
  # http://eraser.heidi.ie/trac/browser/tags/6.0.6.1376/Eraser.Util.Unlocker/Eraser.Util.Unlocker.vcproj
  is_trac = (url.match(/^http:\/\/sourceforge\.net.*\btrac\b/) || url.match(/\btrac\b/) || url.match(/\bchangeset\b.*\b(trunk|tags)\b/))
  if is_trac
    url = url.sub(%r{\/changeset\/}, '/export/')
    url = url.sub(%r{\/browser\/}, '/export/HEAD/')
  end
  # https://hg.splayer.org/splayer/src/e8ee4613a0ce638c3d5eb474c2b160f0ec61f135/src/apps/mplayerc/mplayerc_vs2005.vcxproj
  if url.match(/^https:\/\/hg/)
    url = url.sub(%r{\/src\/}, '/raw/')
  end
  if url.match(/^sourceforge.jp/)
    url = url + '?export=raw'
  end
  # https://www.veracrypt.fr/code/VeraCrypt/tree/src/Mount/Mount.vcxproj
  if url.match(/\/code\/.*\/tree\//)
    url = url.sub(%r{\/tree\/}, '/plain/')
  end
  if url.match(/\/raw-annotate\//)
    url = url.sub(%r{\/raw-annotate\/}, '/raw-file/')
  end
  # With 'diff' it's quite likely that we will not get
  # an actual raw blob download --> skip it!!
  # (unless for certain sites we *are* able to transform it somehow)
  if url.match(/\/diff\//)
    url = ''
  end
  url
end

# Get a Nokogiri::HTML:Document for the page we're interested in...

ARR_FILETYPES = [
  'vcxproj',
  'vcproj',
  'csproj'
]

i = rand(ARR_FILETYPES.length)
filetype = ARR_FILETYPES[i]
randomize_search_arg = rand(2000).to_s

google_search_url = "http://www.google.com/search?as_q=#{randomize_search_arg}&q=filetype:#{filetype}"

puts "Querying #{google_search_url}"

doc = Nokogiri::HTML(open(google_search_url))

# Do funky things with it using Nokogiri::XML::Node methods...

#puts "doc: #{doc.inspect}"

arr_urls = []

####
# Search for nodes by css
doc.css('h3.r').each do |link|
  #puts "LINK #{link.inspect}"
  link.children.each do |child|
    if child.name == 'a'
      #puts "CHILD: #{child.inspect}"
      # Nokigiri XML attribute gets yielded as
      # pair of name ("href") and content (name, href, ...).
      child.attributes.each do |name, content|
        #puts "name #{name}, content #{content}"
        if name == 'href'
          href_google = content
          str_href_google = "#{href_google}"
          href = url_liberate_from_google(str_href_google)
          href = url_transform_to_blob_variant(href)
          if not href.empty?
            arr_urls.push(href)
          end
        end
      end
      #puts "value: #{child.value}"
    end
  end
  #puts "LINK: #{link.inspect}"
  #puts "value: #{link.value}"
end

def get_vcproj2cmake_root_dir
  repo_root = `git rev-parse --show-toplevel`.chomp()
  if not $?.success?
    # Hmm, currently not in a git repo?
    # Try figuring out the root manually...
    dir_prefix = ''
    3.times do
      dir_prefix += '../'
      if File.exist?(dir_prefix + 'install_me_fully_guided.rb')
        # absolute or relative path... doesn't matter, right? :)
        repo_root = dir_prefix
        break
      end
    end
  end
  repo_root
end

def download_urls_into_prefixed_dirs(arr_urls, dir_prefix)
  dirpref = "#{dir_prefix}_"
  arr_dl = []
  download_cmd = 'wget'
  arr_dl.push(download_cmd)
  arr_dl.push('--timeout=10')
  arr_dl.push('-t 2')
  download_cmd_cert='--no-check-certificate'
  arr_dl.push(download_cmd_cert)
  i = 1
  arr_urls.each do |url|
    # TODO: while we cannot do direct parallelization
    # since we download to different dirs,
    # actually forking multiple processes
    # might actually be worthwhile.
    dir_projfiles_specific = dirpref + i.to_s
    begin
      Dir.mkdir(dir_projfiles_specific)
    rescue Errno::EEXIST
    end
    Dir.chdir(dir_projfiles_specific) do
      download_cmd_full = arr_dl.join(' ') + ' ' + '"' + url + '"'
      puts "Executing #{download_cmd_full}"
      `#{download_cmd_full}`
    end
    i += 1
  end
end

REGEX_PROJ = %r{\.(vcproj|vcxproj|csproj)$}
def find_project_files(proj_root)
  arr_projs = []
  Find.find(proj_root) do |f|
    next if not File.file?(f)
    if f.match(REGEX_PROJ)
      arr_projs.push(f)
    end
  end
  arr_projs
end

REGEX_DOCTYPE_HTML = /\bDOCTYPE\b\s*\bhtml\b/i
REGEX_CONTENT_TYPE_HTML = %r{\bContent-Type\b.*\bcontent\b.*\bhtml\b}
ARR_REGEX_BROKEN_FILE = [
  REGEX_DOCTYPE_HTML,
  REGEX_CONTENT_TYPE_HTML
]
def detect_broken_files(arr_projs)
  arr_broken = arr_projs.collect do |proj_file|
    ok = true
    open(proj_file) do |f|
      begin
        ARR_REGEX_BROKEN_FILE.each do |regex|
          result = f.grep(regex)
          if not result.empty?
            puts "project file #{proj_file} is BROKEN (regex #{regex}, result #{result})"
            ok = false
            break
          end
        end
      rescue Exception => e
        if e.message.match(/^invalid byte sequence/)
          # OK, we've got a dilemma here:
          # This is probably caused by evaluating non-UTF-8 content as UTF-8.
          # While the XML parser would properly support various encodings,
          # a simple UTF-8 text grep will bail. Thus indicate success,
          # to try to have the converter convert the file properly.
          # The clean solution would be to use existing helpers in the converter.
          ok = true
        else
          raise
        end
      end
    end
    next if ok
    proj_file
  end
  arr_broken.compact!
  arr_broken
end

def move_away_broken_project_files(proj_root, safe_stash_dir)
  arr_projs = find_project_files(proj_root)
  arr_broken = detect_broken_files(arr_projs)
  return if arr_broken.empty?
  begin
    Dir.mkdir(safe_stash_dir)
  rescue Errno::EEXIST
  end
  arr_broken.each do |proj_file|
    basename = File.basename(proj_file)
    dest = File.join(safe_stash_dir, basename)
    puts "Moving away BROKEN project file #{proj_file} to #{dest}"
    File.rename(proj_file, dest)
  end
end

skip_download = false
#skip_download = true # TESTING

dir_projfiles_root = 'dl_projects_random.tmp'
if not skip_download
  rm_is_safe = (dir_projfiles_root.length > 5)
  if rm_is_safe
    `rm -r #{dir_projfiles_root}`
  end
end
begin
  Dir.mkdir(dir_projfiles_root)
rescue SystemCallError
  puts "#{dir_projfiles_root} already existing!?"
end
Dir.chdir(dir_projfiles_root) do
  if not skip_download
    download_urls_into_prefixed_dirs(arr_urls, filetype)
  end
  # We do want the converter to fail hard on invalid input files -
  # however for this downloader we do NOT want to encounter such cases,
  # all input files should be legitimate.
  move_away_broken_project_files('./', '../broken_project_files')
  puts "Download finished - launching converter..."
  repo_root = get_vcproj2cmake_root_dir()
  if repo_root.empty?
    puts "ERROR: could not figure out vcproj2cmake root dir!"
    exit(1)
  end
  output = `#{repo_root}/scripts/vcproj2cmake_recursive.rb .`
  if $?.success?
     puts "Converter finished successfully!"
  else
    puts "Conversion of project files below #{dir_projfiles_root} FAILED!"
    exit $?.exitstatus
  end
end
