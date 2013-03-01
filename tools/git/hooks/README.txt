This directory contains some sample git hook scripts,
to be activated for your git development as desired.

Rather than creating global per-type hook files
which contain multiple different hook responsibilities (tasks)
pasted in open-coded form, I decided to create a hook scripts
launcher script per each hook type, to then launch all hooks
serially, in most frequently-failing and least-expensive to
most-expensive order.

The easiest way to activate hooks is to add symlinks pointing at the
existing committed files in this repo, to the .git/hooks/ dir.

Most hook scriptlets here should be using Ruby rather than shell script,
since Ruby is more cross-platform and, most importantly, the project
has a strong dependency on Ruby already anyway.
