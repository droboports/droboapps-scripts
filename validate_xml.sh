#!/bin/bash

# Validate droboapps_listing_2.5.2.xml

set -o errexit  # exit on uncaught error code
set -o nounset  # exit on unset variable
#set -o xtrace   # enable script tracing

usage() {
  cat << EOF

Usage: $0 path/to/xml [path/to/xsd]

Validate droboapps_listing_2.5.2.xml using an schema.

Example: $0 ./droboapps_listing_2.5.2.xml ./droboapps_listing_2.5.2.xsd

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

### start script here ###
XMLFILE="${1:-}"
XSDFILE="${2:-}"
XMLSTARLET="xmlstarlet"

# fallback to same basename
if [ -z "${XSDFILE}" ]; then
  XSDFILE="$(dirname "${XMLFILE}")/$(basename "${XMLFILE}" .xml).xsd"
fi

if [ -z "${XMLFILE}" ]; then
  log_error "missing XML file name"
  usage
  exit 1
fi

if [ ! -f "${XMLFILE}" ]; then
  log_error "file ${XMLFILE} does not exist"
  usage
  exit 2
fi

if [ ! -f "${XSDFILE}" ]; then
  log_error "file ${XSDFILE} does not exist"
  usage
  exit 2
fi

if [ ! -r "${XMLFILE}" ]; then
  log_error "file ${XMLFILE} is not readable"
  usage
  exit 3
fi

if [ ! -r "${XSDFILE}" ]; then
  log_error "file ${XSDFILE} is not readable"
  usage
  exit 3
fi

if [ "$(uname)" = "Darwin" ] && [ -x "$(dirname "$0")/xmlstarlet.osx" ]; then
  XMLSTARLET="$(dirname "$0")/xmlstarlet.osx"
elif ! which xmlstarlet 1> /dev/null; then
  log_error "xmlstarlet not found; please install"
  exit 4
fi

${XMLSTARLET} validate --xsd "${XSDFILE}" "${XMLFILE}" && rc=$? || rc=$?
if [ ${rc} -eq 0 ]; then
  log_success "XML validation passed"
else
  log_error "XML validation failed with error code ${rc}"
  exit ${rc}
fi
