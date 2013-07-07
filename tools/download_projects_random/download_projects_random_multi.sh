#!/bin/sh

set -x

for i in $(seq 1 10); do
  dat="$(date +%s)"
  dldir="${DL_DIR:-dl_projects_random.tmp}"
  mkdir "${dldir}"
  log="${dldir}/download_projects_random_${dat}.log"
  echo "Logging to ${log}"
  # Using tee would be nice, but that greatly complicates exit code handling,
  # thus choose to not do that for now...
  #./download_projects_random.rb "${dldir}" 2>&1 | tee ${log}
  ./download_projects_random.rb "${dldir}" 2>&1 > ${log}
  #ls -l "${log}"; cat "${log}"
  if [ "$?" != "0" ]; then
    echo "FAIL ${dat}"
    mv ${dldir} ${dldir}.FAIL_${dat}
  else
    mv ${dldir} ${dldir}.ok_${dat}
  fi
done
