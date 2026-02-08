#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OFFLINE_ROOT_DEFAULT="$ROOT_DIR/offline/nvidia"

DRIVER_RUNFILE=""
CUDA_RUNFILE=""
TOOLKIT_DEB_DIR=""
OFFLINE_ROOT="$OFFLINE_ROOT_DEFAULT"
INSTALL_DRIVER=1
INSTALL_CUDA=1
INSTALL_TOOLKIT_MODE="auto"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  # Recommended (auto-discover packages under bundle/offline/nvidia)
  sudo bash scripts/upgrade-nvidia-cuda-offline.sh

  # Explicit paths
  sudo bash scripts/upgrade-nvidia-cuda-offline.sh \
    --driver-runfile /path/NVIDIA-Linux-x86_64-<ver>.run \
    --cuda-runfile /path/cuda_<ver>_linux.run \
    [--toolkit-deb-dir /path/to/nvidia-container-toolkit-debs] \
    [--offline-root /path/to/offline/nvidia] \
    [--skip-driver] [--skip-cuda] [--install-toolkit|--skip-toolkit] [--dry-run]

Notes:
  - Offline installer: all files must already exist on server.
  - Default package directory: bundle/offline/nvidia
  - Auto-discover:
      driver: NVIDIA-Linux-x86_64-*.run
      cuda:   cuda_*_linux.run
      toolkit debs: bundle/offline/nvidia/toolkit-debs/*.deb
  - Reboot is strongly recommended after driver upgrade.
  - This script targets Ubuntu 24.04 server.
USAGE
}

run_cmd() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  eval "$@"
}

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Required file not found: $file_path" >&2
    exit 1
  fi
}

find_latest_file() {
  local base_dir="$1"
  local pattern="$2"
  local files=()
  shopt -s nullglob
  files=("$base_dir"/$pattern)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${files[@]}" | sort -V | tail -n1
}

has_debs() {
  local base_dir="$1"
  shopt -s nullglob
  local files=("$base_dir"/*.deb)
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver-runfile)
      DRIVER_RUNFILE="$2"
      shift 2
      ;;
    --cuda-runfile)
      CUDA_RUNFILE="$2"
      shift 2
      ;;
    --toolkit-deb-dir)
      TOOLKIT_DEB_DIR="$2"
      shift 2
      ;;
    --offline-root)
      OFFLINE_ROOT="$2"
      shift 2
      ;;
    --install-toolkit)
      INSTALL_TOOLKIT_MODE="on"
      shift
      ;;
    --skip-toolkit)
      INSTALL_TOOLKIT_MODE="off"
      shift
      ;;
    --skip-driver)
      INSTALL_DRIVER=0
      shift
      ;;
    --skip-cuda)
      INSTALL_CUDA=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root: sudo bash scripts/upgrade-nvidia-cuda-offline.sh ..." >&2
  exit 1
fi

if [[ -d "$OFFLINE_ROOT" ]]; then
  if [[ $INSTALL_DRIVER -eq 1 && -z "$DRIVER_RUNFILE" ]]; then
    DRIVER_RUNFILE="$(find_latest_file "$OFFLINE_ROOT" 'NVIDIA-Linux-x86_64-*.run' || true)"
  fi

  if [[ $INSTALL_CUDA -eq 1 && -z "$CUDA_RUNFILE" ]]; then
    CUDA_RUNFILE="$(find_latest_file "$OFFLINE_ROOT" 'cuda_*_linux.run' || true)"
  fi

  if [[ -z "$TOOLKIT_DEB_DIR" ]]; then
    if has_debs "$OFFLINE_ROOT/toolkit-debs"; then
      TOOLKIT_DEB_DIR="$OFFLINE_ROOT/toolkit-debs"
    fi
  fi
fi

if [[ $INSTALL_DRIVER -eq 1 && -z "$DRIVER_RUNFILE" ]]; then
  echo "Driver runfile not found." >&2
  echo "Provide --driver-runfile, or place file under: $OFFLINE_ROOT" >&2
  exit 1
fi

if [[ $INSTALL_CUDA -eq 1 && -z "$CUDA_RUNFILE" ]]; then
  echo "CUDA runfile not found." >&2
  echo "Provide --cuda-runfile, or place file under: $OFFLINE_ROOT" >&2
  exit 1
fi

if [[ "$INSTALL_TOOLKIT_MODE" == "auto" ]]; then
  if [[ -n "$TOOLKIT_DEB_DIR" && -d "$TOOLKIT_DEB_DIR" ]] && has_debs "$TOOLKIT_DEB_DIR"; then
    INSTALL_TOOLKIT_MODE="on"
  else
    INSTALL_TOOLKIT_MODE="off"
  fi
fi

if [[ $INSTALL_DRIVER -eq 1 ]]; then
  require_file "$DRIVER_RUNFILE"
fi

if [[ $INSTALL_CUDA -eq 1 ]]; then
  require_file "$CUDA_RUNFILE"
fi

if [[ "$INSTALL_TOOLKIT_MODE" == "on" ]]; then
  if [[ -z "$TOOLKIT_DEB_DIR" || ! -d "$TOOLKIT_DEB_DIR" ]]; then
    echo "Toolkit deb dir not found: $TOOLKIT_DEB_DIR" >&2
    echo "Provide --toolkit-deb-dir or place deb files under: $OFFLINE_ROOT/toolkit-debs" >&2
    exit 1
  fi
  if ! has_debs "$TOOLKIT_DEB_DIR"; then
    echo "No .deb files found in toolkit dir: $TOOLKIT_DEB_DIR" >&2
    exit 1
  fi
fi

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "Warning: non-Ubuntu system detected: ${ID:-unknown}"
  fi
  if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    echo "Warning: expected Ubuntu 24.04, detected ${VERSION_ID:-unknown}"
  fi
fi

if [[ $INSTALL_DRIVER -eq 1 && $DRY_RUN -eq 0 ]]; then
  KERNEL_HEADERS_PKG="linux-headers-$(uname -r)"
  if ! dpkg -s "$KERNEL_HEADERS_PKG" >/dev/null 2>&1; then
    echo "Kernel headers missing: $KERNEL_HEADERS_PKG"
    echo "Install matching kernel headers first (offline package)." >&2
    exit 1
  fi
fi

echo "Offline root: $OFFLINE_ROOT"
echo "Driver runfile: ${DRIVER_RUNFILE:-<skip>}"
echo "CUDA runfile: ${CUDA_RUNFILE:-<skip>}"
echo "Toolkit deb dir: ${TOOLKIT_DEB_DIR:-<skip>}"

echo "Stopping services that may lock NVIDIA modules..."
run_cmd "systemctl stop docker || true"
run_cmd "systemctl stop nvidia-persistenced || true"
run_cmd "systemctl stop display-manager || true"

if [[ $INSTALL_DRIVER -eq 1 ]]; then
  echo "Installing NVIDIA driver from runfile: $DRIVER_RUNFILE"
  run_cmd "chmod +x '$DRIVER_RUNFILE'"
  run_cmd "sh '$DRIVER_RUNFILE' --silent --dkms --disable-nouveau --no-questions --install-libglvnd"
fi

if [[ $INSTALL_CUDA -eq 1 ]]; then
  echo "Installing CUDA toolkit from runfile: $CUDA_RUNFILE"
  run_cmd "chmod +x '$CUDA_RUNFILE'"
  run_cmd "sh '$CUDA_RUNFILE' --silent --toolkit --override"

  if [[ $DRY_RUN -eq 0 ]]; then
    latest_cuda_dir="$(ls -d /usr/local/cuda-* 2>/dev/null | sort -V | tail -n1 || true)"
    if [[ -n "$latest_cuda_dir" ]]; then
      ln -sfn "$latest_cuda_dir" /usr/local/cuda
    fi
  fi
fi

if [[ "$INSTALL_TOOLKIT_MODE" == "on" ]]; then
  echo "Installing nvidia-container-toolkit from local deb dir: $TOOLKIT_DEB_DIR"
  # First pass may fail due to dependency ordering; second pass usually resolves when all debs are present.
  run_cmd "dpkg -i '$TOOLKIT_DEB_DIR'/*.deb || true"
  run_cmd "dpkg -i '$TOOLKIT_DEB_DIR'/*.deb"

  if command -v nvidia-ctk >/dev/null 2>&1; then
    run_cmd "nvidia-ctk runtime configure --runtime=docker"
  fi
fi

if [[ $DRY_RUN -eq 0 ]]; then
  cat >/etc/profile.d/cuda-path.sh <<'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
EOF
fi

echo "Restarting Docker..."
run_cmd "systemctl daemon-reload"
run_cmd "systemctl restart docker || true"

echo ""
echo "Upgrade script completed."
echo "Next steps:"
echo "1) Reboot server: sudo reboot"
echo "2) Verify: nvidia-smi"
echo "3) Verify docker GPU: docker run --rm --gpus all nvidia/cuda:12.2.2-base-ubuntu22.04 nvidia-smi"
