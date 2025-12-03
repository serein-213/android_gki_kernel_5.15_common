#!/bin/bash
set -e

# ==============================================================================
# GKI Kernel Build Script for Xiaomi 13 (fuxi)
# Environment: Arch Linux / Android 13 / Kernel 5.15
# ==============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# TEMPERATURE MONITORING CONFIGURATION
# ==============================================================================
TEMP_SENSOR="k10temp-pci-00c3"       # AMD CPU temperature sensor
TEMP_WARNING=75                       # Warning threshold (°C)
TEMP_CRITICAL=85                      # Critical threshold - pause build (°C)
TEMP_RESUME=70                        # Resume build when temp drops to (°C)
TEMP_CHECK_INTERVAL=5                 # Check every N seconds
TEMP_LOG_FILE="/tmp/kernel_build_temp.log"

# Temperature monitoring function
get_cpu_temp() {
    local temp=$(sensors "$TEMP_SENSOR" 2>/dev/null | grep -oP 'Tctl:\s+\+\K[0-9.]+' | head -1)
    if [ -z "$temp" ]; then
        # Fallback: try to get any k10temp reading
        temp=$(sensors 2>/dev/null | grep -oP 'Tctl:\s+\+\K[0-9.]+' | head -1)
    fi
    if [ -z "$temp" ]; then
        temp="0"
    fi
    echo "${temp%.*}"  # Return integer
}

# Background temperature monitor
start_temp_monitor() {
    log "Starting temperature monitor (Sensor: $TEMP_SENSOR)"
    log "  Warning: ${TEMP_WARNING}°C | Critical: ${TEMP_CRITICAL}°C | Resume: ${TEMP_RESUME}°C"
    
    (
        echo "=== Temperature Log Started: $(date) ===" > "$TEMP_LOG_FILE"
        local paused=0
        local max_temp=0
        
        while true; do
            local temp=$(get_cpu_temp)
            local timestamp=$(date '+%H:%M:%S')
            
            # Track max temperature
            if [ "$temp" -gt "$max_temp" ]; then
                max_temp=$temp
            fi
            
            # Log temperature
            echo "[$timestamp] CPU: ${temp}°C (Max: ${max_temp}°C)" >> "$TEMP_LOG_FILE"
            
            # Critical temperature - need to throttle
            if [ "$temp" -ge "$TEMP_CRITICAL" ] && [ "$paused" -eq 0 ]; then
                echo -e "${RED}[THERMAL] ⚠️  CRITICAL: ${temp}°C - Throttling build processes!${NC}"
                echo "[$timestamp] CRITICAL: ${temp}°C - Sending SIGSTOP" >> "$TEMP_LOG_FILE"
                # Send SIGSTOP to bazel processes to pause
                pkill -STOP -f "bazel" 2>/dev/null || true
                paused=1
            # Resume when cooled down
            elif [ "$temp" -le "$TEMP_RESUME" ] && [ "$paused" -eq 1 ]; then
                echo -e "${GREEN}[THERMAL] ✓ Cooled to ${temp}°C - Resuming build${NC}"
                echo "[$timestamp] RESUMED: ${temp}°C - Sending SIGCONT" >> "$TEMP_LOG_FILE"
                pkill -CONT -f "bazel" 2>/dev/null || true
                paused=0
            # Warning temperature
            elif [ "$temp" -ge "$TEMP_WARNING" ] && [ "$paused" -eq 0 ]; then
                echo -e "${YELLOW}[THERMAL] ⚡ Warning: ${temp}°C${NC}"
            fi
            
            sleep "$TEMP_CHECK_INTERVAL"
        done
    ) &
    TEMP_MONITOR_PID=$!
    echo "$TEMP_MONITOR_PID" > /tmp/temp_monitor.pid
}

# Stop temperature monitor
stop_temp_monitor() {
    if [ -f /tmp/temp_monitor.pid ]; then
        local pid=$(cat /tmp/temp_monitor.pid)
        kill "$pid" 2>/dev/null || true
        rm -f /tmp/temp_monitor.pid
        
        # Print temperature summary
        if [ -f "$TEMP_LOG_FILE" ]; then
            local max_temp=$(grep -oP 'Max: \K[0-9]+' "$TEMP_LOG_FILE" | sort -n | tail -1)
            echo -e "${CYAN}[THERMAL] 📊 Build completed. Max temperature: ${max_temp}°C${NC}"
        fi
    fi
}

# Cleanup on exit
cleanup() {
    stop_temp_monitor
    # Resume any paused processes
    pkill -CONT -f "bazel" 2>/dev/null || true
}
trap cleanup EXIT

WORKSPACE_DIR="../gki_build_workspace"
KERNEL_SRC="$WORKSPACE_DIR/common"
CLANG_DIR="$WORKSPACE_DIR/prebuilts/clang/host/linux-x86"
CLANG_VER="clang-r547379"
STAMP_BZL="$WORKSPACE_DIR/build/kernel/kleaf/impl/stamp.bzl"

log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }

# 1. Dependency Check (Arch Linux)
log "Checking Dependencies..."
if [ -f /etc/arch-release ] && ! command -v repo &> /dev/null; then
    log "Installing dependencies..."
    sudo pacman -S --needed --noconfirm base-devel git repo zip unzip curl wget python bc rsync schedtool cpio ncurses libxml2 xmlto inetutils
fi

# 2. Workspace Setup
log "Setting up workspace..."
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

if [ ! -d ".repo" ]; then
    log "Initializing Repo..."
    repo init -u https://android.googlesource.com/kernel/manifest -b common-android13-5.15
    mkdir -p .repo/local_manifests
    # Skip downloading kernel source (using local link)
    cat > .repo/local_manifests/local.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remove-project name="kernel/common" />
</manifest>
EOF
    log "Syncing repo (this may take a while)..."
    repo sync -c -j$(nproc) --no-tags
fi

# 3. Source Linking
log "Linking Kernel Source..."
if [ -L "common" ]; then rm "common"; fi
if [ -d "common" ]; then mv common "common_backup_$(date +%s)"; fi
ln -s "$(realpath ../android_gki_kernel_5.15_common)" common

# 4. Fix: Ensure Clang Toolchain Exists (Manual Fetch if Repo Sync failed)
if [ ! -d "$CLANG_DIR/$CLANG_VER" ]; then
    warn "Clang $CLANG_VER not found. Fetching manually..."
    mkdir -p "$CLANG_DIR" && cd "$CLANG_DIR"
    git init
    git remote add origin "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86"
    git fetch --depth 1 origin master
    git checkout FETCH_HEAD -- "$CLANG_VER"
    cd "$WORKSPACE_DIR"
fi

# 5. Fix: ZRAM Configuration (Build as Module)
log "Applying ZRAM Config Fix..."
GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
if grep -q "CONFIG_ZRAM=y" "$GKI_DEFCONFIG"; then
    sed -i 's/CONFIG_ZRAM=y/CONFIG_ZRAM=m/' "$GKI_DEFCONFIG"
    sed -i 's/CONFIG_ZSMALLOC=y/CONFIG_ZSMALLOC=m/' "$GKI_DEFCONFIG"
    log "Converted ZRAM to module."
fi

# 5.1 Enable TMPFS_XATTR (insert after CONFIG_TMPFS=y for correct position)
log "Enabling TMPFS_XATTR..."
if ! grep -q "CONFIG_TMPFS_XATTR=y" "$GKI_DEFCONFIG"; then
    sed -i '/^CONFIG_TMPFS=y$/a CONFIG_TMPFS_XATTR=y' "$GKI_DEFCONFIG"
    log "Added CONFIG_TMPFS_XATTR=y"
fi

MODULES_LIST="$KERNEL_SRC/android/gki_system_dlkm_modules"
if ! grep -q "drivers/block/zram/zram.ko" "$MODULES_LIST"; then
    echo "drivers/block/zram/zram.ko" >> "$MODULES_LIST"
    echo "mm/zsmalloc.ko" >> "$MODULES_LIST"
fi

# 6. Fix: Export 'task_is_booster' for ZRAM Module
CPUSET_C="$KERNEL_SRC/kernel/cgroup/cpuset.c"
if ! grep -q "EXPORT_SYMBOL_GPL(task_is_booster)" "$CPUSET_C"; then
    log "Exporting task_is_booster..."
    echo "" >> "$CPUSET_C"
    echo "EXPORT_SYMBOL_GPL(task_is_booster);" >> "$CPUSET_C"
fi

# 7. Fix: Add symbol to KMI Allowlist (Strict Mode)
SYMBOL_LIST="$KERNEL_SRC/android/abi_gki_aarch64"
if ! grep -q "task_is_booster" "$SYMBOL_LIST"; then
    log "Updating KMI Symbol List..."
    echo "task_is_booster" >> "$SYMBOL_LIST"
fi

# ==============================================================================
# VERSION CUSTOMIZATION
# ==============================================================================
BUILD_DATE=$(date +%Y%m%d)
CUSTOM_VERSION="-serein-android13-$BUILD_DATE"

log "Customizing Kernel Version to: $CUSTOM_VERSION"

# 8. Update CONFIG_LOCALVERSION in gki_defconfig
# Replace existing CONFIG_LOCALVERSION="..." with our custom version
if grep -q "CONFIG_LOCALVERSION=" "$GKI_DEFCONFIG"; then
    sed -i 's/CONFIG_LOCALVERSION=".*"/CONFIG_LOCALVERSION="'"$CUSTOM_VERSION"'"/' "$GKI_DEFCONFIG"
else
    echo "CONFIG_LOCALVERSION=\"$CUSTOM_VERSION\"" >> "$GKI_DEFCONFIG"
fi

# 9. Remove '-maybe-dirty' suffix by hacking stamp.bzl
# The Bazel build system (Kleaf) forces LOCALVERSION="-maybe-dirty" for non-stamped builds.
# We change it to empty string so it doesn't append anything, and lets CONFIG_LOCALVERSION take precedence.
if [ -f "$STAMP_BZL" ]; then
    log "Patching stamp.bzl to remove -maybe-dirty..."
    sed -i 's/export LOCALVERSION="-maybe-dirty"/export LOCALVERSION=""/' "$STAMP_BZL"
else
    warn "stamp.bzl not found at $STAMP_BZL. Version might still include -maybe-dirty."
fi

# ==============================================================================

# ==============================================================================
# CCACHE CONFIGURATION
# ==============================================================================
log "Configuring ccache..."

# Set ccache directory (use workspace-relative path for portability)
CCACHE_DIR="${WORKSPACE_DIR}/.ccache"
mkdir -p "$CCACHE_DIR"

# Configure ccache environment variables
export CCACHE_DIR
# Maximum cache size (default 10GB)
if [ -z "$CCACHE_MAXSIZE" ]; then
    export CCACHE_MAXSIZE="10G"
else
    export CCACHE_MAXSIZE
fi
export CCACHE_COMPRESS=1                        # Enable compression
export CCACHE_COMPRESSLEVEL=6                   # Compression level (1-9)
export CCACHE_SLOPPINESS="pch_defines,time_macros,include_file_mtime,include_file_ctime"
# CCACHE_NOSTATS: 0 means enable stats, 1 means disable stats
# We want stats enabled, so we don't set this variable (or set it to empty)
unset CCACHE_NOSTATS

# Show ccache status
if command -v ccache &> /dev/null; then
    log "ccache version: $(ccache --version | head -n 1)"
    log "ccache directory: $CCACHE_DIR"
    log "ccache max size: $CCACHE_MAXSIZE"
    
    # Show current cache statistics
    if [ -d "$CCACHE_DIR" ] && [ "$(ls -A $CCACHE_DIR 2>/dev/null)" ]; then
        CACHE_STATS=$(ccache -s 2>/dev/null | grep -E "cache hit|cache miss|cache size|files in cache" || echo "No cache data")
        if [ -n "$CACHE_STATS" ]; then
            log "ccache status:"
            echo "$CACHE_STATS" | sed 's/^/  /'
        fi
    else
        log "ccache cache is empty (first build - will populate during build)"
    fi
else
    warn "ccache not found! Install with: sudo pacman -S ccache"
    warn "Continuing without ccache (build will be slower)"
fi

# ==============================================================================
# 10. Build
# ==============================================================================
log "Starting Bazel Build..."

# Start temperature monitoring
start_temp_monitor

# Show initial temperature
INITIAL_TEMP=$(get_cpu_temp)
log "Initial CPU temperature: ${INITIAL_TEMP}°C"

# Note: ccache is configured via build.config.common
# For Bazel builds, we also pass environment variables via --action_env
# This ensures ccache settings are available to all build actions
BAZEL_CCACHE_FLAGS=""
if command -v ccache &> /dev/null; then
    BAZEL_CCACHE_FLAGS="--action_env=CCACHE_DIR --action_env=CCACHE_MAXSIZE --action_env=CCACHE_COMPRESS --action_env=CCACHE_COMPRESSLEVEL --action_env=CCACHE_SLOPPINESS"
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

tools/bazel build $BAZEL_CCACHE_FLAGS $BAZEL_TIMESTAMP_FLAGS //common:kernel_aarch64_dist

# Show ccache statistics after build
if command -v ccache &> /dev/null && [ -d "$CCACHE_DIR" ]; then
    log "ccache statistics after build:"
    ccache -s 2>/dev/null | grep -E "cache hit|cache miss|cache size|files in cache" | sed 's/^/  /' || true
    
    # Show cache efficiency
    HIT_RATE=$(ccache -s 2>/dev/null | grep -oP 'hit rate\s+\K[0-9.]+%' || echo "N/A")
    if [ "$HIT_RATE" != "N/A" ]; then
        log "ccache hit rate: $HIT_RATE"
    fi
fi

# Stop temperature monitoring and show summary
stop_temp_monitor

log "Build Complete!"
# Find Image in workspace out directory (Bazel output)
IMAGE_PATH=$(find "$WORKSPACE_DIR/out" -name Image 2>/dev/null | head -n 1)
if [ -z "$IMAGE_PATH" ]; then
    # Try alternative locations
    IMAGE_PATH=$(find "$WORKSPACE_DIR" -name Image -path "*/out/*" 2>/dev/null | head -n 1)
fi
if [ -z "$IMAGE_PATH" ]; then
    error "Could not find built Kernel Image in $WORKSPACE_DIR"
    exit 1
fi
echo "Kernel Image: $IMAGE_PATH"

# Verify version
log "Verifying Kernel Version..."
if [ -f "$IMAGE_PATH" ]; then
    strings "$IMAGE_PATH" | grep "Linux version" | head -n 1
fi

# ==============================================================================
# POST-BUILD: Generate Output Artifacts
# ==============================================================================
log "Generating build artifacts..."

# Get script directory (kernel source root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"

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

# 3. Generate anykernel.zip
log "Creating anykernel.zip..."
ANYKERNEL_DIR="$OUT_DIR/anykernel_tmp"
rm -rf "$ANYKERNEL_DIR"
mkdir -p "$ANYKERNEL_DIR/META-INF/com/google/android"

# Create update-binary script for AnyKernel
cat > "$ANYKERNEL_DIR/META-INF/com/google/android/update-binary" <<'EOF'
#!/sbin/sh
# AnyKernel installer script for GKI kernel

OUTFD=$2
ZIPFILE=$3

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

# Try to use magiskboot if available (most reliable method)
if command -v magiskboot &> /dev/null; then
    ui_print "Using magiskboot to repack boot image..."
    
    # Find boot partition
    BOOT_PARTITION=$(find /dev/block -name boot 2>/dev/null | head -n 1)
    if [ -z "$BOOT_PARTITION" ]; then
        for name in boot /dev/block/bootdevice/by-name/boot /dev/block/by-name/boot; do
            if [ -e "$name" ]; then
                BOOT_PARTITION="$name"
                break
            fi
        done
    fi
    
    if [ -z "$BOOT_PARTITION" ] || [ ! -e "$BOOT_PARTITION" ]; then
        ui_print "Error: Boot partition not found"
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

BOOT_PARTITION=$(find /dev/block -name boot 2>/dev/null | head -n 1)
if [ -z "$BOOT_PARTITION" ]; then
    BOOT_PARTITION="/dev/block/bootdevice/by-name/boot"
fi

if [ ! -e "$BOOT_PARTITION" ]; then
    ui_print "Error: Boot partition not found"
    ui_print "Please use magiskboot or AIK method"
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
cd "$SCRIPT_DIR"
rm -rf "$ANYKERNEL_DIR"

log "✓ anykernel.zip created: $OUT_DIR/anykernel.zip"

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Artifacts Generated:${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "  ${CYAN}Image.gz:${NC}      $OUT_DIR/Image.gz"
echo -e "  ${CYAN}boot.img:${NC}      $BOOT_IMG"
echo -e "  ${CYAN}anykernel.zip:${NC} $OUT_DIR/anykernel.zip"
echo -e "${GREEN}========================================${NC}"
