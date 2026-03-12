#!/bin/bash

# -----------------------------------------------------------------------------
# Script: rum-launchd-uninstaller.sh
# Author: Brett Thomason
# Created: 2026-03-11
# Purpose: Disable and remove the Adobe RUM LaunchDaemon, including the
#          LaunchDaemon plist and runner script installed by the installer.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DAEMON_LABEL="com.howbrettgotsmart.adobe-rum-updates"
LAUNCHD_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
RUNNER_SCRIPT="/usr/local/bin/adobe-rum-update-check.sh"

usage() {
  cat <<EOF
Usage:
  sudo $SCRIPT_NAME

Description:
  Disables and unloads the Adobe RUM LaunchDaemon, then removes:
  - ${LAUNCHD_PLIST}
  - ${RUNNER_SCRIPT}
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: This script only supports macOS." >&2
    exit 1
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run as root (use sudo)." >&2
    exit 1
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if (( $# != 0 )); then
    echo "ERROR: This script does not accept arguments." >&2
    usage >&2
    exit 1
  fi

  require_macos
  require_root

  log "Disabling LaunchDaemon (if loaded): ${DAEMON_LABEL}"
  launchctl disable "system/${DAEMON_LABEL}" >/dev/null 2>&1 || true

  log "Unloading LaunchDaemon (if loaded): ${LAUNCHD_PLIST}"
  launchctl bootout "system/${DAEMON_LABEL}" >/dev/null 2>&1 || true
  launchctl bootout system "${LAUNCHD_PLIST}" >/dev/null 2>&1 || true

  if [[ -f "${LAUNCHD_PLIST}" ]]; then
    log "Removing plist: ${LAUNCHD_PLIST}"
    rm -f "${LAUNCHD_PLIST}"
  else
    log "Plist already absent: ${LAUNCHD_PLIST}"
  fi

  if [[ -f "${RUNNER_SCRIPT}" ]]; then
    log "Removing runner script: ${RUNNER_SCRIPT}"
    rm -f "${RUNNER_SCRIPT}"
  else
    log "Runner script already absent: ${RUNNER_SCRIPT}"
  fi

  if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
    log "WARNING: Service still appears loaded: ${DAEMON_LABEL}"
  else
    log "Service is not loaded: ${DAEMON_LABEL}"
  fi

  log "RUM LaunchD uninstaller complete."
}

main "$@"
