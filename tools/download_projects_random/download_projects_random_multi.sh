#!/bin/sh

set -x

for i in $(seq 1 10); do
  dat=$(date +%s)
  log=/tmp/download_projects_random_${dat}.log
  echo "Logging to ${log}"
  ./download_projects_random.rb >${log} 2>&1 || {
    echo "FAIL ${dat}"
    dldir=dl_projects_random.tmp
    mv ${dldir} ${dldir}.FAIL_${dat}
  }
done