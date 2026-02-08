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

echo "HOST_DATA_ROOT=$HOST_DATA_ROOT"
echo "HOST_LOG_ROOT=$HOST_LOG_ROOT"
