#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/prepare-host-layout.sh"

COMPONENTS=()
LOAD_IMAGES=1
DO_BACKUP=0
BACKUP_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/upgrade.sh [component ...] [--no-load] [--backup] [--backup-dir <path>]

Components:
  all | openwebui | proxy | ragflow | deps | tei | vllm

Examples:
  bash scripts/upgrade.sh all
  bash scripts/upgrade.sh vllm
  bash scripts/upgrade.sh openwebui proxy
  bash scripts/upgrade.sh ragflow --backup
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-load)
      LOAD_IMAGES=0
      shift
      ;;
    --backup)
      DO_BACKUP=1
      shift
      ;;
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      COMPONENTS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
  COMPONENTS=("all")
fi

contains_component() {
  local target="$1"
  shift
  local items=("$@")
  for item in "${items[@]}"; do
    if [[ "$item" == "all" || "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ $DO_BACKUP -eq 1 ]]; then
  backup_cmd=("$ROOT_DIR/scripts/backup.sh")
  if [[ -n "$BACKUP_DIR" ]]; then
    backup_cmd+=("--backup-dir" "$BACKUP_DIR")
  fi
  backup_cmd+=("${COMPONENTS[@]}")
  "${backup_cmd[@]}"
fi

if [[ $LOAD_IMAGES -eq 1 ]]; then
  bash "$ROOT_DIR/scripts/load-images.sh" "${COMPONENTS[@]}"
fi

bash "$ROOT_DIR/scripts/retag-images.sh" "${COMPONENTS[@]}"

if contains_component "ragflow" "${COMPONENTS[@]}" || contains_component "deps" "${COMPONENTS[@]}" || contains_component "tei" "${COMPONENTS[@]}"; then
  ( cd "$ROOT_DIR/compose/ragflow" && docker compose -f docker-compose.yml up -d )
fi

if contains_component "openwebui" "${COMPONENTS[@]}" || contains_component "proxy" "${COMPONENTS[@]}"; then
  ( cd "$ROOT_DIR/compose/openwebui" && docker compose -f docker-compose.yml up -d )
fi

if contains_component "vllm" "${COMPONENTS[@]}"; then
  ( cd "$ROOT_DIR/compose/vllm" && docker compose -f docker-compose.yml up -d )
fi

echo "Upgrade completed for components: ${COMPONENTS[*]}"
