#!/bin/bash
# ==============================================================================
# Kernel Configuration Fixes Module
# ==============================================================================

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Apply all configuration fixes
apply_config_fixes() {
    log "Applying kernel configuration fixes..."
    
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    
    # Fix: ZRAM Configuration (Build as Module)
    log "Applying ZRAM Config Fix..."
    if grep -q "CONFIG_ZRAM=y" "$GKI_DEFCONFIG"; then
        sed -i 's/CONFIG_ZRAM=y/CONFIG_ZRAM=m/' "$GKI_DEFCONFIG"
        sed -i 's/CONFIG_ZSMALLOC=y/CONFIG_ZSMALLOC=m/' "$GKI_DEFCONFIG"
        log "Converted ZRAM to module."
    fi
    
    # Enable TMPFS_XATTR (insert after CONFIG_TMPFS=y for correct position)
    log "Enabling TMPFS_XATTR..."
    if ! grep -q "CONFIG_TMPFS_XATTR=y" "$GKI_DEFCONFIG"; then
        sed -i '/^CONFIG_TMPFS=y$/a CONFIG_TMPFS_XATTR=y' "$GKI_DEFCONFIG"
        log "Added CONFIG_TMPFS_XATTR=y"
    fi
    
    # Add ZRAM modules to system_dlkm_modules list
    MODULES_LIST="$KERNEL_SRC/android/gki_system_dlkm_modules"
    if ! grep -q "drivers/block/zram/zram.ko" "$MODULES_LIST"; then
        echo "drivers/block/zram/zram.ko" >> "$MODULES_LIST"
        echo "mm/zsmalloc.ko" >> "$MODULES_LIST"
    fi
    
    # Fix: Export 'task_is_booster' for ZRAM Module
    CPUSET_C="$KERNEL_SRC/kernel/cgroup/cpuset.c"
    if ! grep -q "EXPORT_SYMBOL_GPL(task_is_booster)" "$CPUSET_C"; then
        log "Exporting task_is_booster..."
        echo "" >> "$CPUSET_C"
        echo "EXPORT_SYMBOL_GPL(task_is_booster);" >> "$CPUSET_C"
    fi
    
    # Fix: Add symbol to KMI Allowlist (Strict Mode)
    SYMBOL_LIST="$KERNEL_SRC/android/abi_gki_aarch64"
    if ! grep -q "task_is_booster" "$SYMBOL_LIST"; then
        log "Updating KMI Symbol List..."
        echo "task_is_booster" >> "$SYMBOL_LIST"
    fi
    
    log "Configuration fixes applied."
}

