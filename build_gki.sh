#!/bin/bash
set -e

# ==============================================================================
# GKI Kernel Build Script for Xiaomi 13 (fuxi)
# Environment: Arch Linux / Android 13 / Kernel 5.15
# ==============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ✅ 定义统一的输出目录，Bazel 会把结果吐到这里
DIST_OUTPUT_DIR="$SCRIPT_DIR/out/dist"

# Load all modules
source "$LIB_DIR/common.sh"
source "$LIB_DIR/temp_monitor.sh"
source "$LIB_DIR/pack.sh"
source "$LIB_DIR/config_fixes.sh"
source "$LIB_DIR/workspace.sh"
source "$LIB_DIR/version.sh"
source "$LIB_DIR/ccache.sh"
source "$LIB_DIR/ksu.sh"
source "$LIB_DIR/susfs.sh"
source "$LIB_DIR/bazel.sh"

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
SKIP_BUILD=false
PACK_AK3=false
PACK_IMG=false
ENABLE_KSU=false
ENABLE_SUSFS=false
CLEAN_CACHE=true # Default to cleaning the cache
PERF_PROFILE="max"  # 默认全速
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --ksu          Enable KernelSU support"
    echo "  --susfs        Enable SUSFS support"
    echo "  --ak3          Only pack anykernel.zip (skip build)"
    echo "  --img          Only pack boot.img and Image.gz (skip build)"
    echo "  --profile      Build performance profile: max (default), balanced, cool"
    echo "  --clean        Force clean the Bazel cache before building (default)"
    echo "  --no-clean     Do not clean the Bazel cache before building"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --profile cool   # Build quietly with reduced heat"
    echo "  $0 --profile balanced"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ksu)
            ENABLE_KSU=true
            shift
            ;;
        --susfs)
            ENABLE_SUSFS=true
            shift
            ;;
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
        --profile)
            PERF_PROFILE="$2"
            shift 2
            ;;
        --clean)
            CLEAN_CACHE=true
            shift
            ;;
        --no-clean)
            CLEAN_CACHE=false
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

# 0. Clean Bazel Cache (if requested)
# This is the fix for the stale build timestamp issue.
if [ "$CLEAN_CACHE" = true ]; then
    clean_bazel_cache
fi

# 1. Dependency Check
check_dependencies

# 2. Workspace Setup
setup_workspace

# 🔥 CRITICAL FIX: 确保源码目录绝对干净
# config_fixes 或 ksu 脚本可能会污染 common 目录
# 必须在进入 Bazel 之前清理它们，但要保留我们需要修改的 defconfig
log "Cleaning source tree for Bazel..."
if [ -d "$WORKSPACE_DIR/common" ]; then
    pushd "$WORKSPACE_DIR/common" > /dev/null
    # 使用 make mrproper 彻底清理构建产物
    # 这会删除 .config, include/config, include/generated 等所有构建文件
    make mrproper > /dev/null 2>&1 || {
        warn "make mrproper failed, trying manual cleanup..."
        # 如果 make mrproper 失败，手动清理关键文件
        rm -rf .config .config.old include/config include/generated arch/*/include/generated .kernelvariables
    }
    popd > /dev/null
    log "✓ Source tree cleaned"
fi

# 3. Apply Configuration Fixes (修改 gki_defconfig)
# 注意：config_fixes.sh 应该只修改 common/arch/arm64/configs/gki_defconfig
# 不要直接去生成 .config，否则 Bazel 又会报错
apply_config_fixes

# 3.1 Setup KernelSU (if enabled)
# KSU setup 可能会修改源码，确保修改的是源码文件而不是生成文件
if [ "$ENABLE_KSU" = true ]; then
    setup_kernelsu
fi

# 3.2 Setup SUSFS (if enabled)
if [ "$ENABLE_SUSFS" = true ]; then
    setup_susfs
fi

# 4. Version Customization
customize_version

# 5. CCache Configuration
configure_ccache

# 6. Build (if not skipped)
if [ "$SKIP_BUILD" = false ]; then
    log "Starting Bazel Build..."
     # ==========================================================================
    # PERFORMANCE PROFILE SETUP
    # ==========================================================================
    TOTAL_CORES=$(nproc)
    case $PERF_PROFILE in
        "cool")
            # 静音模式：使用 50% 核心
            # 适合挂机编译，几乎无风扇噪音
            USE_CORES=$(($TOTAL_CORES / 2))
            if [ "$USE_CORES" -lt 1 ]; then USE_CORES=1; fi
            log "🚀 Performance Profile: COOL (Using $USE_CORES/$TOTAL_CORES cores)"
            ;;
        "balanced")
            # 平衡模式：使用 75% 核心
            # 速度和温度的折中
            USE_CORES=$(($TOTAL_CORES * 3 / 4))
            log "🚀 Performance Profile: BALANCED (Using $USE_CORES/$TOTAL_CORES cores)"
            ;;
        "max")
            # 狂暴模式：使用 100% 核心 (默认)
            USE_CORES=$TOTAL_CORES
            log "🚀 Performance Profile: MAX PERFORMANCE (Using all $TOTAL_CORES cores)"
            ;;
        *)
            # 允许用户直接输入数字，例如 --profile 8
            if [[ "$PERF_PROFILE" =~ ^[0-9]+$ ]]; then
                USE_CORES=$PERF_PROFILE
                if [ "$USE_CORES" -gt "$TOTAL_CORES" ]; then USE_CORES=$TOTAL_CORES; fi
                log "🚀 Performance Profile: CUSTOM (Using $USE_CORES/$TOTAL_CORES cores)"
            else
                warn "Unknown profile '$PERF_PROFILE', defaulting to MAX"
                USE_CORES=$TOTAL_CORES
            fi
            ;;
    esac
    # 1. 计算核心列表 (例如 USE_CORES=4，则范围是 0-3)
    CPU_END_INDEX=$(($USE_CORES - 1))
    CPU_RANGE="0-$CPU_END_INDEX"

    # 2. 构造 Taskset 前缀命令
    # taskset -c 0-3 表示：只允许程序在 CPU0 到 CPU3 上运行
    # 这样 CPU4 及其以后的核心会完全休眠，彻底降温
    PREFIX_CMD="taskset -c $CPU_RANGE"
    
    log "🔒 Locking build process to CPU cores: $CPU_RANGE"
    BAZEL_PERF_FLAGS="--jobs=$USE_CORES --local_cpu_resources=$USE_CORES"

    # Start temperature monitoring
    start_temp_monitor

    # Show initial temperature
    INITIAL_TEMP=$(get_cpu_temp)
    log "Initial CPU temperature: ${INITIAL_TEMP}°C"

    # Note: Using Bazel --disk_cache instead of ccache for better performance

    # Set build timestamp for kernel version string
    # This fixes the "Thu Jan 1 00:00:00 UTC 1970" issue
    # SOURCE_DATE_EPOCH is used for reproducible builds, but we want actual build time
    # 获取当前实际时间戳
    CURRENT_TIME=$(date +%s)
    # 将时间戳格式化为字符串
    if command -v date >/dev/null 2>&1; then
        # 尝试使用 GNU date (Linux)
        BUILD_TIMESTAMP=$(date -u -d "@$CURRENT_TIME" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || \
                         date -u -r "$CURRENT_TIME" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || \
                         date -u "+%Y-%m-%d %H:%M:%S %Z")
    else
        BUILD_TIMESTAMP=$(date -u "+%Y-%m-%d %H:%M:%S %Z")
    fi
    
    export SOURCE_DATE_EPOCH=$CURRENT_TIME
    export KBUILD_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"

    log "Using actual build timestamp: $BUILD_TIMESTAMP (epoch: $CURRENT_TIME)"
    
    # 这些环境变量会传递给构建系统，确保内核版本信息中包含正确的时间戳
    BAZEL_TIMESTAMP_FLAGS="--action_env=KBUILD_BUILD_TIMESTAMP --action_env=SOURCE_DATE_EPOCH"

    log "Build timestamp set to: $BUILD_TIMESTAMP"

    BAZEL_CACHE_DIR="$HOME/.bazel_cache"
    mkdir -p "$BAZEL_CACHE_DIR"

    log "Building with Bazel Native Disk Cache..."
    log "Cache directory: $BAZEL_CACHE_DIR ($(du -sh "$BAZEL_CACHE_DIR" 2>/dev/null | cut -f1 || echo 'N/A'))"
    
    cd "$WORKSPACE_DIR"

    # 🔥 OPTIMIZATION: 使用 'run' 而不是 'build' 以便直接输出到 dist_dir
    # Bazel 缓存基于文件内容哈希，不依赖 git 状态
    # 即使有未提交的更改，只要文件内容相同，缓存就能命中
    # 时间戳使用稳定的 commit 时间，确保相同 commit 的构建能复用缓存
    mkdir -p "$DIST_OUTPUT_DIR"
    
    log "Building kernel with Bazel (output to: $DIST_OUTPUT_DIR)..."
    log "Build parameters: TIME=$CURRENT_TIME, TIMESTAMP=$BUILD_TIMESTAMP"
    
    # 确保 BAZEL_FLAGS 有默认值，避免空变量导致命令解析错误
    BAZEL_FLAGS="${BAZEL_FLAGS:-}"
    
    # Disable KMI strict mode for custom builds
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    
    $PREFIX_CMD tools/bazel run \
        --action_env=KMI_SYMBOL_LIST_STRICT_MODE=0 \
        --action_env=KMI_ENFORCED=0 \
        ${BAZEL_FLAGS} \
        ${BAZEL_PERF_FLAGS} \
        ${BAZEL_TIMESTAMP_FLAGS} \
        --disk_cache="$BAZEL_CACHE_DIR" \
        //common:kernel_aarch64_dist \
        -- \
        --dist_dir="$DIST_OUTPUT_DIR"

    # Bazel cache statistics (disk_cache used instead of ccache)
    if [ -d "$BAZEL_CACHE_DIR" ]; then
        CACHE_SIZE=$(du -sh "$BAZEL_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
        CACHE_FILES=$(find "$BAZEL_CACHE_DIR" -type f 2>/dev/null | wc -l)
        log "Bazel disk cache statistics:"
        log "  Cache directory: $BAZEL_CACHE_DIR"
        log "  Cache size: $CACHE_SIZE"
        log "  Cache files: $CACHE_FILES"
    fi

    # Stop temperature monitoring and show summary
    stop_temp_monitor
    
    # 🔥 REMOVED: 删除了 .config 恢复逻辑
    # 因为 Bazel 构建不需要也不应该在 common/ 下保留 .config
    # 如果你想保存本次构建的 config，去 $DIST_OUTPUT_DIR 下找 config 文件即可

    log "Build Complete!"
    
    # ==============================================================================
    # CLEANUP: Organize Output Directory
    # ==============================================================================
    log "Organizing output directory..."
    
    # 1. 创建归档目录
    EXTRAS_DIR="$DIST_OUTPUT_DIR/extras"
    mkdir -p "$EXTRAS_DIR"

    # 2. 将所有“非核心”文件移动到 extras 目录
    # 我们只保留 Image, Image.gz, boot.img, vmlinux, anykernel.zip
    # 其他的全部移走
    find "$DIST_OUTPUT_DIR" -maxdepth 1 -type f \
        ! -name "Image" \
        ! -name "Image.gz" \
        ! -name "boot.img" \
        ! -name "vmlinux" \
        ! -name "anykernel.zip" \
        -exec mv {} "$EXTRAS_DIR/" \;

    log "✓ Dist directory cleaned. Debug files moved to: out/dist/extras"
else
    log "Skipping build (pack-only mode)"
fi

# ✅ UPDATED: 直接从 dist 目录获取 Image
# 不需要复杂的 find 逻辑了
IMAGE_PATH="$DIST_OUTPUT_DIR/Image"

if [ ! -f "$IMAGE_PATH" ]; then
    # 尝试找一下压缩版
    IMAGE_PATH="$DIST_OUTPUT_DIR/Image.gz"
fi
echo "Kernel Image: $IMAGE_PATH"

# Verify version
log "Verifying Kernel Version..."
if [ -f "$IMAGE_PATH" ]; then
    # 如果是 gz 压缩的，需要 zcat
    if [[ "$IMAGE_PATH" == *.gz ]]; then
        zcat "$IMAGE_PATH" | strings | grep "Linux version" | head -n 1
    else
        strings "$IMAGE_PATH" | grep "Linux version" | head -n 1
    fi
else
    warn "Kernel Image not found at $IMAGE_PATH"
    warn "Build may have failed or output location changed"
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
