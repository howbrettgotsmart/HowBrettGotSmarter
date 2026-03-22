#!/bin/zsh

set -euo pipefail

SCRIPT_NAME="${0:t}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

log() {
  local level="$1"
  shift
  print -u2 -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME <path-to-app-bundle>
  $SCRIPT_NAME --help

Description:
  Reads app version from a macOS .app bundle Info.plist.
  Tries CFBundleShortVersionString first, then CFBundleVersion.

Examples:
  $SCRIPT_NAME "/Applications/Safari.app"
  $SCRIPT_NAME "/Applications/Google Chrome.app"
EOF
}

read_plist_key() {
  local plist_path="$1"
  local key="$2"
  "$PLIST_BUDDY" -c "Print :$key" "$plist_path" 2>/dev/null || true
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if (( $# != 1 )); then
  log "ERROR" "Expected exactly one argument."
  usage >&2
  exit 1
fi

app_path="$1"
info_plist="$app_path/Contents/Info.plist"

log "INFO" "Starting installed app version check."
log "INFO" "App path: $app_path"

if [[ ! -d "$app_path" ]]; then
  log "ERROR" "App bundle is missing: $app_path"
  exit 2
fi

if [[ ! -f "$info_plist" ]]; then
  log "ERROR" "Info.plist not found at: $info_plist"
  exit 3
fi

if [[ ! -x "$PLIST_BUDDY" ]]; then
  log "ERROR" "Required tool not found: $PLIST_BUDDY"
  exit 4
fi

version="$(read_plist_key "$info_plist" "CFBundleShortVersionString")"
if [[ -n "$version" ]]; then
  log "INFO" "Using CFBundleShortVersionString."
else
  log "INFO" "CFBundleShortVersionString missing; falling back to CFBundleVersion."
  version="$(read_plist_key "$info_plist" "CFBundleVersion")"
fi

if [[ -z "$version" ]]; then
  log "ERROR" "Unable to find CFBundleShortVersionString or CFBundleVersion in: $info_plist"
  exit 5
fi

log "INFO" "Installed app version: $version"
print -r -- "$version"
