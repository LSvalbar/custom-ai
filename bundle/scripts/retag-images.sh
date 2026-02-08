#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="$ROOT_DIR/images/index.tsv"

if [[ $# -eq 0 ]]; then
  COMPONENTS=("all")
else
  COMPONENTS=("$@")
fi

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Index not found: $INDEX_FILE"
  exit 0
fi

contains_component() {
  local target="$1"
  shift
  local items=("$@")
  for item in "${items[@]}"; do
    if [[ "$item" == "all" || "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

while IFS=$'\t' read -r component tar_file stable_image release_image release_tag updated_at; do
  if [[ "$component" == "component" || -z "$component" ]]; then
    continue
  fi

  if ! contains_component "$component" "${COMPONENTS[@]}"; then
    continue
  fi

  if [[ -z "$stable_image" || -z "$release_image" || "$stable_image" == "$release_image" ]]; then
    continue
  fi

  if ! docker image inspect "$release_image" >/dev/null 2>&1; then
    echo "Skip retag, release image not found locally: $release_image"
    continue
  fi

  echo "Retag $release_image -> $stable_image"
  docker tag "$release_image" "$stable_image"
done < "$INDEX_FILE"
