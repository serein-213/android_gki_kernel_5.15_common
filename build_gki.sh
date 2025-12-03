#!/bin/bash
set -e

# ==============================================================================
# GKI Kernel Build Script for Xiaomi 13 (fuxi)
# Environment: Arch Linux / Android 13 / Kernel 5.15
# ==============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Load all modules
source "$LIB_DIR/common.sh"
source "$LIB_DIR/temp_monitor.sh"
source "$LIB_DIR/pack.sh"
source "$LIB_DIR/config_fixes.sh"
source "$LIB_DIR/workspace.sh"
source "$LIB_DIR/version.sh"
source "$LIB_DIR/ccache.sh"

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
SKIP_BUILD=false
PACK_AK3=false
PACK_IMG=false

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --ak3          Only pack anykernel.zip (skip build)"
    echo "  --img          Only pack boot.img and Image.gz (skip build)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Full build and pack all artifacts"
    echo "  $0 --ak3       # Only pack anykernel.zip (requires existing build)"
    echo "  $0 --img       # Only pack boot.img and Image.gz (requires existing build)"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ak3)
            PACK_AK3=true
            SKIP_BUILD=true
            shift
            ;;
        --img)
            PACK_IMG=true
            SKIP_BUILD=true
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# If no specific pack option is set, pack everything
if [ "$SKIP_BUILD" = false ]; then
    PACK_AK3=true
    PACK_IMG=true
fi

# ==============================================================================
# MAIN BUILD PROCESS
# ==============================================================================

# 1. Dependency Check
check_dependencies

# 2. Workspace Setup
setup_workspace

# 3. Apply Configuration Fixes
apply_config_fixes

# 4. Version Customization
customize_version

# 5. CCache Configuration
configure_ccache

# 6. Build (if not skipped)
if [ "$SKIP_BUILD" = false ]; then
    log "Starting Bazel Build..."

    # Start temperature monitoring
    start_temp_monitor

    # Show initial temperature
    INITIAL_TEMP=$(get_cpu_temp)
    log "Initial CPU temperature: ${INITIAL_TEMP}°C"

    # Note: ccache is configured via build.config.common
    # For Bazel builds, we also pass environment variables via --action_env
    # This ensures ccache settings are available to all build actions
    BAZEL_CCACHE_FLAGS=$(get_ccache_flags)
    if [ -n "$BAZEL_CCACHE_FLAGS" ]; then
        log "ccache environment variables will be passed to Bazel build actions"
    fi

    # Set build timestamp for kernel version string
    # This fixes the "Thu Jan 1 00:00:00 UTC 1970" issue
    # SOURCE_DATE_EPOCH is used for reproducible builds, but we want actual build time
    BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S %Z")
    KBUILD_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
    export KBUILD_BUILD_TIMESTAMP
    # Also set SOURCE_DATE_EPOCH to current time (not 0) for proper timestamp
    export SOURCE_DATE_EPOCH=$(date +%s)

    # Pass timestamp to Bazel build actions
    BAZEL_TIMESTAMP_FLAGS="--action_env=KBUILD_BUILD_TIMESTAMP --action_env=SOURCE_DATE_EPOCH"

    log "Build timestamp: $BUILD_TIMESTAMP"

    cd "$WORKSPACE_DIR"
    tools/bazel build $BAZEL_CCACHE_FLAGS $BAZEL_TIMESTAMP_FLAGS //common:kernel_aarch64_dist

    # Show ccache statistics after build
    show_ccache_stats

    # Stop temperature monitoring and show summary
    stop_temp_monitor
    
    # Restore .config file if it was moved
    SOURCE_DIR="$(realpath ../android_gki_kernel_5.15_common)"
    CONFIG_BACKUP="$SOURCE_DIR/.config.build_backup"
    if [ -f "$CONFIG_BACKUP" ]; then
        log "Restoring .config file..."
        mv "$CONFIG_BACKUP" "$SOURCE_DIR/.config"
        log "✓ .config restored"
    fi

    log "Build Complete!"
else
    log "Skipping build (pack-only mode)"
fi

# Find and verify kernel image
IMAGE_PATH=$(find_kernel_image)
echo "Kernel Image: $IMAGE_PATH"

# Verify version
log "Verifying Kernel Version..."
if [ -f "$IMAGE_PATH" ]; then
    strings "$IMAGE_PATH" | grep "Linux version" | head -n 1
fi

# ==============================================================================
# POST-BUILD: Generate Output Artifacts
# ==============================================================================
OUT_DIR="$SCRIPT_DIR/out"

# Pack artifacts based on parameters
if [ "$PACK_IMG" = true ]; then
    pack_image_artifacts
fi

if [ "$PACK_AK3" = true ]; then
    pack_anykernel
fi

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Artifacts Generated:${NC}"
echo -e "${GREEN}========================================${NC}"
if [ "$PACK_IMG" = true ]; then
    echo -e "  ${CYAN}Image.gz:${NC}      $OUT_DIR/Image.gz"
    echo -e "  ${CYAN}boot.img:${NC}      $OUT_DIR/boot.img"
fi
if [ "$PACK_AK3" = true ]; then
    echo -e "  ${CYAN}anykernel.zip:${NC} $OUT_DIR/anykernel.zip"
fi
echo -e "${GREEN}========================================${NC}"
