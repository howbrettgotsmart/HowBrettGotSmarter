#!/bin/bash

# -----------------------------------------------------------------------------
# Script: install-adobe-rum-launchdaemon.sh
# Author: Brett Thomason
# Created: 2026-03-11
# Purpose: Install and load a macOS LaunchDaemon that runs Adobe RUM update
#          checks twice daily at 07:00 and 18:00 local time.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DAEMON_LABEL="com.howbrettgotsmart.adobe-rum-updates"
LAUNCHD_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
RUNNER_SCRIPT="/usr/local/bin/adobe-rum-update-check.sh"
LOG_FILE="/var/log/adobe-rum-updates.log"
RUNNER_DIR="$(dirname "${RUNNER_SCRIPT}")"
LOG_DIR="$(dirname "${LOG_FILE}")"
RUM_PATH_DEFAULT="/usr/local/bin/RemoteUpdateManager"

usage() {
  cat <<EOF
Usage:
  sudo $SCRIPT_NAME [--rum-path /path/to/RemoteUpdateManager]

Description:
  Installs and loads a LaunchDaemon that runs Adobe Remote Update Manager
  twice daily at 07:00 and 18:00 local time.
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

ensure_required_paths() {
  mkdir -p "${RUNNER_DIR}" "${LOG_DIR}"
  touch "${LOG_FILE}"
  chmod 644 "${LOG_FILE}"
  chown root:wheel "${LOG_FILE}"
}

parse_args() {
  RUM_PATH="${RUM_PATH_DEFAULT}"

  while (($# > 0)); do
    case "$1" in
      --rum-path)
        shift
        if [[ $# -eq 0 ]]; then
          echo "ERROR: Missing value for --rum-path." >&2
          exit 1
        fi
        RUM_PATH="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ ! -x "${RUM_PATH}" ]]; then
    echo "ERROR: RemoteUpdateManager is not executable at: ${RUM_PATH}" >&2
    exit 1
  fi
}

install_runner_script() {
  log "Installing runner script: ${RUNNER_SCRIPT}"
  cat > "${RUNNER_SCRIPT}" <<EOF
#!/bin/bash
set -euo pipefail

RUM_PATH="${RUM_PATH}"
LOG_FILE="${LOG_FILE}"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

{
  echo "[\$(timestamp)] Starting Adobe RUM update check."
  set +e
  "\${RUM_PATH}" --action=install
  rc=\$?
  set -e
  echo "[\$(timestamp)] Adobe RUM update check completed with exit code \$rc."
  exit \$rc
} >> "\${LOG_FILE}" 2>&1
EOF

  chmod 755 "${RUNNER_SCRIPT}"
  chown root:wheel "${RUNNER_SCRIPT}"
}

install_launchdaemon() {
  log "Writing LaunchDaemon plist: ${LAUNCHD_PLIST}"
  cat > "${LAUNCHD_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${DAEMON_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${RUNNER_SCRIPT}</string>
  </array>

  <key>StartCalendarInterval</key>
  <array>
    <dict>
      <key>Hour</key>
      <integer>7</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
    <dict>
      <key>Hour</key>
      <integer>18</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
  </array>

  <key>RunAtLoad</key>
  <false/>

  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>

  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF

  chmod 644 "${LAUNCHD_PLIST}"
  chown root:wheel "${LAUNCHD_PLIST}"

  /usr/bin/plutil -lint "${LAUNCHD_PLIST}" >/dev/null
}

load_launchdaemon() {
  log "Loading LaunchDaemon via launchctl."
  launchctl bootout "system/${DAEMON_LABEL}" >/dev/null 2>&1 || true
  launchctl bootout system "${LAUNCHD_PLIST}" >/dev/null 2>&1 || true
  launchctl bootstrap system "${LAUNCHD_PLIST}"
  launchctl enable "system/${DAEMON_LABEL}" || true
  launchctl print "system/${DAEMON_LABEL}" >/dev/null
}

main() {
  require_macos
  require_root
  parse_args "$@"
  ensure_required_paths
  install_runner_script
  install_launchdaemon
  load_launchdaemon
  log "Done. Scheduled checks at 07:00 and 18:00 local time."
  log "View logs with: sudo tail -f ${LOG_FILE}"
}

main "$@"
