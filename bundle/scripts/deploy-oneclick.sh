#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

current_vm_max_map_count="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if [[ "$current_vm_max_map_count" -lt 262144 ]]; then
  echo "Elasticsearch prerequisite not met: vm.max_map_count=$current_vm_max_map_count (<262144)."
  echo "Run once on host as root:"
  echo "  sudo sysctl -w vm.max_map_count=262144"
  echo "Then re-run deploy."
  exit 1
fi

bash "$ROOT_DIR/scripts/upgrade.sh" all "$@"
