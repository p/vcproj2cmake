vcproj2cmake.rb - .vcproj/.vcxproj to CMakeLists.txt converter scripts
written by Andreas Mohr and Jesper Eskilson.
License: BSD (see LICENSE.txt)

----------
DISCLAIMER: there are NO WARRANTIES as to the suitability of this converter
(for details see LICENSE.txt), thus make sure to have suitable backup -
if things break, then you certainly get to keep both parts.
----------


=== Environment dependencies / installation requirements  ===

- working CMake installation
  CMake 2.6.x to 2.8.x recommended (vcproj2cmake has been tested
  with CMake versions in the ranges of 2.6.x to 2.8.7 only)
- Ruby
  Ruby 1.8.x to 1.9.x recommended (while some efforts have been done
  to ensure compatibility with older Ruby versions [e.g. those found on RHEL3],
  such support may be spotty)


Usage (very rough summary), with Linux/Makefile generator:
- use existing Visual Studio project source tree which contains a .vcproj file
- install vcproj2cmake environment to this source tree
- [OPTIONAL] choose suitable vcproj2cmake converter configuration:
  create a [PATH_TO_INSTALLED_VCPROJ2CMAKE]/scripts/vcproj2cmake_settings.user.rb,
  or directly modify the vcproj2cmake_settings.rb there
  (not recommended - the non-user file will be overwritten on each repository update,
  thus restoring all settings to default)
- in the project source tree, run ruby [PATH_TO_VCPROJ2CMAKE]/scripts/vcproj2cmake.rb PROJECT.vcproj
  (alternatively, execute vcproj2cmake_recursive.rb to convert an entire hierarchy of .vcproj sub projects)
- copy all required cmake/Modules, cmake/vcproj2cmake and samples (provided by the vcproj2cmake source tree!)
  to their respective paths in your project source tree
- after successfully converting the .vcproj file to a CMakeLists.txt, start your out-of-tree CMake builds:
  - mkdir ../[PROJECT_NAME].build_toolkit1_v1.2.3_unicode_debug
  - cd ../[PROJECT_NAME].build_toolkit1_v1.2.3_unicode_debug
  - ccmake -DCMAKE_BUILD_TYPE=Debug ../[PROJECT_NAME] (alternatively: cmake ../[PROJECT_NAME])
     -- NOTE that DCMAKE_BUILD_TYPE is a _required_ setting on many generators (things will break if unspecified)
  - time make -j3 -k (however I would recommend using a CMake with CMAKE_GENERATOR Ninja rather than Makefiles)

===========================================================================
Usage, easy mode:
- run install_me_fully_guided.rb or (on UNIX) install_me_fully_guided.sh
- this will interactively prompt you for everything
- ideally you will end up with a completely built CMake-enabled build tree
  of your .vc[x]proj-based source tree if everything goes fine
===========================================================================


NOTE: first thing to state is:
if you do not have any users who are hooked on keeping to use
their static .vcproj files on Visual Studio, then it perhaps makes less sense
to use our converter as a somewhat more cumbersome _online converter_ solution
- instead you may choose to go for a full-scale manual conversion
to CMakeLists.txt files (by basing your initial CMakeLists.txt layout
on the output of our script, too, of course).
That way you can avoid having to deal with the hook script includes as
required by our online conversion concept, and instead modify your
CMakeLists.txt files directly wherever needed (since _they_ will be your
authoritative project information in future on all platforms, instead of the static .vcproj files).

OTOH by using our scripts for one-time-conversion only, you will lose out
on any of the hopefully substantial further improvements done to our
online conversion script in the future,
thus it's a tough initial decision to make on whether to maintain
an online conversion infrastructure or to go initial-convert only and thus
run _all_ related developers on a CMake-based setup.



=== Installation notes ===

For more volatile vcproj2cmake parts (those which get updated frequently
by the vcproj2cmake project, such as vcproj2cmake_func.cmake
and generated CMakeLists.txt),
it is recommended to not add them to Source Control Management (SCM).
Reasons:
- version of vcproj2cmake_func.cmake etc. should remain synchronized
  with the main conversion scripts, which can only be guaranteed
  by always-installing vcproj2cmake_func.cmake etc.
- a large number of generated CMakeLists.txt files
  will needlessly clutter the source tree for non-CMake developers
Mappings files and hook files, OTOH, contain custom project-specific
persistent information and thus should find their way into SCM.

===============================================================================
Explanation of core concepts:


=== Hook script includes ===

In the generated CMakeLists.txt file(s), you may notice lines like
include(${V2C_HOOK_PROJECT} OPTIONAL)
These are meant to provide interception points ("hooks") to enhance online-converted
CMakeLists.txt with specific static content (e.g. to call required CMake Find scripts
via "find_package(Foobar REQUIRED)",
or to override some undesireable .vc[x]proj choices, to provide some user-facing
CMake setup cache variables, etc.).
One could just as easily have written this line like
include(cmake/vcproj2cmake/hook_project.txt OPTIONAL)
, but then it would be somewhat less flexible (some environments might want to
temporarily disable use of these included scripts, by changing the variable
to a different/inexistent script).
Note that these required variables like V2C_HOOK_PROJECT are pre-defined by our
vcproj2cmake_defs.cmake module.


Example hook scripts to be used by every sub project in your project hierarchy that needs
such customizations are provided in our repository's sample/ directory.


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

Original expression as used by the static Windows side (.vcproj content)
- note case sensitivity! -,
then ':' as separator between original content and CMake-side mappings,
then a platform-specific identifier (WIN32, APPLE, ...) which is used
  in a CMake "if(...)" conditional (or no identifier in case the mapping
  is supposed to be platform-universal),
then a '=' to assign the replacement expression to be used on that platform,
then the ensuing replacement expression.
Then an '|' (pipe, "or") for an optional series of additional platform conditionals.


Note that ideally you merely need to centrally maintain all mappings in your root project part
(ROOT_PROJECT/cmake/vcproj2cmake/*_mappings.txt), since sub projects will also
collect information from the root project in addition to their (optional) local mappings files.


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
projects, mentioning the _full_, _versioned_ library name.
This specific semi-redundant information, of course,
is something that Windows-side VS projects possibly don't want to have to maintain
(or, as happened in my case, are happy to remove on a whim during an upgrade).



=== Miscellaneous ===

vcproj2cmake_recursive.rb supports skipping of certain unwanted sub projects
(e.g. ones that are very cross-platform incompatible) within your
Visual Studio project tree.
This is to be done by mentioning the names of the projects to be excluded
in the file $v2c_config_dir_local/project_exclude_list.txt


=== Automatic re-conversion upon .vcproj changes ===

vcproj2cmake now contains a mechanism (added as targets to the build environment)
for _automatically_ triggered re-conversion of files
whenever the backing .vcproj file received some updates.
This is implemented in function
cmake/Modules/vcproj2cmake_func.cmake/v2c_rebuild_on_update()
This internal mechanism is enabled by default - you may modify the CMake cache variable
V2C_USE_AUTOMATIC_CMAKELISTS_REBUILDER to disable it.
NOTE: in order to have the automatic re-conversion mechanism work properly,
this currently needs the initial (manual) converter invocation
to be done from root project, _not_ any other directory (FIXME get rid of this limitation).

Since the converter will be re-executed from within the generated files (Makefile etc.),
it will convert the CMakeLists.txt that these are based on _within_ this same process.
However, it has no means to abort subsequent target execution once it notices that there
were .vc[x]proj changes which render the current CMake generator build files obsolete.
Thus, the current build instance will run to its end, and it's important to then launch
it a second time to have CMake start a new configure run with the CMakeLists.txt and
then re-build all newly modified targets.
There's no appreciable way to immediately re-build the updated configuration -
see CMake list "User-accessible hook on internal cmake_check_build_system target?".

To cleanly re-convert _all_ CMakeLists.txt in an isolated way
after a source upgrade via SCM, you may invoke target update_cmakelists_ALL,
followed by doing a full build.


=== Troubleshooting ===

- use CMake's message(FATAL_ERROR "DBG: xxx") command
- add_custom_command(... COMMENT="DBG: we are doing ${THIS} and failing ${THAT}")
- cmake --debug-output --trace

If there's compile failure due to missing includes, then this probably means that
a newly converted CMakeLists.txt still contains an include_directories() command
which lists some paths in their raw, original, Windows-specific form.
What should have happened is automatic replacement of such path strings
with a CMake-side configuration variable (e.g. ${toolkit_INCLUDE_DIR})
via a regular expression in the mappings file (include_mappings.txt).
Then CMake will consult the setting at ${toolkit_INCLUDE_DIR}
(which should have been gathered during a CMake configure run,
probably via a find_package() within one of the vcproj2cmake hook scripts
that are explained above).

If things appear to be failing left and right,
the reason might be a lack of CMake proficiency, thus it's perhaps best
to start with a new small CMake sample project
(perhaps use one of the samples on the internet) before using this converter,
to gain some CMake experience (CMake itself has a rather steep learning curve,
thus it might be even worse trying to start with a somewhat complex
and semi-mature .vc[x]proj to CMake converter).


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


=== Related projects, alternative setups ===

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
- this is said to be doable, and perhaps it can even be preferrable (would be nice
  to receive input in case anyone has particular experience in this area).


Possibly useful project to normalize file content
of the rather volatile .vcproj file format ("herding cats"):
http://www.codeproject.com/Articles/133604/Visual-C-version-7-9-vcproj-project-file-formatter


=== Off-Topic parts ===

If someone is still making use of the SCM (Source Control Management)
abomination called VSS
and contemplating migrating to a different, actually usable system,
then it may be useful to NOT default-decide to go for the "obvious" successor
(Microsoft TFS), but instead making an Informed Decision (tm) of which
capable SCM (or in fact, an integrated Tracker/Ticket environment [ALM]) to choose.
While TFS is an awful lot better than VSS, it still has some painful
shortcomings, among these:
- no three-way-merges via common base version, i.e. base-less merge
  http://jamesmckay.net/2011/01/baseless-merges-in-team-foundation-server-why/
- no disconnected SCM operation (server connection required)
- installation is a veritable PITA (e.g. due to multi-server setup for
  perfect spreading of Microsoft infrastructure lockin)
- interfacing towards much more strongly cross-platform SCMs such as SVN or git
  is h*ll (SvnBridge project rates itself as "stable" - everything but
  as of 2012... [I'm working on getting this fixed];
  git-tfs is Windows-only, or Mono-tainted untested alternative use;
  also, OpenTF hasn't seen a commit since 2008)

For a very revealing discussion with lots of experienced SCM/ALM people,
you may look at
http://jamesmckay.net/2011/02/team-foundation-server-is-the-lotus-notes-of-version-control-tools/

In short, it is strongly advisable to also check out other (possibly much more
transparently developed) ALMs such as Trac before committing to a specific product
(these environments make up a large part of your development inner loop,
thus a wrong choice will cost dearly in wasted time and inefficiency).
http://almatters.wordpress.com/2010/08/19/alm-open-source-tools-eclipse-mylyn-subclipse-trac-subversion/


While git might be an obvious cross-platform SCM candidate, Windows integration of Mercurial
probably is somewhat better.
Useful URLs:
http://mercurial.selenic.com/wiki/SourceSafeConversion
http://code.google.com/p/vss2git/
http://code.google.com/p/gitextensions/



=== Epilogue ===

Whenever something needs better explanation, just tell me and I'll try to improve it.
Dito if you think that some mechanism is poorly implemented (we're still at pre-Beta stage!).

Despite being at a semi-finished stage, the converter is now more than usable enough
to successfully build and install/package a very large project consisting of
several dozen sub projects.

Happy hacking,

Andreas Mohr <andi@lisas.de>
