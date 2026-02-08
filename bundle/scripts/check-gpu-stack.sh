#!/usr/bin/env bash
set -euo pipefail

TARGET_CUDA="${1:-12.2}"

ver_ge() {
  local a="$1"
  local b="$2"
  [[ "$(printf '%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" ]]
}

min_driver_for_cuda() {
  local cuda="$1"
  case "$cuda" in
    12.*) echo "525.60.13" ;;
    11.*) echo "450.80.02" ;;
    10.*) echo "410.48" ;;
    *) echo "0.0.0" ;;
  esac
}

recommended_driver_for_cuda() {
  local cuda="$1"
  case "$cuda" in
    12.2*|12.3*|12.4*) echo "535.54.03" ;;
    12.5*|12.6*|12.7*|12.8*|12.9*) echo "550.54.14" ;;
    12.*) echo "535.54.03" ;;
    11.*) echo "470.57.02" ;;
    *) echo "0.0.0" ;;
  esac
}

echo "=== GPU Stack Check ==="

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi: NOT FOUND"
  exit 1
fi

DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d ' ')"
RUNTIME_CUDA_VERSION="$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader | head -n1 | tr -d ' ')"
GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"

echo "GPU: $GPU_NAME"
echo "Driver: $DRIVER_VERSION"
echo "Runtime CUDA reported by nvidia-smi: $RUNTIME_CUDA_VERSION"
echo "Target CUDA: $TARGET_CUDA"

MIN_DRIVER="$(min_driver_for_cuda "$TARGET_CUDA")"
REC_DRIVER="$(recommended_driver_for_cuda "$TARGET_CUDA")"

echo "Minimum driver (CUDA compatibility): $MIN_DRIVER"
echo "Recommended driver for stability: $REC_DRIVER"

if ver_ge "$DRIVER_VERSION" "$MIN_DRIVER"; then
  echo "Result: PASS (minimum compatibility met)"
else
  echo "Result: FAIL (driver too old for target CUDA)"
fi

if ver_ge "$DRIVER_VERSION" "$REC_DRIVER"; then
  echo "Recommendation: PASS (driver is in recommended range)"
else
  echo "Recommendation: UPGRADE ADVISED (below recommended range)"
fi

if command -v docker >/dev/null 2>&1; then
  echo ""
  echo "Docker runtime check:"
  docker info 2>/dev/null | sed -n '/Runtimes:/,/Default Runtime:/p' || true
else
  echo "docker: NOT FOUND"
fi

if [[ -f "./repos/vllm/docker/Dockerfile" ]]; then
  VLLM_DOCKER_CUDA="$(grep -m1 '^ARG CUDA_VERSION=' ./repos/vllm/docker/Dockerfile | cut -d= -f2 || true)"
  echo "vLLM source Dockerfile CUDA default: ${VLLM_DOCKER_CUDA:-unknown}"
fi
