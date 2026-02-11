#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

down_stack() {
  local compose_dir="$1"
  if [[ -d "$compose_dir" ]]; then
    ( cd "$compose_dir" && docker compose -f docker-compose.yml down --remove-orphans )
  fi
}

down_stack "$ROOT_DIR/compose/openwebui"
down_stack "$ROOT_DIR/compose/vllm"
down_stack "$ROOT_DIR/compose/ragflow"

echo "All platform containers stopped and removed."
