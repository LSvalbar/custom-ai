#!/usr/bin/env bash
set -euo pipefail

MODE="report"
APPLY=0
CREATE_VENV=0
VENV_PATH="/opt/venvs/py312"
PYTHON_BIN="/usr/bin/python3.12"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/python-env-reconcile.sh [--cleanup-source] [--apply] [--create-venv] [--venv-path <path>] [--python-bin <path>]

Modes:
  default          Report only (safe, no changes)
  --cleanup-source Remove source-installed Python artifacts under /usr/local (dry-run unless --apply)

Options:
  --apply          Execute deletion/creation commands (without this: dry-run)
  --create-venv    Create a unified Python 3.12 venv after report/cleanup
  --venv-path      Venv path (default: /opt/venvs/py312)
  --python-bin     Python binary to create venv (default: /usr/bin/python3.12)
  -h, --help       Show help

Examples:
  bash scripts/python-env-reconcile.sh
  bash scripts/python-env-reconcile.sh --cleanup-source
  bash scripts/python-env-reconcile.sh --cleanup-source --apply
  bash scripts/python-env-reconcile.sh --cleanup-source --apply --create-venv
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup-source)
      MODE="cleanup-source"
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --create-venv)
      CREATE_VENV=1
      shift
      ;;
    --venv-path)
      VENV_PATH="$2"
      shift 2
      ;;
    --python-bin)
      PYTHON_BIN="$2"
      shift 2
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
  local cmd="$1"
  if [[ $APPLY -eq 1 ]]; then
    eval "$cmd"
  else
    echo "[dry-run] $cmd"
  fi
}

is_dpkg_owned() {
  local p="$1"
  dpkg -S "$p" >/dev/null 2>&1
}

classify_path() {
  local real="$1"
  if [[ "$real" == /usr/bin/* || "$real" == /bin/* ]]; then
    if is_dpkg_owned "$real"; then
      echo "system-package"
    else
      echo "system-unmanaged"
    fi
    return
  fi

  if [[ "$real" == /usr/local/* ]]; then
    if is_dpkg_owned "$real"; then
      echo "local-package"
    else
      echo "local-source"
    fi
    return
  fi

  if [[ "$real" == *"/.pyenv/"* || "$real" == *"/miniconda"* || "$real" == *"/anaconda"* || "$real" == *"/.conda/"* ]]; then
    echo "user-managed"
    return
  fi

  echo "other"
}

version_of() {
  local bin="$1"
  local name
  name="$(basename "$bin")"
  if [[ "$name" == pip* ]]; then
    "$bin" --version 2>/dev/null | awk '{print $2}' || true
  else
    "$bin" -V 2>&1 | awk '{print $2}' || true
  fi
}

owner_of() {
  local real="$1"
  dpkg -S "$real" 2>/dev/null | head -n1 || true
}

declare -A CANDIDATES=()

collect_cmd_paths() {
  local cmd="$1"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    CANDIDATES["$p"]=1
  done < <(command -v -a "$cmd" 2>/dev/null || true)
}

for cmd in python python3 python3.12 pip pip3 pip3.12; do
  collect_cmd_paths "$cmd"
done

for pattern in /usr/bin/python3* /usr/local/bin/python3* /usr/local/bin/pip3* /usr/local/bin/python /usr/local/bin/pip; do
  for p in $pattern; do
    [[ -e "$p" ]] || continue
    CANDIDATES["$p"]=1
  done
done

echo "=== Python Runtime Report ==="
printf "%-35s %-35s %-10s %-16s %s\n" "BINARY" "REALPATH" "VERSION" "CLASS" "OWNER"

SOURCE_BINARIES=()

for bin in "${!CANDIDATES[@]}"; do
  [[ -e "$bin" ]] || continue
  real="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
  [[ -e "$real" ]] || continue
  class="$(classify_path "$real")"
  ver="$(version_of "$bin")"
  owner="$(owner_of "$real")"
  printf "%-35s %-35s %-10s %-16s %s\n" "$bin" "$real" "${ver:-unknown}" "$class" "${owner:--}"

  base="$(basename "$bin")"
  if [[ "$class" == "local-source" && "$bin" == /usr/local/bin/* ]]; then
    if [[ "$base" =~ ^(python([0-9.]*)?|pip([0-9.]*)?|pydoc([0-9.]*)?|idle([0-9.]*)?|2to3([0-9.]*)?)$ ]]; then
      SOURCE_BINARIES+=("$bin")
    fi
  fi
done | sort

echo
echo "Default python3:"
if command -v python3 >/dev/null 2>&1; then
  echo "  which python3 -> $(command -v python3)"
  echo "  realpath      -> $(readlink -f "$(command -v python3)")"
  echo "  version       -> $(python3 --version 2>/dev/null || true)"
else
  echo "  python3 not found"
fi

if [[ "$MODE" == "cleanup-source" ]]; then
  echo
  echo "=== Cleanup Plan (source-installed under /usr/local) ==="

  if [[ ${#SOURCE_BINARIES[@]} -eq 0 ]]; then
    echo "No local-source python/pip binaries found in /usr/local/bin."
  else
    for b in "${SOURCE_BINARIES[@]}"; do
      run_cmd "sudo rm -f -- '$b'"
    done
  fi

  for d in /usr/local/lib/python3* /usr/local/include/python3*; do
    [[ -e "$d" ]] || continue
    if ! is_dpkg_owned "$d"; then
      run_cmd "sudo rm -rf -- '$d'"
    fi
  done

  for m in /usr/local/share/man/man1/python3* /usr/local/share/man/man1/pip3*; do
    [[ -e "$m" ]] || continue
    run_cmd "sudo rm -f -- '$m'"
  done

  run_cmd "hash -r"
fi

if [[ $CREATE_VENV -eq 1 ]]; then
  echo
  echo "=== Unified Venv Setup ==="
  if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "Python binary not found/executable: $PYTHON_BIN"
    exit 1
  fi

  run_cmd "sudo mkdir -p '$(dirname "$VENV_PATH")'"
  run_cmd "sudo '$PYTHON_BIN' -m venv '$VENV_PATH'"
  run_cmd "sudo '$VENV_PATH/bin/python' -m pip install -U pip"
  echo "Venv target: $VENV_PATH"
fi

if [[ $APPLY -eq 0 ]]; then
  echo
  echo "Dry-run only. Add --apply to execute changes."
fi
