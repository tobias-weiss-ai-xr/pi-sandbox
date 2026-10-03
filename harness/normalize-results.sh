#!/usr/bin/env bash
# normalize-results.sh — strip host-specific noise so probe results diff cleanly
# across hosts (Windows/Git-Bash, Linux, macOS).
#
# Volatile fields (container hostnames, kernel strings, uid/gid, file sizes,
# process counts, mount tables, disk stats) are replaced with placeholders;
# the signal (EXISTS/missing/blocked/SUCCESS/HTTP codes) is preserved.
#
# Usage:
#   bash harness/normalize-results.sh results/02-docker-recommended.txt results/02-macos-docker-recommended.txt | diff - ...
#   bash harness/normalize-results.sh results/04-*.txt
set -euo pipefail

norm() {
  sed -E \
    -e 's/^([[:space:]]*run host:).*/\1 <host>/' \
    -e 's/^([[:space:]]*uname:).*/\1 <uname>/' \
    -e 's/^([[:space:]]*ostype:).*/\1 <ostype>/' \
    -e 's/^([[:space:]]*pwd:).*/\1 <workdir>/' \
    -e 's/^([[:space:]]*workdir:).*/\1 <workdir>/' \
    -e 's/uid=[0-9]+/uid=<n>/g' \
    -e 's/gid=[0-9]+/gid=<n>/g' \
    -e 's/uid\([0-9]+\)/uid(<n>)/g' \
    -e 's/size=[0-9]+/size=<n>/g' \
    -e 's/(readable:).*/\1 <cmdline>/' \
    -e 's/visible processes: [0-9]+/visible processes: <n>/' \
    -e 's/^([[:space:]]*sample:).*/\1 <procs>/' \
    -e 's/^([[:space:]]+)[^ ]+ on \/.*/\1<mount>/' \
    -e 's/(disk free \(workdir\):).*/\1 <df>/' \
    "$@"
}

if [ "$#" -gt 0 ]; then
  for f in "$@"; do echo "### $f"; norm "$f"; done
else
  norm
fi