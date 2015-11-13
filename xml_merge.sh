#!/bin/bash

set -o errexit  # exit on uncaught error code
set -o nounset  # exit on unset variable
#set -o xtrace   # enable script tracing

usage() {
  cat << EOF

Usage: $0 appname...

Merge the information for each of the given apps from the XML file in the
staging FTP server in the XML file from the production FTP server.

Example: $0 apache python2 perl5

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

# list of apps to merge
APPLIST="$@"
# use xml tools by default
XMLSTARLET=1
XML=xmlstarlet

if [ -z "${APPLIST}" ]; then
  log_error "missing app list; printing usage and exiting"
  usage
  exit 1
fi

if [ "$(uname)" = "Darwin" ] && [ -f "$(dirname "$0")/xmlstarlet.osx" ]; then
  XML="$(dirname "$0")/xmlstarlet.osx"
elif ! which xmlstarlet 1> /dev/null; then
  log_warn "xmlstarlet not found; falling back to grep/sed"
  XMLSTARLET=0
fi

PRODUCTION_URL="ftp://166.78.35.9/droboapps/2.1/droboapps_listing_2.5.2.xml"
STAGING_URL="ftp://12.205.168.80/droboapps/2.1/droboapps_listing_2.5.2.xml"
PRODUCTION_XML="production.xml"
STAGING_XML="staging.xml"
RESULT_XML="droboapps_listing_2.5.2.xml"
rc=0

if [ ! -f "${STAGING_XML}" ]; then
  log_info "Downloading ${RESULT_XML} from staging (10 second timeout)"
  curl --max-time 10 --output "${STAGING_XML}" "${STAGING_URL}" && rc=$? || rc=$?
  if [ ${rc} -ne 0 ]; then
    log_error "Unable to download ${RESULT_XML} from staging;" "error code ${rc}"
    exit ${rc}
  fi
else
  log_info "Using local copy of ${STAGING_XML}"
fi
if [ ! -f "${PRODUCTION_XML}" ]; then
  log_info "Downloading ${RESULT_XML} from production (10 second timeout)"
  curl --max-time 10 --output "${PRODUCTION_XML}" "${PRODUCTION_URL}" && rc=$? || rc=$?
  if [ ${rc} -ne 0 ]; then
    log_error "Unable to download ${RESULT_XML} from production;" "error code ${rc}"
    exit ${rc}
  fi
else
  log_info "Using local copy of ${PRODUCTION_XML}"
fi
# Fix DOS line endings
#sed -i '.dos' -e 's/\r//' "${PRODUCTION_XML}"
#sed -i '.dos' -e 's/\r//' "${STAGING_XML}"

# Remove empty lines
log_info "Removing empty lines from XML files"
sed -i'.emptylines' -e '/^$/d' "${PRODUCTION_XML}"
sed -i'.emptylines' -e '/^$/d' "${STAGING_XML}"

cp -af "${PRODUCTION_XML}" "${RESULT_XML}"

# Merge apps
for app in ${APPLIST}; do
  log_info "Merging ${app} from staging to production"
  NEWAPP=0
  AFTER=8
  rm -f "${app}.patch"
  if ! grep --quiet "<Name>${app}" "${RESULT_XML}"; then
    # This is a new app, insert a tag at the end of the file
    if [ ${XMLSTARLET} -eq 1 ]; then
      $XML edit --inplace \
        --subnode "/AppsList" --type elem --name "App" \
        --subnode "/AppsList/App[last()]" --type elem --name "Name" --value "${app}" \
        "${RESULT_XML}"
    else
      OFFSET=$(( $(wc -l "${RESULT_XML}" | awk '{print $1}') - 1 ))
      sed -i'.preapp' \
        -e $'$i\\\n'"\  <App>" \
        -e $'$i\\\n'"\    <Name>${app}</Name>" \
        -e $'$i\\\n'"\  </App>" \
        "${RESULT_XML}"
    fi
    NEWAPP=1
    OFFSET=$(( $(wc -l "${RESULT_XML}" | awk '{print $1}') - 3 ))
    AFTER=1
  fi
  # Generate patch
  if [ ${XMLSTARLET} -eq 1 ]; then
    diff -u \
      <( $XML select --indent --template --nl \
         --copy-of "//AppsList/App[Name/text()='${app}']" "${RESULT_XML}" ) \
      <( $XML select --indent --template --nl \
         --copy-of "//AppsList/App[Name/text()='${app}']" "${STAGING_XML}" ) \
      > "${app}.patch" && rc=$? || rc=$?
  else
    # Fall back to grep; this is less robust, but it works if the XML is pretty-printed
    diff -u \
      <( grep --before-context=1 --after-context="${AFTER}" "<Name>${app}" \
        "${RESULT_XML}" ) \
      <( grep --before-context=1 --after-context=8 "<Name>${app}" \
        "${STAGING_XML}" ) \
      > "${app}.patch" && rc=$? || rc=$?
  fi
  # Fix patch lines if new app; patch fails otherwise
  if [ ${NEWAPP} -eq 1 ]; then
    sed -i'.preoffset' \
      -e "s/-1/-${OFFSET}/" \
      -e "s/+1/+${OFFSET}/" \
      -e "s/<App>/  <App>/" \
      "${app}.patch"
  fi
  patch "${RESULT_XML}" "${app}.patch"
  # Sort result XML
  if [ ${XMLSTARLET} -eq 1 ]; then
    log_info "Sorting production XML by app name"
    cp -af "${RESULT_XML}" "${RESULT_XML}.presort"
    $XML select --xml-decl --root --template --nl \
      --match "/AppsList/App" --sort A:T:- "Name" \
      --copy-of "Name/.." "${RESULT_XML}.presort" > "${RESULT_XML}"
    $XML edit --inplace \
      --rename "/xsl-select" --value "AppsList" \
      "${RESULT_XML}"
  else
    log_warn "XML result not sorted; ${app} will be the last app in ${RESULT_XML}"
  fi
done

if [ ${XMLSTARLET} -eq 1 ]; then
  log_info "Validating and formatting new production XML"
  cp -af "${RESULT_XML}" "${RESULT_XML}.preformat"
  $XML format "${RESULT_XML}.preformat" 1> "${RESULT_XML}"
else
  log_warn "XML result not validated and formatted; please try to open ${RESULT_XML} in an XML parser"
fi

log_success "new production XML is ${RESULT_XML}"
