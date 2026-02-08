#!/usr/bin/env bash
set -euo pipefail

APPLY=0
REMOVE_PIP=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/cleanup-legacy-python.sh [--apply] [--remove-pip]

Default is dry-run.

Options:
  --apply       Execute stop/disable/kill commands
  --remove-pip  Also uninstall open-webui and vllm from system python/pip
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --remove-pip)
      REMOVE_PIP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

run_cmd() {
  if [[ $APPLY -eq 1 ]]; then
    eval "$1"
  else
    echo "[dry-run] $1"
  fi
}

echo "Scanning systemd services..."
mapfile -t UNITS < <(systemctl list-unit-files --type=service --no-pager | awk '{print $1}' | grep -Ei '^(open-webui|openwebui|vllm)(\.service)?$' || true)

for unit in "${UNITS[@]}"; do
  [[ -z "$unit" ]] && continue
  run_cmd "sudo systemctl disable --now $unit"
done

echo "Stopping legacy processes..."
run_cmd "pkill -f 'open-webui serve' || true"
run_cmd "pkill -f 'open_webui.main:app' || true"
run_cmd "pkill -f 'vllm.entrypoints.openai.api_server' || true"

if [[ $REMOVE_PIP -eq 1 ]]; then
  echo "Uninstalling pip packages..."
  if command -v python3 >/dev/null 2>&1; then
    run_cmd "python3 -m pip uninstall -y open-webui vllm || true"
  fi
  if command -v pip3 >/dev/null 2>&1; then
    run_cmd "pip3 uninstall -y open-webui vllm || true"
  fi
fi

echo "Done."
if [[ $APPLY -eq 0 ]]; then
  echo "This was dry-run. Re-run with --apply to execute."
fi
