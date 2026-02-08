#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES_DIR="$ROOT_DIR/images"
INDEX_FILE="$IMAGES_DIR/index.tsv"

if [[ $# -eq 0 ]]; then
  COMPONENTS=("all")
else
  COMPONENTS=("$@")
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

declare -A TAR_SET=()

if [[ -f "$INDEX_FILE" ]]; then
  while IFS=$'\t' read -r component tar_file stable_image release_image release_tag updated_at; do
    if [[ "$component" == "component" || -z "$component" ]]; then
      continue
    fi

    if contains_component "$component" "${COMPONENTS[@]}"; then
      TAR_SET["$tar_file"]=1
    fi
  done < "$INDEX_FILE"
else
  for f in "$IMAGES_DIR"/*.tar; do
    [[ -e "$f" ]] || continue
    TAR_SET["$(basename "$f")"]=1
  done
fi

if [[ ${#TAR_SET[@]} -eq 0 ]]; then
  echo "No image tar matched requested component(s): ${COMPONENTS[*]}"
  exit 1
fi

mapfile -t TAR_FILES < <(printf '%s\n' "${!TAR_SET[@]}" | sort)

loaded_count=0

for tar_name in "${TAR_FILES[@]}"; do
  tar_path="$IMAGES_DIR/$tar_name"
  if [[ ! -f "$tar_path" ]]; then
    echo "Skipping missing tar: $tar_path"
    continue
  fi

  echo "Loading $tar_path"
  docker load -i "$tar_path"
  loaded_count=$((loaded_count + 1))
done

if [[ $loaded_count -eq 0 ]]; then
  echo "No image tar was loaded. Check index and tar files under $IMAGES_DIR"
  exit 1
fi
