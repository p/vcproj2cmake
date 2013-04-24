#!/bin/sh

set -x

for i in $(seq 1 10); do
  dat=$(date +%s)
  dldir=dl_projects_random.tmp
  mkdir "${dldir}"
  log="${dldir}/download_projects_random_${dat}.log"
  echo "Logging to ${log}"
  ./download_projects_random.rb "${dldir}" >${log} 2>&1 || {
    echo "FAIL ${dat}"
    mv ${dldir} ${dldir}.FAIL_${dat}
  }
done
