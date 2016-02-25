#!/bin/sh

# Small helper to update a non-linear branch
# (usually our "next" branch).
# May be symlinked in ~/bin/ for easy access.
# Usually one would probably do a git pull --ff-only,
# but since such branches are ones with non-linear history
# (for purposes of quick inter-machine sync while foregoing
# activity in "official" branches, and for quick bugfixing),
# that's not possible in that case.
# Using POSIX shell script since using Ruby does not buy us much
# (Windows git has full shell integration anyway).

set -x

git fetch || {
  echo "git fetch failed!" 1>&2
  exit 1
}

# TODO: add check which skips painful branch -m renaming
# in case the origin is up-to-date / can be ff:d.
# Perhaps it's as simple as checking exit code result
# of git pull --ff-only.

# symbolic-ref --short is not supported by git 1.7.9.5,
# thus use a hopefully more compatible sed workaround.
# http://stackoverflow.com/a/2111099
#branch="$(git symbolic-ref --short HEAD)"
branch=$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')

datestamp=$(date +%Y%m%d%H%M%S)
# Do explicitly state the source argument, too
# (probably increases safety against "issues"):
old_name="old/${branch}.${datestamp}"
git branch -m "${branch}" "${old_name}"
git tag "${old_name}" "${branch}"
git branch -D "${old_name}"
# Perhaps rather than stashing away these things one should
# do an automated commit to that old branch...
git diff --quiet || {
  echo "Found uncommitted changes - stashing..."
  git stash && need_stash_pop=1
}
git checkout "${branch}"
[ -n "${need_stash_pop}" ] && {
  echo "Restoring previously stashed uncommitted changes..."
  git stash pop
}
