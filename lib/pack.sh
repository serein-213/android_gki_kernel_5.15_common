#!/bin/bash
# ==============================================================================
# Packaging Module
# ==============================================================================

# Source common functions
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/common.sh"

# Find the built kernel Image
find_kernel_image() {
    local image_path=$(find "$WORKSPACE_DIR/out" -name Image 2>/dev/null | head -n 1)
    if [ -z "$image_path" ]; then
        # Try alternative locations
        image_path=$(find "$WORKSPACE_DIR" -name Image -path "*/out/*" 2>/dev/null | head -n 1)
    fi
    if [ -z "$image_path" ]; then
        error "Could not find built Kernel Image in $WORKSPACE_DIR"
        error "Please run the build first or ensure the build completed successfully."
        exit 1
    fi
    echo "$image_path"
}

# Pack Image.gz and boot.img
pack_image_artifacts() {
    log "Packing Image.gz and boot.img..."
    
    # Find kernel image
    IMAGE_PATH=$(find_kernel_image)
    echo "Kernel Image: $IMAGE_PATH"
    
    # Get kernel source root directory (parent of lib directory)
    KERNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    OUT_DIR="$KERNEL_ROOT/out"
    
    # Create output directory
    mkdir -p "$OUT_DIR"
    log "Output directory: $OUT_DIR"
    
    # 1. Generate Image.gz
    log "Creating Image.gz..."
    cp "$IMAGE_PATH" "$OUT_DIR/Image"
    gzip -f "$OUT_DIR/Image"
    log "✓ Image.gz created: $OUT_DIR/Image.gz"
    
    # 2. Generate boot.img
    log "Creating boot.img..."
    BOOT_IMG="$OUT_DIR/boot.img"
    
    # Check if mkbootimg is available
    if ! command -v mkbootimg &> /dev/null; then
        warn "mkbootimg not found. Trying to use from Android build tools..."
        # Try to find mkbootimg in common Android locations
        if [ -f "$WORKSPACE_DIR/prebuilts/misc/linux-x86/libufdt/mkbootimg.py" ]; then
            MKBOOTIMG_CMD="python3 $WORKSPACE_DIR/prebuilts/misc/linux-x86/libufdt/mkbootimg.py"
        else
            error "mkbootimg not found. Please install Android build tools or set up mkbootimg."
            exit 1
        fi
    else
        MKBOOTIMG_CMD="mkbootimg"
    fi
    
    # Create boot.img with header version 4 (GKI Android 13)
    $MKBOOTIMG_CMD \
        --kernel "$IMAGE_PATH" \
        --header_version 4 \
        --output "$BOOT_IMG"
    
    # Add AVB hash footer if avbtool is available
    if command -v avbtool &> /dev/null; then
        log "Adding AVB hash footer..."
        IMAGE_SIZE=$(stat -c%s "$BOOT_IMG")
        PADDING=$((2 * 1024 * 1024))  # 2MB
        PARTITION_SIZE=$((IMAGE_SIZE + PADDING))
        avbtool add_hash_footer \
            --image "$BOOT_IMG" \
            --partition_name boot \
            --partition_size "$PARTITION_SIZE"
        log "✓ AVB footer added"
    else
        warn "avbtool not found. boot.img created without AVB footer."
    fi
    
    log "✓ boot.img created: $BOOT_IMG"
}

# Pack anykernel.zip
pack_anykernel() {
    log "Packing anykernel.zip..."
    
    # Find kernel image
    IMAGE_PATH=$(find_kernel_image)
    
    # Get kernel source root directory (parent of lib directory)
    KERNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    OUT_DIR="$KERNEL_ROOT/out"
    
    # Create output directory
    mkdir -p "$OUT_DIR"
    
    ANYKERNEL_DIR="$OUT_DIR/anykernel_tmp"
    rm -rf "$ANYKERNEL_DIR"
    mkdir -p "$ANYKERNEL_DIR/META-INF/com/google/android"
    
    # Create update-binary script for AnyKernel
    cat > "$ANYKERNEL_DIR/META-INF/com/google/android/update-binary" <<'EOF'
#!/sbin/sh
# AnyKernel installer script for GKI kernel

# Handle different parameter formats:
# Standard AnyKernel3: $1=OUTFD, $2=ZIPFILE
# HorizonKernelFlasher: $1=3, $2=1, $3=ZIPFILE
if [ -n "$3" ] && [ -f "$3" ]; then
    # HorizonKernelFlasher format: sh update-binary 3 1 "zip路径"
    OUTFD=$1
    ZIPFILE=$3
elif [ -n "$2" ] && [ -f "$2" ]; then
    # Standard AnyKernel3 format: sh update-binary OUTFD ZIPFILE
    OUTFD=$1
    ZIPFILE=$2
else
    # Fallback: try to use what we have
    OUTFD=${1:-3}
    ZIPFILE=${2:-$3}
fi

ui_print() {
    echo "ui_print $1" >&$OUTFD
    echo "ui_print" >&$OUTFD
}

ui_print " "
ui_print "AnyKernel GKI Kernel Installer"
ui_print " "

# Extract kernel image
ui_print "Extracting kernel..."
TMPDIR=/tmp/anykernel_$$
mkdir -p "$TMPDIR"
cd "$TMPDIR"
unzip -o "$ZIPFILE" "Image" || {
    ui_print "Error: Failed to extract Image from zip"
    exit 1
}

if [ ! -f "$TMPDIR/Image" ]; then
    ui_print "Error: Image not found in zip"
    exit 1
fi

# Enhanced boot partition detection (boot partition only)
find_boot_partition() {
    local boot_part=""
    local slot_suffix=""
    
    # Helper function to check if path exists (works with symlinks and block devices)
    check_path() {
        local p="$1"
        # Try multiple methods to check if path exists
        if [ -e "$p" ] || [ -L "$p" ] || [ -b "$p" ] || [ -c "$p" ]; then
            return 0
        fi
        # Also try using ls (more reliable in some recovery environments)
        if ls "$p" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    }
    
    # Method 1: Direct check for A/B partitions (boot_a and boot_b) - most reliable
    # Check boot_a first (slot a) - try multiple paths
    for path in \
        "/dev/block/by-name/boot_a" \
        "/dev/block/bootdevice/by-name/boot_a" \
        "/dev/block/platform/*/by-name/boot_a" \
        "/dev/block/platform/*/*/by-name/boot_a"; do
        # Expand wildcards
        for p in $path; do
            if check_path "$p"; then
                boot_part="$p"
                ui_print "Found boot partition: $boot_part"
                echo "$boot_part"
                return 0
            fi
        done
    done
    
    # Check boot_b (slot b) - try multiple paths
    for path in \
        "/dev/block/by-name/boot_b" \
        "/dev/block/bootdevice/by-name/boot_b" \
        "/dev/block/platform/*/by-name/boot_b" \
        "/dev/block/platform/*/*/by-name/boot_b"; do
        # Expand wildcards
        for p in $path; do
            if check_path "$p"; then
                boot_part="$p"
                ui_print "Found boot partition: $boot_part"
                echo "$boot_part"
                return 0
            fi
        done
    done
    
    # Method 2: Use find to search for boot_a or boot_b (A/B partitions)
    if [ -d "/dev/block" ]; then
        # Try boot_a first
        boot_part=$(find /dev/block -name "boot_a" 2>/dev/null | head -n 1)
        if [ -n "$boot_part" ] && check_path "$boot_part"; then
            ui_print "Found boot partition via find: $boot_part"
            echo "$boot_part"
            return 0
        fi
        # Try boot_b
        boot_part=$(find /dev/block -name "boot_b" 2>/dev/null | head -n 1)
        if [ -n "$boot_part" ] && check_path "$boot_part"; then
            ui_print "Found boot partition via find: $boot_part"
            echo "$boot_part"
            return 0
        fi
    fi
    
    # Method 3: Check common by-name paths (non-A/B devices)
    for path in \
        "/dev/block/bootdevice/by-name/boot" \
        "/dev/block/by-name/boot"; do
        if check_path "$path"; then
            boot_part="$path"
            ui_print "Found boot partition: $boot_part"
            echo "$boot_part"
            return 0
        fi
    done
    
    # Method 4: Use find to search for boot (non-A/B)
    if [ -d "/dev/block" ]; then
        boot_part=$(find /dev/block -name "boot" 2>/dev/null | head -n 1)
        if [ -n "$boot_part" ] && check_path "$boot_part"; then
            ui_print "Found boot partition via find: $boot_part"
            echo "$boot_part"
            return 0
        fi
    fi
    
    # Method 5: Try getprop (Android system property) - may not work in all recovery environments
    if command -v getprop &> /dev/null; then
        slot_suffix=$(getprop ro.boot.slot_suffix 2>/dev/null || echo "")
        local boot_dev=$(getprop ro.boot.bootdevice 2>/dev/null || echo "")
        
        if [ -n "$boot_dev" ]; then
            # Try with slot suffix first
            if [ -n "$slot_suffix" ]; then
                boot_part="/dev/block/platform/$boot_dev/by-name/boot${slot_suffix}"
                if check_path "$boot_part"; then
                    ui_print "Found boot partition via getprop: $boot_part"
                    echo "$boot_part"
                    return 0
                fi
            fi
            # Try without slot suffix
            boot_part="/dev/block/platform/$boot_dev/by-name/boot"
            if check_path "$boot_part"; then
                ui_print "Found boot partition via getprop: $boot_part"
                echo "$boot_part"
                return 0
            fi
        fi
    fi
    
    # Method 6: Try platform paths with wildcard expansion
    if [ -d "/dev/block/platform" ]; then
        for plat_dir in /dev/block/platform/*/by-name; do
            if [ -d "$plat_dir" ]; then
                # Check boot_a and boot_b first
                for name in boot_a boot_b boot; do
                    if check_path "$plat_dir/$name"; then
                        boot_part="$plat_dir/$name"
                        ui_print "Found boot partition: $boot_part"
                        echo "$boot_part"
                        return 0
                    fi
                done
            fi
        done
    fi
    
    return 1
}

# Try to use magiskboot if available (most reliable method)
if command -v magiskboot &> /dev/null; then
    ui_print "Using magiskboot to repack boot image..."
    
    # Debug: List available boot partitions BEFORE searching
    ui_print "Debug: Checking available boot partitions..."
    if [ -d "/dev/block/by-name" ]; then
        for p in /dev/block/by-name/boot*; do
            if [ -e "$p" ] || [ -L "$p" ] || [ -b "$p" ]; then
                ui_print "  Found: $p"
            fi
        done
    fi
    if [ -d "/dev/block/bootdevice/by-name" ]; then
        for p in /dev/block/bootdevice/by-name/boot*; do
            if [ -e "$p" ] || [ -L "$p" ] || [ -b "$p" ]; then
                ui_print "  Found: $p"
            fi
        done
    fi
    
    # Find boot partition using enhanced detection
    BOOT_PARTITION=$(find_boot_partition)
    
    if [ -z "$BOOT_PARTITION" ]; then
        ui_print "Error: Boot partition not found"
        ui_print "Tried multiple detection methods"
        ui_print "Please check your device's partition layout"
        exit 1
    fi
    
    # Verify the partition exists (try multiple methods)
    if [ ! -e "$BOOT_PARTITION" ] && [ ! -L "$BOOT_PARTITION" ] && [ ! -b "$BOOT_PARTITION" ]; then
        ui_print "Error: Boot partition not accessible: $BOOT_PARTITION"
        ui_print "Please check your device's partition layout"
        exit 1
    fi
    
    ui_print "Backing up boot partition..."
    dd if="$BOOT_PARTITION" of="$TMPDIR/boot.img" bs=4096 || {
        ui_print "Error: Failed to read boot partition"
        exit 1
    }
    
    ui_print "Unpacking boot image..."
    magiskboot unpack "$TMPDIR/boot.img" || {
        ui_print "Error: Failed to unpack boot image"
        exit 1
    }
    
    ui_print "Replacing kernel..."
    cp "$TMPDIR/Image" "$TMPDIR/kernel" || {
        ui_print "Error: Failed to copy kernel"
        exit 1
    }
    
    ui_print "Repacking boot image..."
    magiskboot repack "$TMPDIR/boot.img" "$TMPDIR/boot_new.img" || {
        ui_print "Error: Failed to repack boot image"
        exit 1
    }
    
    ui_print "Flashing new boot image..."
    dd if="$TMPDIR/boot_new.img" of="$BOOT_PARTITION" bs=4096 || {
        ui_print "Error: Failed to write boot partition"
        exit 1
    }
    
    ui_print " "
    ui_print "Kernel flashed successfully!"
    rm -rf "$TMPDIR"
    exit 0
fi

# Fallback: Try to use AIK (Android Image Kitchen) if available
if [ -d "/tmp/AIK" ] || [ -d "/data/local/tmp/AIK" ]; then
    AIK_DIR="/tmp/AIK"
    [ -d "/data/local/tmp/AIK" ] && AIK_DIR="/data/local/tmp/AIK"
    
    ui_print "Using Android Image Kitchen..."
    # AIK method would go here
    ui_print "AIK method not fully implemented"
fi

# Final fallback: Direct flash (risky, device-specific)
ui_print "Warning: Using direct flash method (may not work on all devices)"
ui_print "This method is device-specific and may cause bootloop!"

BOOT_PARTITION=$(find_boot_partition)

if [ -z "$BOOT_PARTITION" ] || [ ! -e "$BOOT_PARTITION" ]; then
    ui_print "Error: Boot partition not found"
    ui_print "Please use magiskboot or AIK method"
    ui_print "Or check your device's partition layout manually"
    exit 1
fi

ui_print "Direct flashing kernel (offset may vary by device)..."
# This is device-specific and may need adjustment
dd if="$TMPDIR/Image" of="$BOOT_PARTITION" bs=4096 seek=2048 conv=notrunc || {
    ui_print "Error: Direct flash failed"
    ui_print "Please use a recovery with magiskboot support"
    exit 1
}

ui_print " "
ui_print "Kernel flashed (direct method)"
ui_print "If device doesn't boot, restore from backup!"

rm -rf "$TMPDIR"
EOF

    chmod +x "$ANYKERNEL_DIR/META-INF/com/google/android/update-binary"
    
    # Copy kernel image to anykernel directory
    cp "$IMAGE_PATH" "$ANYKERNEL_DIR/Image"
    
    # Create anykernel.zip
    cd "$ANYKERNEL_DIR"
    zip -r "$OUT_DIR/anykernel.zip" . > /dev/null
    cd "$KERNEL_ROOT"
    rm -rf "$ANYKERNEL_DIR"
    
    log "✓ anykernel.zip created: $OUT_DIR/anykernel.zip"
}

