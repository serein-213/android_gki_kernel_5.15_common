#!/bin/bash
# ==============================================================================
# CCache Configuration Module
# ==============================================================================

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configure ccache
configure_ccache() {
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
}

# Get ccache flags for Bazel
get_ccache_flags() {
    if command -v ccache &> /dev/null; then
        echo "--action_env=CCACHE_DIR --action_env=CCACHE_MAXSIZE --action_env=CCACHE_COMPRESS --action_env=CCACHE_COMPRESSLEVEL --action_env=CCACHE_SLOPPINESS"
    else
        echo ""
    fi
}

# Show ccache statistics after build
show_ccache_stats() {
    CCACHE_DIR="${WORKSPACE_DIR}/.ccache"
    if command -v ccache &> /dev/null && [ -d "$CCACHE_DIR" ]; then
        log "ccache statistics after build:"
        ccache -s 2>/dev/null | grep -E "cache hit|cache miss|cache size|files in cache" | sed 's/^/  /' || true
        
        # Show cache efficiency
        HIT_RATE=$(ccache -s 2>/dev/null | grep -oP 'hit rate\s+\K[0-9.]+%' || echo "N/A")
        if [ "$HIT_RATE" != "N/A" ]; then
            log "ccache hit rate: $HIT_RATE"
        fi
    fi
}

