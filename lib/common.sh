#!/bin/bash
# ==============================================================================
# Common Configuration and Utility Functions
# ==============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }

# Workspace configuration
WORKSPACE_DIR="../gki_build_workspace"
KERNEL_SRC="$WORKSPACE_DIR/common"
CLANG_DIR="$WORKSPACE_DIR/prebuilts/clang/host/linux-x86"
CLANG_VER="clang-r547379"
STAMP_BZL="$WORKSPACE_DIR/build/kernel/kleaf/impl/stamp.bzl"

# Get script directory
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# Cleanup function (can be overridden by other modules)
cleanup() {
    # This will be extended by temp_monitor.sh
    true
}

# Setup cleanup trap
trap cleanup EXIT

