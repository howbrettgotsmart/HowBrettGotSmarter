#!/bin/bash

# -----------------------------------------------------------------------------
# Script: update-chrome-if-newer.sh
# Author: Brett Thomason
# Created: 2026-03-11
# Purpose: Check installed Google Chrome version on macOS against latest online
#          stable version and install update only when newer is available.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CHROME_APP="/Applications/Google Chrome.app"
CHROME_PLIST="${CHROME_APP}/Contents/Info.plist"
DEFAULT_PKG_URL="https://dl.google.com/chrome/mac/stable/accept_tos%3Dhttps%253A%252F%252Fwww.google.com%252Fintl%252Fen_ph%252Fchrome%252Fterms%252F%26_and_accept_tos%3Dhttps%253A%252F%252Fpolicies.google.com%252Fterms/googlechrome.pkg"
VERSION_API_BASE="https://versionhistory.googleapis.com/v1/chrome/platforms"
TMP_PKG=""
DRY_RUN="false"
FORCE_INSTALL="false"

usage() {
  cat <<EOF
Usage:
  sudo ${SCRIPT_NAME} [--pkg-url URL] [--dry-run] [--force]

Description:
  1) Reads installed Chrome version from:
     ${CHROME_PLIST}
  2) Fetches latest stable Chrome version for macOS from Google's
     VersionHistory API.
  3) If online version is newer, downloads and installs the Chrome package.
  4) If installed version is current/newer, exits without changes.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cleanup_temp_pkg() {
  if [[ -n "${TMP_PKG}" && -f "${TMP_PKG}" ]]; then
    rm -f "${TMP_PKG}"
  fi
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

require_commands() {
  local cmd
  for cmd in curl mktemp installer pgrep osascript /usr/libexec/PlistBuddy; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERROR: Required command not found: $cmd" >&2
      exit 1
    fi
  done
}

parse_args() {
  PKG_URL="${DEFAULT_PKG_URL}"

  while (($# > 0)); do
    case "$1" in
      --pkg-url)
        shift
        if [[ $# -eq 0 ]]; then
          echo "ERROR: Missing value for --pkg-url." >&2
          exit 1
        fi
        PKG_URL="$1"
        ;;
      --dry-run)
        DRY_RUN="true"
        ;;
      --force)
        FORCE_INSTALL="true"
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
}

version_gt() {
  local v1="$1"
  local v2="$2"
  local IFS=.
  local i max
  local -a a b

  read -r -a a <<< "$v1"
  read -r -a b <<< "$v2"
  max="${#a[@]}"
  if (( ${#b[@]} > max )); then
    max="${#b[@]}"
  fi

  for ((i=0; i<max; i++)); do
    local ai="${a[i]:-0}"
    local bi="${b[i]:-0}"
    if ((10#${ai} > 10#${bi})); then
      return 0
    fi
    if ((10#${ai} < 10#${bi})); then
      return 1
    fi
  done

  return 1
}

read_installed_version() {
  if [[ ! -f "${CHROME_PLIST}" ]]; then
    echo "0.0.0.0"
    return
  fi

  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${CHROME_PLIST}"
}

extract_version_from_json() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.load(sys.stdin)["versions"][0]["version"])'
    return
  fi

  grep -Eo '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | cut -d'"' -f4
}

fetch_latest_version_for_platform() {
  local platform="$1"
  local url="${VERSION_API_BASE}/${platform}/channels/stable/versions?order_by=version%20desc&page_size=1"
  local payload version

  if ! payload="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "${url}")"; then
    return 1
  fi
  version="$(printf '%s' "${payload}" | extract_version_from_json)"

  if [[ -z "${version}" ]]; then
    return 1
  fi

  printf '%s\n' "${version}"
}

fetch_latest_online_version() {
  local latest_mac=""
  local latest_mac_arm64=""

  if latest_mac="$(fetch_latest_version_for_platform mac)"; then
    log "Latest stable mac version from API: ${latest_mac}"
  else
    log "WARNING: Failed to fetch stable version for platform: mac"
  fi

  if latest_mac_arm64="$(fetch_latest_version_for_platform mac_arm64)"; then
    log "Latest stable mac_arm64 version from API: ${latest_mac_arm64}"
  else
    log "WARNING: Failed to fetch stable version for platform: mac_arm64"
  fi

  if [[ -z "${latest_mac}" && -z "${latest_mac_arm64}" ]]; then
    echo "ERROR: Failed to fetch latest stable Chrome version from API." >&2
    exit 1
  fi

  if [[ -z "${latest_mac}" ]]; then
    printf '%s\n' "${latest_mac_arm64}"
    return
  fi

  if [[ -z "${latest_mac_arm64}" ]]; then
    printf '%s\n' "${latest_mac}"
    return
  fi

  if version_gt "${latest_mac}" "${latest_mac_arm64}"; then
    printf '%s\n' "${latest_mac}"
  else
    printf '%s\n' "${latest_mac_arm64}"
  fi
}

quit_chrome_if_running() {
  local waited=0

  if ! pgrep -x "Google Chrome" >/dev/null 2>&1; then
    log "Google Chrome is not running."
    return
  fi

  log "Google Chrome is running. Attempting graceful quit."
  osascript -e 'tell application "Google Chrome" to quit' >/dev/null 2>&1 || true

  while pgrep -x "Google Chrome" >/dev/null 2>&1; do
    if (( waited >= 15 )); then
      log "Chrome still running after 15s. Forcing quit."
      killall "Google Chrome" >/dev/null 2>&1 || true
      sleep 2
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if pgrep -x "Google Chrome" >/dev/null 2>&1; then
    log "Chrome did not fully stop; update may fail if app remains active."
  else
    log "Google Chrome closed."
  fi
}

main() {
  local installed_version latest_online post_install_version

  trap cleanup_temp_pkg EXIT
  require_macos
  require_root
  require_commands
  parse_args "$@"

  log "Checking installed Google Chrome version."
  installed_version="$(read_installed_version)"
  log "Installed version: ${installed_version}"

  log "Fetching latest stable Chrome version from Google VersionHistory API."
  latest_online="$(fetch_latest_online_version)"

  log "Latest online version: ${latest_online}"

  if [[ "${FORCE_INSTALL}" != "true" ]] && ! version_gt "${latest_online}" "${installed_version}"; then
    log "No update needed. Installed Chrome is current (or newer)."
    exit 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "Dry run mode: update would be installed."
    exit 0
  fi

  quit_chrome_if_running

  log "Newer version detected. Downloading Chrome package."
  TMP_PKG="$(mktemp /tmp/googlechrome-update.XXXXXX.pkg)"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 "${PKG_URL}" -o "${TMP_PKG}"

  log "Installing Chrome package."
  /usr/sbin/installer -pkg "${TMP_PKG}" -target /

  post_install_version="$(read_installed_version)"
  log "Install complete. Current installed version: ${post_install_version}"

  if version_gt "${latest_online}" "${post_install_version}"; then
    log "WARNING: Installed version is still behind latest online version."
    exit 1
  fi
}

main "$@"
