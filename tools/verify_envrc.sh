#!/usr/bin/env bash
# Verify that paths from .envrc are in PATH
# This script can be called by both build.sh and nimble tasks

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -f "$PROJECT_ROOT/.envrc" ]; then
  echo "*** ERROR: .envrc not found ***"
  echo ""
  echo "Please ensure .envrc exists and has been loaded with direnv."
  echo "For direnv installation and setup, see: https://direnv.net/docs/installation.html"
  echo ""
  exit 1
fi

missing_paths=()

# Parse .envrc for PATH_add lines
while IFS= read -r line; do
  if [[ $line =~ ^[[:space:]]*PATH_add[[:space:]]+(.+)$ ]]; then
    path_to_add="${BASH_REMATCH[1]}"
    full_path="$PROJECT_ROOT/$path_to_add"

    # Check if this path is in the current PATH
    if [[ ":$PATH:" != *":$full_path:"* ]]; then
      missing_paths+=("$full_path")
    fi
  fi
done < "$PROJECT_ROOT/.envrc"

if [ ${#missing_paths[@]} -gt 0 ]; then
  echo ""
  echo "*** ERROR: Required paths not found in PATH ***"
  echo ""
  echo "The following paths are missing from your PATH:"
  for path in "${missing_paths[@]}"; do
    echo "  - $path"
  done
  echo ""
  echo "Please add these paths to your PATH, or use direnv to manage them automatically."
  echo "For direnv installation and setup, see: https://direnv.net/docs/installation.html"
  echo ""
  exit 1
fi
