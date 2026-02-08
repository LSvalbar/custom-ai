#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/prepare-host-layout.sh"

SINCE="24h"
FOLLOW=0
CONTAINERS=()

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/export-docker-logs.sh [container ...] [--since <duration>] [--follow]

Examples:
  bash scripts/export-docker-logs.sh
  bash scripts/export-docker-logs.sh openwebui ragflow-gpu --since 2h
  bash scripts/export-docker-logs.sh --follow
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE="$2"
      shift 2
      ;;
    --follow)
      FOLLOW=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      CONTAINERS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
  CONTAINERS=(
    "openwebui"
    "ragflow-proxy"
    "ragflow-gpu"
    "ragflow-cpu"
    "ragflow-mysql"
    "ragflow-redis"
    "ragflow-minio"
    "ragflow-es01"
    "ragflow-opensearch01"
    "ragflow-infinity"
    "ragflow-oceanbase"
    "ragflow-kibana"
    "ragflow-tei-cpu"
    "ragflow-tei-gpu"
    "vllm"
  )
fi

existing=()
for container in "${CONTAINERS[@]}"; do
  if docker inspect "$container" >/dev/null 2>&1; then
    existing+=("$container")
  else
    echo "Skipping missing container: $container"
  fi
done

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "No containers found."
  exit 0
fi

if [[ $FOLLOW -eq 0 ]]; then
  for container in "${existing[@]}"; do
    log_dir="$HOST_LOG_ROOT/$container"
    mkdir -p "$log_dir"
    log_file="$log_dir/docker.log"
    echo "Exporting logs: $container -> $log_file (since=$SINCE)"
    docker logs --timestamps --since "$SINCE" "$container" > "$log_file" 2>&1 || true
  done
  exit 0
fi

pids=()
cleanup() {
  for pid in "${pids[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT INT TERM

for container in "${existing[@]}"; do
  log_dir="$HOST_LOG_ROOT/$container"
  mkdir -p "$log_dir"
  log_file="$log_dir/docker.log"
  echo "Following logs: $container -> $log_file (since=$SINCE)"
  docker logs -f --timestamps --since "$SINCE" "$container" >> "$log_file" 2>&1 &
  pids+=("$!")
done

wait
