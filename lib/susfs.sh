#!/bin/bash
# ==============================================================================
# SUSFS Setup Module
# ==============================================================================

# Source common functions
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/common.sh"

# Setup SUSFS
setup_susfs() {
    log "Setting up SUSFS..."

    # 1. Apply KernelSU SUSFS patch
    if [ -d "$KERNEL_SRC/KernelSU" ]; then
        log "Applying SUSFS patch to KernelSU..."
        pushd "$KERNEL_SRC/KernelSU" > /dev/null
        if patch -p1 --dry-run < "$REPO_ROOT/patches/susfs/10_enable_susfs_for_ksu.patch" > /dev/null 2>&1; then
            patch -p1 < "$REPO_ROOT/patches/susfs/10_enable_susfs_for_ksu.patch"
            log "✓ SUSFS patch applied to KernelSU"
        else
            warn "SUSFS patch to KernelSU failed (dry-run) or already applied."
        fi
        popd > /dev/null
    else
        error "KernelSU directory not found! SUSFS depends on KernelSU."
        exit 1
    fi

    # 2. Enable SUSFS in gki_defconfig
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    log "Enabling SUSFS in gki_defconfig..."
    if ! grep -q "CONFIG_KSU_SUSFS=y" "$GKI_DEFCONFIG"; then
        # Add SUSFS configs
        cat >> "$GKI_DEFCONFIG" <<EOF

# SUSFS
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
        log "✓ SUSFS configurations added to gki_defconfig"
    else
        log "SUSFS already enabled in gki_defconfig"
    fi

    log "✓ SUSFS setup complete."
}
