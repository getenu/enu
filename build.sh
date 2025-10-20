#!/bin/bash
set -e

# Determine project root (where this script is located)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Configuration
NIM_DIR="$PROJECT_ROOT/vendor/nim"
NIM_BIN="$NIM_DIR/bin/nim"
BUILD_STATE_DIR="$PROJECT_ROOT/.build_state"
NIM_STATE_FILE="$BUILD_STATE_DIR/nim_built"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}==>${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

# Check if nim submodule exists
check_nim_submodule() {
    if [ ! -d "$NIM_DIR/.git" ]; then
        info "Nim submodule not initialized, initializing..."
        git submodule update --init --recursive vendor/nim
        success "Nim submodule initialized"
    fi
}

# Get current nim submodule commit SHA
get_nim_sha() {
    git -C "$NIM_DIR" rev-parse HEAD
}

# Check if nim needs to be built
needs_nim_build() {
    if [ ! -f "$NIM_BIN" ]; then
        return 0  # true - needs build
    fi

    if [ ! -f "$NIM_STATE_FILE" ]; then
        return 0  # true - needs build
    fi

    local current_sha=$(get_nim_sha)
    local built_sha=$(cat "$NIM_STATE_FILE" 2>/dev/null || echo "")

    if [ "$current_sha" != "$built_sha" ]; then
        return 0  # true - needs build
    fi

    return 1  # false - doesn't need build
}

# Build nim from source
build_nim() {
    info "Building Nim compiler from source..."

    cd "$NIM_DIR"

    # Clean previous build if exists
    if [ -f "bin/nim" ]; then
        rm -rf bin csources dist
    fi

    # Build nim
    sh build_all.sh

    # Record the built SHA
    mkdir -p "$BUILD_STATE_DIR"
    get_nim_sha > "$NIM_STATE_FILE"

    cd "$PROJECT_ROOT"
    success "Nim compiler built successfully"
}

# Verify build environment
verify_environment() {
    local platform=$(uname -s)

    case "$platform" in
        Darwin)
            # macOS
            if ! xcode-select -p &> /dev/null; then
                error "Xcode Command Line Tools not installed. Install with: xcode-select --install"
            fi

            if ! command -v scons &> /dev/null; then
                error "scons not found. Install with: brew install scons\nOr see: https://docs.godotengine.org/en/stable/contributing/development/compiling/compiling_for_macos.html"
            fi

            success "macOS build environment verified"
            ;;
        Linux)
            if ! command -v scons &> /dev/null; then
                error "scons not found. Install with your package manager (e.g., apt install scons)\nOr see: https://docs.godotengine.org/en/stable/contributing/development/compiling/compiling_for_linuxbsd.html"
            fi

            success "Linux build environment verified"
            ;;
        *)
            warn "Unknown platform: $platform"
            ;;
    esac
}

# Main build logic
main() {
    local build_type="${1:-dev}"

    case "$build_type" in
        dev)
            NIMBLE_TASK="build_all"
            ;;
        dist)
            NIMBLE_TASK="dist_all"
            ;;
        *)
            error "Unknown build type: $build_type\nUsage: $0 [dev|dist]"
            ;;
    esac

    info "Starting $build_type build..."

    # Verify required paths are in PATH
    "$PROJECT_ROOT/tools/verify_paths.sh"

    # Check and initialize nim submodule
    check_nim_submodule

    # Build nim if needed
    if needs_nim_build; then
        build_nim
    else
        success "Nim compiler already built ($(get_nim_sha | cut -c1-7))"
    fi

    # Verify environment
    verify_environment

    # Setup nimble dependencies
    info "Setting up nimble dependencies..."
    nimble setup -y

    # Run nimble task
    info "Running nimble $NIMBLE_TASK..."
    nimble $NIMBLE_TASK -y

    success "Build completed successfully!"
}

# Run main
main "$@"
