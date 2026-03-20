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

    # 1. Enable SUSFS in gki_defconfig
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    log "Enabling CONFIG_SUSFS in $GKI_DEFCONFIG..."
    if ! grep -q "CONFIG_SUSFS=y" "$GKI_DEFCONFIG"; then
        echo "CONFIG_SUSFS=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_SUSFS=y to gki_defconfig"
    fi

    # 2. Patch KernelSU for SUSFS (if KernelSU is enabled)
    # The --ksu flag is handled in build_gki.sh, we check ENABLE_KSU here
    if [ "$ENABLE_KSU" = true ]; then
        log "KernelSU is enabled, applying SUSFS patch for KernelSU..."

        # Check if KernelSU directory exists
        if [ -d "$KERNEL_SRC/KernelSU" ]; then
            # The patch should be in the cloned susfs4ksu repo, which is ../susfs4ksu relative to kernel source
            KSU_SUSFS_PATCH="$KERNEL_SRC/../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"

            if [ -f "$KSU_SUSFS_PATCH" ]; then
                cd "$KERNEL_SRC/KernelSU"
                log "Applying 10_enable_susfs_for_ksu.patch to KernelSU..."
                if patch -p1 < "$KSU_SUSFS_PATCH"; then
                    log "✓ KernelSU patched for SUSFS support"
                else
                    error "Failed to apply SUSFS patch to KernelSU!"
                    # We don't exit here, as the kernel might still build without KSU SUSFS support
                fi
                cd "$KERNEL_SRC"
            else
                warn "SUSFS patch for KernelSU not found at $KSU_SUSFS_PATCH"
            fi
        else
            warn "KernelSU directory not found, skipping KSU SUSFS patch."
        fi
    fi

    log "✓ SUSFS setup complete."
}
