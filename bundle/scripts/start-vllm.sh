#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/prepare-host-layout.sh"

( cd "$ROOT_DIR/compose/vllm" && docker compose -f docker-compose.yml up -d )
