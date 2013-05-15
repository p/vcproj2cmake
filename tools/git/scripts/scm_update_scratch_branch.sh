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

branch="$(git symbolic-ref --short HEAD)"

datestamp=$(date +%Y%m%d%H%M%S)
# Do explicitly state the source argument, too
# (probably increases safety against "issues"):
git branch -m "${branch}" "old.${branch}.${datestamp}"
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
