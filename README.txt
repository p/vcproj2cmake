vcproj2cmake.rb - .vcproj/.vcxproj to CMakeLists.txt converter scripts
written by Andreas Mohr and Jesper Eskilson.
License: BSD (see LICENSE.txt)

----------
DISCLAIMER: there are NO WARRANTIES as to the suitability of this converter
(for details see LICENSE.txt), thus make sure to have suitable backup -
if things break, then you certainly get to keep both parts.
----------


=== Environment dependencies / installation requirements  ===

On UNIX platforms (Linux, *BSD, Mac OS X, Solaris etc.) at least,
installing required dependencies via the standard package manager mechanism
conventions of your system/distribution is recommended.
On Mac OS X, that would mean using e.g. one of Homebrew, nix, rudix, MacPorts.

- git (for vcproj2cmake project source download)
  [once you managed to read this README this item likely is history already,
  unless you viewed this file in the SF web repository browser]
  For Windows (less recommended -  CMake support issues
  on generated VS project configurations, and less testing),
  manually installing msysgit ( Official site: http://msysgit.github.com )
  is a good choice (I successfully used it)
- CMake ( Upstream: http://www.cmake.org )
  CMake 2.6.x to 2.8.x recommended (vcproj2cmake has been tested
  with CMake versions in the ranges of 2.6.x to 2.8.10 only)
- Ruby ( Upstream: http://www.ruby-lang.org )
  Ruby 1.8.x to 1.9.x recommended: while some efforts have been done
  to frantically retain compatibility with older Ruby versions
  (e.g. those found on RHEL3), such support may easily be spotty


===========================================================================
Usage, easy mode:
- run install_me_fully_guided.rb or (on UNIX) install_me_fully_guided.sh
- this will interactively prompt you for everything
- ideally you will end up with a completely built CMake-enabled build tree
  of your .vc[x]proj-based source tree if everything goes fine
  (famous last words...)
===========================================================================

Details for manual usage (very rough summary), with Linux/Makefile generator:
- use existing Visual Studio project source tree which contains a .vcproj file
- install vcproj2cmake environment to this source tree
- [OPTIONAL] choose suitable vcproj2cmake converter configuration:
  create a [PATH_TO_INSTALLED_VCPROJ2CMAKE]/scripts/vcproj2cmake_settings.user.rb,
  or directly modify the vcproj2cmake_settings.rb there
  (not recommended - the non-user file will be overwritten on each repository update,
  thus restoring all settings to default)
- in the project source tree, run ruby [PATH_TO_VCPROJ2CMAKE]/scripts/vcproj2cmake.rb PROJECT.vcproj
  (alternatively, execute vcproj2cmake_recursive.rb to convert an entire
  hierarchy of .vcproj sub projects [parsing of .sln solution files is
  unfortunately not supported yet])
- copy all required cmake/Modules, cmake/vcproj2cmake and samples (provided by the vcproj2cmake source tree!)
  to their respective paths in your project source tree
- after successfully having converted the .vcproj file to a CMakeLists.txt,
  start your out-of-tree CMake builds:
  - mkdir ../[PROJECT_NAME].build_toolkit1_v1.2.3_unicode_debug
  - cd ../[PROJECT_NAME].build_toolkit1_v1.2.3_unicode_debug
  - ccmake -DCMAKE_BUILD_TYPE=Debug ../[PROJECT_NAME] (alternatively: cmake ../[PROJECT_NAME])
     -- NOTE that DCMAKE_BUILD_TYPE is a _required_ setting on many generators (things will break if unspecified)
  - time make -j3 -k
    (however I would recommend making use of CMake's Ninja generator -
     cmake -G Ninja - rather than generating Makefiles)


NOTE: first thing to state is:
if you do not have any users who are hooked on keeping to use
their static .vcproj files on Visual Studio, then it perhaps makes less sense
to use our converter as a somewhat more cumbersome _online converter_ solution
- instead you may choose to go for a full-scale manual conversion
to CMakeLists.txt files (probably by basing your initial CMakeLists.txt layout
on the output of our script, too, of course).
That way you can avoid having to deal with the hook script includes as
required by our online conversion concept, and instead modify your
CMakeLists.txt files directly wherever needed (since _they_ will be your
authoritative project information in future on all platforms,
instead of the static .vcproj files).

OTOH by using our scripts for one-time-conversion only, you will lose out
on any of the hopefully substantial further improvements done to our
online conversion script in the future,
thus it's a tough initial decision to make on whether to maintain
an online conversion infrastructure or to go initial-convert only and thus
run _all_ related developers on a CMake-based setup.



=== Installation notes ===

For more volatile vcproj2cmake parts (those which get updated frequently
by the vcproj2cmake project, such as vcproj2cmake_func.cmake
and generated CMakeLists.txt files),
it is recommended to *not* add them to Source Control Management (SCM).
Reasons:
- version of vcproj2cmake_func.cmake etc. should remain synchronized
  with the main conversion scripts, which can only be guaranteed
  by always-installing vcproj2cmake_func.cmake etc.
- a large number of generated CMakeLists.txt files
  will needlessly clutter the SCM working copy of non-CMake developers
Mappings files and hook files, OTOH, do contain custom project-specific
persistent information and thus should find their way into SCM.

===============================================================================
Explanation of core concepts:


=== Directory hierarchy ===

I strongly recommend having the root directory (the one
where the solution [.sln] file is usually placed) of a Visual Studio
source tree kept as an otherwise almost empty directory,
with all application and library projects then placed in *child* directories.
Not following this good convention may (will?) cause V2C conversion to break.
You might e.g. decide to aggregate this entire auto-converted
V2C sub scope from a parent-level native CMakeLists.txt infrastructure,
via add_subdirectory()).


Side note, to broaden understanding about project layout:
rather than having an overly plain project directory hierarchy
(e.g. worst case: all source files in root dir),
a useful and common in-project hierarchy looks something like this
(as used by e.g. CMake and various TFS projects):
/ [root dir]
  Build/ [project-specific build configuration files/scripts]
  Docs/
  Example/
  Source/
  Tests/ [unit tests etc.]
  Utilities/ [scripts and stuff required for this project]

(the solution file would probably be placed into the root dir)

For TFS Team Projects ($/SomeTeamProj), each such project hierarchy would
be shoved into one _sub_ directory within the Team Project
(one team may manage *multiple* projects).


=== Hook script includes ===

In the generated CMakeLists.txt file(s), you may notice lines like
include(${V2C_HOOK_PROJECT} OPTIONAL)
These are meant to provide interception points ("hooks")
to enhance online-converted CMakeLists.txt with specific static content
(e.g. to call required CMake Find scripts via "find_package(Foobar REQUIRED)",
or to override some undesireable .vc[x]proj choices, to provide some user-facing
CMake setup cache variables, etc.).
One could just as easily have written this line like
include(cmake/vcproj2cmake/hook_project.txt OPTIONAL)
, but then it would be somewhat less flexible (some environments might want to
temporarily disable use of these included scripts, by changing the variable
to a different/inexistent script).
Note that these required variables like V2C_HOOK_PROJECT are pre-defined by our
vcproj2cmake_defs.cmake module.


Example hook scripts to be used by every sub project in your project hierarchy
which happens to need such customizations
are provided in our repository's sample/ directory.

For the rather exotic case of a single CMakeLists.txt
converted from *several* project files within a *single* directory,
each hook file will be invoked for all projects.
Since it's not obvious which project() code is the one that's
currently calling the hook, it's advisable to implement manual
if(${PROJECT_NAME} STREQUAL foobar_project)
checks in such hook scripts.


== Hook scripts Best Practice ==

Well, I'm not sure whether this already deserves being called "Best
Practice", but...

Since specific hook scripts will get included repeatedly
(by multiple .vc[x]proj-based projects, possibly located in subsequent
sub directories, i.e. ending up in _same_ CMake scope!!),
it's probably a very good idea to let the initial hook script
(probably the V2C_HOOK_PROJECT one) include a _common_ CMake module file
(to be located in our custom-configured CMake module path)
which then provides CMake functions which are _generic_.
By centrally defining such common functions in this module
(and thus providing them in subsequent CMake scope),
they can then be invoked (referenced) by each hook point
(or a subsequent one!) as needed,
each time supplying project-_specific_ function variables as needed.
And since that CMake module is used only in a generic way (to define
those generic functions) and thus does _not_ dirtily fumble any project-specific
state, it is sufficient to have this _static_ content of this module
get parsed _once_ only despite actually having it include(myModule):d many times.
This can be achieved by implementing an include protection guard such as

if(my_module_parsed) # Avoid repeated parsing of this generic (non-state-modifying) function module
  return()
endif(my_module_parsed)
set(my_module_parsed true)

(with the effect of drastically shortened output of
"cmake --trace ." as executed in ${CMAKE_BINARY_DIR}).


One could continue by defining generic functions such as

adapt_my_project_target_dir(_target _subdir)

which could then be invoked via hook points
in a very project-specific way, e.g.
adapt_my_project_target_dir(foobar "${foobar_SOURCE_DIR}/doc/html")



=== mappings files (definitions, dependencies, library directories, include directories) ===

Certain compiler defines in your projects may be Win32-only,
and certain other defines might need a different replacement on a certain other platform.

Dito with library dependencies, and especially with include and library directories.

This is what vcproj2cmake's mappings file mechanism is meant to solve
(see our initial-content sample files at cmake/vcproj2cmake/include_mappings.txt etc.).


Basic syntax of mappings files is:

First original expression as used by the static Windows side (.vcproj content)
  - note case sensitivity! -,
then ':' as separator between original content and CMake-side mappings,
then a platform-specific conditional identifier (WIN32, APPLE, ...)
  which is used in a CMake "if(...)" conditional
  (or no identifier in case the mapping is supposed to apply for all
  platforms),
then a '=' to assign the replacement expression which is to be used
  on that platform,
then the ensuing replacement expression.
Then an '|' (pipe, "or") for an optional series of additional platform conditionals.


Note that ideally you merely need to centrally maintain all mappings
in your root directory (solution file?) part
(ROOT_DIR/cmake/vcproj2cmake/*_mappings.txt),
since sub projects will also collect information from the root dir settings
in addition to their (optional) local mappings files.


lib_dirs_dep_mappings.txt is a bit special in that it will translate
library _directory_ (link directory) statements
into appropriate ${YYYY_LIBRARIES} library _dependency_ variables
(or an open-coded list of libraries if the Find module does not provide a *_LIBRARIES variable),
iff(!) a matching entry can be found.
This mechanism can easily be required on Non-Windows platforms since
on Windows MSVC supports "auto-linking" (i.e., auto-discovery)
of required library dependencies via

#pragma comment(lib, ...)

lines in header files (thus it's only a library directory which needs to be specified),
whereas on Non-Windows each library needs to be explicitly listed.
See also
  http://en.wikipedia.org/wiki/Auto-linking
  [related documentation of a very popular example of auto-linking]:
  http://www.boost.org/doc/libs/1_48_0/more/getting_started/windows.html#auto-linking
  http://stackoverflow.com/questions/1875388/help-on-linking-in-gcc
  http://stackoverflow.com/questions/1685206/pragma-commentlib-xxx-lib-equivalent-under-linux
  "#pragma comment GCC equivelent" http://www.cplusplus.com/forum/general/52941/
  http://cboard.cprogramming.com/c-programming/124805-%5Bgcc%5D-specifying-include-libraries-source-files.html
  "Passing names of libraries to linker." http://gcc.gnu.org/ml/gcc-help/2005-06/msg00205.html

This sufficiently automatic and easy conversion mechanism unfortunately has certain drawbacks:
E.g. in case of Boost, it will cause linking of a target
to the _full_ list of libraries contained within ${Boost_LIBRARIES}.
If you don't want to pay this link and bloat penalty, then you will have to add each
dependency to the AdditionalDependencies (library dependency) elements in your Visual Studio
projects, mentioning the _full_, _correctly versioned_ library name.
This specific semi-redundant information, of course,
is something that Windows-side VS projects possibly don't want to have to maintain
(or, as happened in my case, are happy to unknowingly remove on a whim
during an upgrade).



=== Miscellaneous ===

vcproj2cmake_recursive.rb supports skipping of certain unwanted sub projects
(e.g. ones that are very cross-platform incompatible) within your
Visual Studio project tree.
This is to be done by mentioning the names of the projects to be excluded
in the file $v2c_config_dir_local/project_exclude_list.txt

Any CACHE variables or option()s provided by our vcproj2cmake CMake code
can have an successful preset override during the initial CMake configure run
(by imposing their initial value via cmake -D).

=== Automatic re-conversion upon .vcproj changes ===

vcproj2cmake now contains a mechanism (added as targets to the build environment)
for _automatically_ triggered re-conversion of files
whenever the backing .vc[x]proj file changed (received some updates).
This is implemented in function
cmake/Modules/vcproj2cmake_func.cmake/v2c_rebuild_on_update()
This internal mechanism is enabled by default - you may modify the user-side
CMake CACHE variable V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER to disable it.
NOTE: in order to have the automatic re-conversion mechanism work properly,
this currently needs the initial (manual) converter invocation
to be done from root dir, _not_ any other directory
(FIXME get rid of this limitation).

Since the converter will be re-executed from within the generated files
(Makefile etc.), it will convert the CMakeLists.txt that these are based on
_within_ this same process.
However, it has no means to abort subsequent target execution
once it notices that there were .vc[x]proj changes
which render the current CMake generator build files obsolete.
Thus, the current build instance will run to its end,
and it's important to then launch it a second time to have CMake start
a new configure run with the CMakeLists.txt and then re-build
all newly modified targets.
There's no appreciable way to immediately re-build the updated configuration -
see CMake list "User-accessible hook on internal cmake_check_build_system target?".

To cleanly re-convert _all_ CMakeLists.txt in an isolated way (one step)
after a source upgrade via SCM, you may invoke target update_cmakelists_ALL,
followed by doing a full build.

Unfortunately, for the case of newly deleted files of a project,
a CMake configure run as forced by a subsequent build run will error out
due to not finding the deleted file within its file list, thus there's no way
to automatically and conveniently reconvert the affected CMakeLists.txt file(s)
in this case, since the entire build environment (and especially
important targets such as update_cmakelists_ALL), is rendered non-working
until the next successful configure run. Thus in such cases the user
needs to resort to manually re-running the converter script
(e.g. vcproj2cmake_recursive.rb) again.



=== Troubleshooting ===

== vcproj2cmake conversion run issues ==

Filesystem case differences: this converter expects file statements
as listed in the VS project files to have correct case vs. the actual file
as stored in an SCM, since many platforms use case sensitive filesystems.
Thus, if there is such a problematic case difference, it needs to be corrected.
Usually that means correcting a wrong file entry in the project file,
but in some cases one will resort to fixing filename case in SCM (file rename),
and/or correcting improperly cased #include statements in source code.


== CMake configure run issues ==

- use CMake's message(FATAL_ERROR "DBG: xxx") command
- add_custom_command(... COMMENT="DBG: we are doing ${THIS} and failing ${THAT}")
- cmake --debug-output --trace


== Build run issues ==

If there's compile failure due to missing includes, then it probably means that
a newly converted CMakeLists.txt still contains an include_directories() command
which lists some paths in their raw, original, Windows-specific form.
What should have happened is automatic replacement of such path strings
with a CMake-side configuration variable (e.g. ${toolkit_INCLUDE_DIR})
via a regular expression in the mappings file (include_mappings.txt).
Then CMake will consult the setting at ${toolkit_INCLUDE_DIR}
(which should have been gathered during a CMake configure run,
probably via a find_package() within one of the vcproj2cmake hook scripts
that are explained above).

gcc compiler errors such as:

  c++: error trying to exec 'cc1obj': execvp: No such file or directory

mean that cc1obj, the compiler backend for ObjectiveC, isn't installed,
thus you should install the corresponding additional gcc packages
on your system.


If things appear to be failing left and right,
the reason might be a lack of CMake proficiency, thus it's perhaps best
to start with a new small, clean CMake sample project
(perhaps use one of the samples on the internet) before using this converter,
to gain some CMake experience (CMake itself has a rather steep learning curve,
thus it might be even worse trying to start with a somewhat complex
and semi-mature .vc[x]proj to CMake converter).


== IDE issues ==

Visual Studio handling can be quite a bitch at times.
This is especially true for e.g. project reloading prompts
and SCC (Source Control Management) integration.
While I was unable to make SCC integration work on a VS2005 <=> VSS combo
(resulting in awfully annoying nagging by VS)
despite a sizeable amount of attempts, on a VS2010 <=> TFS combo I finally
managed to figure out what broke it there:
when creating a proper out-of-tree CMake build tree as a nearby *sibling*
to the source root, it seems that the TFS workspace mapping as existing
for the source root (see e.g. tf.exe cmdline tool for details)
does *NOT* get picked up, resulting in nice SCC binding
errors on solution loading and No-Workey No-Go. This all despite our
project files containing file lists with nothing but references to files below
the source (solution) root (thus VS should have been able to figure out
that we would want to grab this mapping).
Now if we create the CMake out-of-tree build *within* (below) the source root,
then VS does finally manage to associate the workspace mapping,
resulting in a SCC integration that does appear to work correctly.
I don't know whether this was the same cause on VS2005 as well, though,
or whether there was some additional breakage there.
An interesting side note is that this issue also haunts "regular", "boring"
users of VS (e.g. CI builds being done outside of a source root
will fail to get their SCM bindings).
Possibly helpful SCC integration links:
"Working folder fiasco"
  http://social.msdn.microsoft.com/Forums/sa/tfsversioncontrol/thread/a9a34296-cae2-4c34-949a-5b40c7f74c7e
"[CMake] Source control bindings feature in CMake needs better documentation"
  http://www.cmake.org/pipermail/cmake/2011-November/047113.html


=== Installation/packaging ===

To supply sufficient installation information for the foreign-converted
projects that a main project target (e.g. a main executable) depends on,
one should probably use GetPrerequisites.cmake on this main project target;
this lists all sub project targets already and allows to install them
from a global configuration part.

However, since this probably won't be sufficient in many cases,
there's now a new pretty flexible yet hopefully very easily usable
v2c_target_install() helper in cmake/Modules/vcproj2cmake_func.cmake.
For specific information on how to enable its use and configuration fine-tuning,
see the function comments within that file.


=== Precompiled header (PCH) support ===

V2C now includes some initial support for existing precompiled header
configurations (MSVC, gcc, etc.).
This PCH functionality has been taken from "Support for precompiled headers"
  http://www.cmake.org/Bug/view.php?id=1260
(vcproj2cmake can now be considered inofficial "upstream"
of this functionality, since there probably is nobody else
who's actively improving the module file)
Please note that IMHO precompiled headers are not always a good idea.
See http://gcc.gnu.org/wiki/PCHHaters
and "Precompiled Headers? Do we really need them" reply at
  http://stackoverflow.com/a/1138356
for a good explanation.
PCH may become a SPOF (Single Point Of Failure) for some of the more chaotic
projects (libraries), namely those which fail to have a clear mission
and try to implement / reference the entire universe
(throwing together spaghetti code which handles file handling / serialization,
threading, GUI layout, string handling, algorithms, communication, ...).
Consequently such a project ends up including many different large toolkits
in its main header, causing all source files to include that monster header
despite only needing a tiny subset of that functionality each.
Admittedly this is the worst case (which should be avoidable),
but it does happen and it's not pretty.

Not to mention that PCH frequently shadow proper dependency tracking of
the headers that they include (to show that this is a more prominent
problem: none of the 3 assorted-mixed-up public CMake PCH support modules
currently offers proper rebuilds on include change!).
See e.g.
http://connect.microsoft.com/VisualStudio/feedback/details/704753/visual-studio-does-not-rebuild-precompiled-file-when-headers-change
"MSBuild Does Not Detect Changes in Precompiled Headers"
http://social.msdn.microsoft.com/Forums/en-US/msbuild/thread/1adbe5a0-88de-4b33-ba39-6e4d1e33502c/

Note that on VS2010, for /MP (multi-processor) builds in combination with
using #import directives, using PCH appears to be necessary
since using #import in standalone header files instead
may cause a race condition between multiple build units
building the interface parts.
Chalk that up to an insufficient target dependency chain configured in their
build infrastructure.
The possibly best workaround against that race is to move all use of #import
into PCHs, thereby (ab)using the standard PCH build order guards
to ensure that nobody else will process the #import parts in parallel.


=== Related projects, alternative setups ===

CMake's builtin command: include_external_msproject().
This one is MSVC-only, quite obviously.


sln2mak (.sln to Makefile converter), http://www.codeproject.com/KB/cross-platform/sln2mak.aspx

I just have to state that we have a very unfair advantage here:
while this script implementation possibly might be better
than our converter (who knows...), the fact that we are converting
towards CMake (and thus to a whole universe of supported build environments
/IDEs via CMake's generators) probably renders any shortcomings
that we might have rather very moot.
Plus, sln2mak is C#-based (requiring an awkwardly _disconnected_ conversion
of Non-Windows-targeted build settings on a Windows box),
whereas vcproj2cmake is a fully cross-platform-deployable (Ruby) converter.


A completely alternative way of gaining cross-platform builds
other than making use of CMake via vcproj2cmake
may be to stay within proprietary .vcproj / Visual Studio realms
and to implement a cross-compiler setup
- this is said to be doable, and perhaps it can even be preferrable
  (would be nice to receive input in case anyone has particular experience
   in this area).
Jam is said to possibly be a helpful tool in such case,
since it can be deployed as a custom build command in a Visual Studio project config (and in several other IDEs, too).
However, some people say that Jam has the appearance of being very easy,
yet once you start doing more elaborate things it can get very hard
rather quickly. Who knows... (any feedback?).


http://sourceforge.net/projects/folders4cmake/
This one seems rather interesting since it does things the other way around
as compared to vcproj2cmake:
it seems to be a Visual-Studio-side plugin which then generates a CMake
file list gathered from VS file filters setup.
Given an existing CMake framework where one then simply plugs in the
custom-generated file lists, this might be much more workable than expected,
and possibly superiour to the vcproj2cmake configuration effort in certain ways.
Untested, however (any feedback?).


https://github.com/sakra/cotire/ (compile time reducer)
is a CMake module that speeds up the build process of CMake based build systems
by fully automating techniques as precompiled header usage
and single compilation unit builds for C and C++.


Possibly useful project to normalize file content
of the rather volatile .vcproj file format ("herding cats"):
http://www.codeproject.com/Articles/133604/Visual-C-version-7-9-vcproj-project-file-formatter


https://github.com/Vairn/vcxproj2cmake (or other related forks at github)
Perl-based converter. Unfortunately not very powerful yet as of end-2012.


=== Project development notes ===

Important/useful git settings include:

$ git config --global user.name "John Doe"
$ git config --global user.email johndoe@example.com
$ git config --global color.ui true
$ git config --global core.editor vim
Windows: $ git config core.autocrlf true
Non-Windows: $ git config core.autocrlf input
I think we want NON-tab indenting in any case
(even though an argument could be made for doing tab-based development,
since *one* tab would directly translate into *one* indent step,
with actual representation in number of spaces per tab
dynamically configurable in editors),
since Ruby indenting conventions definitely seem to be two spaces,
and indenting for a new scope while allowing/requesting
tab as replacement of 8-ws parts would lead to problems:
$ git config core.whitespace trailing-space,space-before-tab,tab-in-indent,cr-at-eol [not yet entirely sure about this one]
(and preferably do a git diff --check prior to committing/pushing)
$ git config --global rebase.autosquash true
$ git config receive.fsckObjects true


=== Cross-platform development hints ===

== Toolkit dependency management/reduction ==


In order to achieve eventually getting a large heavily Win32/MFC-based solution
into a sufficiently cross-platform-compatible state,
it is advisable to configure all Visual Studio projects to use
the most strict platform settings that are currently possible,
to avoid having other people let unwanted dependencies (MFC, ATL) creep in.
I.e. for (almost?) Win32-only projects, do configure a Win32 setting
(and prefer SubSystem Console rather than Windows),
for Non-Win32 projects (possibly some toolkits have a strictly
POSIX-only interface, thus a corresponding user-side project
is able to consist of POSIX-only parts, too),
try to setup a POSIX-only setting (this is not openly documented,
but I believe it's possible; see e.g. .vcxproj SubSystem element or some such).
Indeed, SubSystem values are listed as Console, Windows, Native, EFI Application, EFI ROM, EFI Runtime, WindowsCE, POSIX
(MSVC /SUBSYSTEM: does have a POSIX flag; however KB308259 says that POSIX
subsystem has been deprecated in XP).
You really don't want to have the unbelievably bloated windows.h header
to be reachable by default within a project wherever it can be avoided...

In addition to this, it might be useful to do checks for certain defines
(e.g. include guard defines) in header files which are strongly indicative
of certain unwanted toolkit dependencies, and in case of encountering
such a define to bail out of compilation, hard.


=== Off-Topic parts ===

If someone is still making use of the SCM (Source Control Management)
abomination called VSS
and contemplating migrating to a different, actually usable system,
then it may be useful to NOT default-decide to go for the "obvious" successor
(Microsoft TFS), but instead making an Informed Decision (tm) of which
capable SCM (or in fact, an integrated Tracker/Ticket environment [ALM]) to choose.
While TFS is an awful lot better than VSS, it still has some painful
shortcomings, among these:
- non-cross-platform tool
  --> inescapable (hard) dependency on non-performant Windows servers
     --> filename case sensitivity issue (certain TFS 2008 API functions
	return *other* case insensitive results for *different* case sensitive input)
- no three-way-merges via common base version, i.e. base-less merge
  http://jamesmckay.net/2011/01/baseless-merges-in-team-foundation-server-why/
- no disconnected SCM operation (server connection required;
  server is managing client state on server side
  [and BTW their solution of working "disconnected" is annoyingly cumbersome
  at both disconnecting *and* reconnecting ops])
- installation is a veritable PITA (e.g. due to multi-server setup for
  perfect spreading of Microsoft infrastructure lockin)
- interfacing towards much more strongly cross-platform SCMs such as SVN or git
  is h*ll:
  - SvnBridge project rates itself as "stable" - everything but
    as of 2012... (I'm working on getting this fixed -
    with my public patch applied it's much improved now)
  - git-tfs requires installation on a Windows server as well,
    or Mono-tainted untested alternative use
  - the "new" second git-tfs project (Java-based) that was just released
    probably hasn't seen much use yet (TODO: determine actual status)
  - also, OpenTF hasn't seen a commit since 2008
- astonishing stability issues
  - a work item tracking exception occurring in server layers
    that was caused by one client will cause (TFS2008):
    a) the server to not handle the NullPtrException in a benign way
       (no client input whatsoever should ever cause a server to croak, ideally ["INPUT VALIDATION"])
    b) several *other*, *unrelated* VS clients which happen to have ongoing TFS transmissions to be affected by this single-client server session failure (WTH?)
    c) those other clients to *not* handle this failure in a benign way
       (final failure due to simply locking up as an entirely inadequate
        "handling" of this problem that originated on the side of the server)
    --> whoa, triple FAIL!! This behaviour is surely being acerbated
        by the fact that TFS is a centralized (non-disconnected operation)
        lock-in type infrastructure
  - a merge operation of two almost identical text-only header files
    on TFS2008 sometimes causes the result to end up with embedded NULs
    (read: corrupted, for many purposes - type changed from text to binary!),
    despite both original blobs emphatically NOT containing any embedded NUL
    [quite likely the root cause is a string handling off-by-1 in
    TFS's merge code!]

For a very revealing discussion with many experienced SCM/ALM people,
you may look at
http://jamesmckay.net/2011/02/team-foundation-server-is-the-lotus-notes-of-version-control-tools/

In short, it is strongly advisable to also check out other (possibly much more
transparently developed) ALM solutions such as Trac, Jira, Polarion
before committing to a specific product
(these environments make up a large part of your team's development inner loop,
thus a wrong choice will cost dearly in wasted time and inefficiency).
http://almatters.wordpress.com/2010/08/19/alm-open-source-tools-eclipse-mylyn-subclipse-trac-subversion/


While git might be an obvious cross-platform SCM candidate,
Windows integration of Mercurial probably is somewhat better.
Useful URLs:
http://mercurial.selenic.com/wiki/SourceSafeConversion
http://code.google.com/p/vss2git/
http://code.google.com/p/gitextensions/



=== Epilogue ===

Whenever something needs better explanation, just tell me
and I'll try to improve it (I'm constantly rewording many parts of this README).
Dito if you think that some mechanism is poorly implemented (we're still at pre-Beta stage!).

Despite being at a semi-finished stage, the converter is now more than usable enough
to successfully build and install/package a very large project
consisting of many dozen sub projects.

Happy hacking,

Andreas Mohr <andi@lisas.de>
