#!/usr/bin/env bash
set -euo pipefail

HOST_DATA_ROOT="${HOST_DATA_ROOT:-$HOME/data/forstar}"
HOST_LOG_ROOT="${HOST_LOG_ROOT:-/var/log/forstar}"

export HOST_DATA_ROOT HOST_LOG_ROOT

mkdir -p "$HOST_DATA_ROOT"
if ! mkdir -p "$HOST_LOG_ROOT" 2>/dev/null; then
  HOST_LOG_ROOT="$HOME/log/forstar"
  export HOST_LOG_ROOT
  mkdir -p "$HOST_LOG_ROOT"
fi

# Elasticsearch requires vm.max_map_count >= 262144.
# Apply immediately when possible and persist for reboot.
if command -v sysctl >/dev/null 2>&1; then
  current_vm_max_map_count="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
  if [[ "$current_vm_max_map_count" -lt 262144 ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      sysctl -w vm.max_map_count=262144 >/dev/null || true
      mkdir -p /etc/sysctl.d
      cat >/etc/sysctl.d/99-forstar.conf <<'EOF'
vm.max_map_count=262144
EOF
    else
      echo "Warning: vm.max_map_count=$current_vm_max_map_count (<262144). Run as root once to apply Elasticsearch kernel setting."
    fi
  fi
fi

# Data directories
mkdir -p "$HOST_DATA_ROOT/openwebui"
mkdir -p "$HOST_DATA_ROOT/ragflow/history_data_agent"
mkdir -p "$HOST_DATA_ROOT/ragflow/mysql"
mkdir -p "$HOST_DATA_ROOT/ragflow/minio"
mkdir -p "$HOST_DATA_ROOT/ragflow/redis"
mkdir -p "$HOST_DATA_ROOT/ragflow/elasticsearch"
mkdir -p "$HOST_DATA_ROOT/ragflow/opensearch"
mkdir -p "$HOST_DATA_ROOT/ragflow/infinity"
mkdir -p "$HOST_DATA_ROOT/ragflow/kibana"
mkdir -p "$HOST_DATA_ROOT/ragflow/oceanbase/data"
mkdir -p "$HOST_DATA_ROOT/ragflow/oceanbase/conf"
mkdir -p "$HOST_DATA_ROOT/vllm"

# Log directories
mkdir -p "$HOST_LOG_ROOT/openwebui"
mkdir -p "$HOST_LOG_ROOT/ragflow-proxy"
mkdir -p "$HOST_LOG_ROOT/ragflow"
mkdir -p "$HOST_LOG_ROOT/ragflow-nginx"
mkdir -p "$HOST_LOG_ROOT/mysql"
mkdir -p "$HOST_LOG_ROOT/redis"
mkdir -p "$HOST_LOG_ROOT/elasticsearch"
mkdir -p "$HOST_LOG_ROOT/opensearch"
mkdir -p "$HOST_LOG_ROOT/vllm"

# Ensure Elastic/OpenSearch data dirs are writable for uid/gid 1000 in containers.
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R 1000:1000 "$HOST_DATA_ROOT/ragflow/elasticsearch" "$HOST_DATA_ROOT/ragflow/opensearch" >/dev/null 2>&1 || true
fi

echo "HOST_DATA_ROOT=$HOST_DATA_ROOT"
echo "HOST_LOG_ROOT=$HOST_LOG_ROOT"
