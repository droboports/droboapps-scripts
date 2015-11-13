#!/bin/bash

set -o errexit  # exit on uncaught error code
set -o nounset  # exit on unset variable
set -o xtrace   # enable script tracing

usage() {
  cat << EOF

Usage: $0 appname

Perform a simple install test of a given app.

Example: $0 python2

EOF
}

# $1: red text
# $2: additional normal text
log_error() {
  echo -e "\033[1;31mERROR: ${1}\033[0m ${2:-}" >&2
}

# $1: yellow text
# $2: additional normal text
log_warn() {
  echo -e "\033[1;33mWARNING: ${1}\033[0m ${2:-}"
}

# $1: green text
# $2: additional normal text
log_success() {
  echo -e "\033[1;32mSUCCESS: ${1}\033[0m ${2:-}"
}

# $1: cyan text
# $2: additional normal text
log_info() {
  echo -e "\033[1;36mINFO: ${1}\033[0m ${2:-}"
}

## cleanup app data
# $1: appname
_cleanup() {
  DroboApps.sh uninstall_app "$1" || true
  rm -fr "/mnt/DroboFS/Shares/DroboApps/$1"
  rm -fr "/mnt/DroboFS/Shares/DroboApps/.AppData/$1"
  rm -fr "/mnt/DroboFS/System/$1"
  rm -fr "/tmp/DroboApps/$1"
  logrotate -v -f -s /var/run/logrotate.status /etc/logrotate.conf 1>> /var/log/logrotate.log 2>&1 || true
}

## rename artifact
# $1: appname
_rename_tgz() {
  find . \( ! -regex '.*/\..*' \) -type f -mindepth 1 -maxdepth 1 -name "*.tgz" \
  | while read tgz; do
      mv "${tgz}" "$(dirname "${tgz}")/$1.tgz"
      return 0
    done
}

## copy artifact in place
# $1: appname
_copy_tgz() {
  cp -afv "$1.tgz" /mnt/DroboFS/Shares/DroboApps/
}

## collect a single log file
# $1: logfile
_collect_log() {
  if [ -f "$1" ]; then
    log_info " ### Content of $1: ###"
    cat "$1"
    log_info " ### End of $1 ### "
  else
    log_warn "Log file $1 not found"
  fi
}

## collect log files
# $1: appname
_collect_logs() {
  set +x
  _collect_log "/mnt/DroboFS/Shares/DroboApps/.servicerc"
  _collect_log "/var/log/messages"
  _collect_log "/var/log/DroboApps.log"
  _collect_log "/tmp/DroboApps/log.txt"
  _collect_log "/tmp/DroboApps/$1/log.txt"
  _collect_log "/tmp/DroboApps/$1/install.log"
  _collect_log "/tmp/DroboApps/$1/update.log"
  _collect_log "/tmp/DroboApps/$1/uninstall.log"
  set -x
  return 0
}

## tests the existence and status of a single dependency
# $1: appname
_test_depend() {
  grep "$1" "/mnt/DroboFS/Shares/DroboApps/.servicerc"
  test -d "/mnt/DroboFS/Shares/DroboApps/$1"
  test "$(/usr/bin/DroboApps.sh status_app "$1")" == "$1 is enabled and running"
}

## tests the existence and status of dependencies
# $1: appname
_test_depends() {
  local depends
  local servicesh="/mnt/DroboFS/Shares/DroboApps/$1/service.sh"

  if [ ! -f "${servicesh}" ]; then
    log_error "File missing: ${servicesh}"
    return 1
  fi

  eval "$(grep ^depends= "${servicesh}")"
  for appname in ${depends}; do
    _test_depend "${appname}"
  done
}

## perform a simple install from scratch test
# $1: appname
_test_install() {
  test "$(/usr/bin/DroboApps.sh status_app "$1")" == "$1 is not installed."
  DroboApps.sh install
  test "$(/usr/bin/DroboApps.sh status_app "$1")" == "$1 is enabled and running"

  _test_depends "$1"

  DroboApps.sh stop_app "$1"
  test "$(/usr/bin/DroboApps.sh status_app "$1")" == "$1 is disabled and stopped"

  DroboApps.sh start_app "$1"
  test "$(/usr/bin/DroboApps.sh status_app "$1")" == "$1 is enabled and running"

  "/mnt/DroboFS/Shares/DroboApps/$1/service.sh" restart
  test "$(/usr/bin/DroboApps.sh status_app "$1")" == "$1 is enabled and running"
}

_test() {
  _rename_tgz "$1"
  _copy_tgz "$1"
  _test_install "$1"
}

main() {
  _cleanup "$1"
  trap "_collect_logs $1" EXIT
  _collect_log "/mnt/DroboFS/Shares/DroboApps/.servicerc"
  _test "$1"
  _collect_logs "$1"
  trap - EXIT
  _cleanup "$1"
}

main "$@"
