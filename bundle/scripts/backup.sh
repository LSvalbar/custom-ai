#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/prepare-host-layout.sh"

COMPONENTS=()
BACKUP_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/backup.sh [component ...] [--backup-dir <path>]

Components:
  all | openwebui | proxy | ragflow | deps | tei | vllm

Notes:
  - Backups are created from HOST_DATA_ROOT bind-mounted directories.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$ROOT_DIR/backups/$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$BACKUP_DIR"

declare -A DATA_DIRS=()

if contains_component "openwebui" "${COMPONENTS[@]}" || contains_component "proxy" "${COMPONENTS[@]}"; then
  DATA_DIRS["openwebui"]="$HOST_DATA_ROOT/openwebui"
fi

if contains_component "ragflow" "${COMPONENTS[@]}" || contains_component "deps" "${COMPONENTS[@]}" || contains_component "tei" "${COMPONENTS[@]}"; then
  DATA_DIRS["ragflow-history_data_agent"]="$HOST_DATA_ROOT/ragflow/history_data_agent"
  DATA_DIRS["ragflow-mysql"]="$HOST_DATA_ROOT/ragflow/mysql"
  DATA_DIRS["ragflow-minio"]="$HOST_DATA_ROOT/ragflow/minio"
  DATA_DIRS["ragflow-redis"]="$HOST_DATA_ROOT/ragflow/redis"
  DATA_DIRS["ragflow-elasticsearch"]="$HOST_DATA_ROOT/ragflow/elasticsearch"
  DATA_DIRS["ragflow-opensearch"]="$HOST_DATA_ROOT/ragflow/opensearch"
  DATA_DIRS["ragflow-infinity"]="$HOST_DATA_ROOT/ragflow/infinity"
  DATA_DIRS["ragflow-kibana"]="$HOST_DATA_ROOT/ragflow/kibana"
  DATA_DIRS["ragflow-oceanbase-data"]="$HOST_DATA_ROOT/ragflow/oceanbase/data"
  DATA_DIRS["ragflow-oceanbase-conf"]="$HOST_DATA_ROOT/ragflow/oceanbase/conf"
fi

if contains_component "vllm" "${COMPONENTS[@]}"; then
  DATA_DIRS["vllm"]="$HOST_DATA_ROOT/vllm"
fi

if [[ ${#DATA_DIRS[@]} -eq 0 ]]; then
  echo "No data backup needed for components: ${COMPONENTS[*]}"
  exit 0
fi

for name in "${!DATA_DIRS[@]}"; do
  dir="${DATA_DIRS[$name]}"

  if [[ ! -d "$dir" ]]; then
    echo "Skipping missing data dir: $dir"
    continue
  fi

  out_file="$BACKUP_DIR/${name}.tar.gz"
  echo "Backing up $dir -> $out_file"
  tar czf "$out_file" -C "$dir" .
done

echo "Backup completed: $BACKUP_DIR"
