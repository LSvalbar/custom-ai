#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/prepare-host-layout.sh"

COMPONENTS=()
LOAD_IMAGES=1

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/upgrade.sh [component ...] [--no-load]

Components:
  all | openwebui | proxy | ragflow | deps | tei | vllm

Examples:
  bash scripts/upgrade.sh all
  bash scripts/upgrade.sh vllm
  bash scripts/upgrade.sh openwebui proxy
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-load)
      LOAD_IMAGES=0
      shift
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

ensure_es_kernel_prereq() {
  local current
  current="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
  if [[ "$current" -lt 262144 ]]; then
    echo "Cannot start RAGFlow/Elasticsearch: vm.max_map_count=$current (<262144)."
    echo "Run once on host as root:"
    echo "  sudo sysctl -w vm.max_map_count=262144"
    echo "Then run upgrade again."
    exit 1
  fi
}

resolve_vllm_host_model_path() {
  local env_file="$ROOT_DIR/compose/vllm/.env"
  if [[ ! -f "$env_file" ]]; then
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  if [[ -z "${MODEL_ROOT:-}" || -z "${MODEL_PATH:-}" ]]; then
    return 1
  fi

  if [[ "$MODEL_PATH" == /models/* ]]; then
    local rel="${MODEL_PATH#/models/}"
    printf "%s/%s\n" "${MODEL_ROOT%/}" "$rel"
    return 0
  fi

  if [[ "$MODEL_PATH" == "$MODEL_ROOT"* ]]; then
    printf "%s\n" "$MODEL_PATH"
    return 0
  fi

  return 1
}

can_start_vllm() {
  local host_model_path
  host_model_path="$(resolve_vllm_host_model_path || true)"
  if [[ -z "$host_model_path" ]]; then
    echo "Skip vLLM start: unable to resolve host model path from compose/vllm/.env"
    return 1
  fi

  if [[ ! -d "$host_model_path" ]]; then
    echo "Skip vLLM start: model directory does not exist: $host_model_path"
    return 1
  fi

  if [[ ! -f "$host_model_path/config.json" ]]; then
    echo "Skip vLLM start: missing config.json under model directory: $host_model_path"
    return 1
  fi

  return 0
}

if [[ $LOAD_IMAGES -eq 1 ]]; then
  bash "$ROOT_DIR/scripts/load-images.sh" "${COMPONENTS[@]}"
fi

bash "$ROOT_DIR/scripts/retag-images.sh" "${COMPONENTS[@]}"

if contains_component "ragflow" "${COMPONENTS[@]}" || contains_component "deps" "${COMPONENTS[@]}" || contains_component "tei" "${COMPONENTS[@]}"; then
  ensure_es_kernel_prereq
  ( cd "$ROOT_DIR/compose/ragflow" && docker compose -f docker-compose.yml up -d )
fi

if contains_component "openwebui" "${COMPONENTS[@]}" || contains_component "proxy" "${COMPONENTS[@]}"; then
  ( cd "$ROOT_DIR/compose/openwebui" && docker compose -f docker-compose.yml up -d )
fi

if contains_component "vllm" "${COMPONENTS[@]}"; then
  if can_start_vllm; then
    ( cd "$ROOT_DIR/compose/vllm" && docker compose -f docker-compose.yml up -d )
  fi
fi

echo "Upgrade completed for components: ${COMPONENTS[*]}"
