#!/usr/bin/env bash
# Verify that required project paths are in PATH
# Called by build.sh to ensure build environment is set up correctly

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

missing_paths=()

# Define required paths - common to all platforms
required_paths=(
  "vendor/nim/bin"
  "nimbledeps/bin"
)

# Add Windows-specific paths if running under MSYS/MinGW/Cygwin
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" =~ ^mingw ]]; then
  required_paths+=(
    "build_env/mingw64/bin"
    "build_env/python"
    "build_env/python/Scripts"
  )
fi

# Check each required path
for rel_path in "${required_paths[@]}"; do
  full_path="$PROJECT_ROOT/$rel_path"

  # Check if this path is in the current PATH
  if [[ ":$PATH:" != *":$full_path:"* ]]; then
    missing_paths+=("$full_path")
  fi
done

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
