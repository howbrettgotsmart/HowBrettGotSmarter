#!/bin/zsh

set -euo pipefail

SCRIPT_NAME="${0:t}"

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
  Reads CFBundleShortVersionString from a macOS .app bundle Info.plist.

Examples:
  $SCRIPT_NAME "/Applications/Safari.app"
  $SCRIPT_NAME "/Applications/Google Chrome.app"
EOF
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

version=""
if ! version="$(/usr/bin/defaults read "$info_plist" CFBundleShortVersionString 2>/dev/null)"; then
  log "ERROR" "Unable to read CFBundleShortVersionString from: $info_plist"
  exit 4
fi

if [[ -z "$version" ]]; then
  log "ERROR" "CFBundleShortVersionString is empty."
  exit 5
fi

log "INFO" "Installed app version: $version"
print -r -- "$version"
