#!/bin/bash
# ==============================================================================
# Version Customization Module
# ==============================================================================

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Customize kernel version
customize_version() {
    BUILD_DATE=$(date +%Y%m%d)
    CUSTOM_VERSION="-serein-android13-$BUILD_DATE"
    
    log "Customizing Kernel Version to: $CUSTOM_VERSION"
    
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    
    # Update CONFIG_LOCALVERSION in gki_defconfig
    # Replace existing CONFIG_LOCALVERSION="..." with our custom version
    if grep -q "CONFIG_LOCALVERSION=" "$GKI_DEFCONFIG"; then
        sed -i 's/CONFIG_LOCALVERSION=".*"/CONFIG_LOCALVERSION="'"$CUSTOM_VERSION"'"/' "$GKI_DEFCONFIG"
    else
        echo "CONFIG_LOCALVERSION=\"$CUSTOM_VERSION\"" >> "$GKI_DEFCONFIG"
    fi
    
    # Remove '-maybe-dirty' suffix by hacking stamp.bzl
    # The Bazel build system (Kleaf) forces LOCALVERSION="-maybe-dirty" for non-stamped builds.
    # We change it to empty string so it doesn't append anything, and lets CONFIG_LOCALVERSION take precedence.
    if [ -f "$STAMP_BZL" ]; then
        log "Patching stamp.bzl to remove -maybe-dirty..."
        sed -i 's/export LOCALVERSION="-maybe-dirty"/export LOCALVERSION=""/' "$STAMP_BZL"
    else
        warn "stamp.bzl not found at $STAMP_BZL. Version might still include -maybe-dirty."
    fi
}

