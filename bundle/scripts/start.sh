#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/prepare-host-layout.sh"

# Start RAGFlow stack
( cd "$ROOT_DIR/compose/ragflow" && docker compose -f docker-compose.yml up -d )

# Start OpenWebUI + proxy
( cd "$ROOT_DIR/compose/openwebui" && docker compose -f docker-compose.yml up -d )
