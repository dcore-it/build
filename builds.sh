#!/bin/bash

set -e

# ==========================================
# Colors
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ==========================================
# Configuration
# ==========================================
ROM_NAME="Evolution-X"
ROM_URL="https://github.com/Evolution-X/manifest"
ROM_BRANCH="cnb"
MANIFEST_URL="https://github.com/dcore-it/manifest_peridot.git"

DEVICE="peridot"
LUNCH_TARGET="lineage_peridot-cp2a-user"

export TZ="Asia/Jakarta"
export BUILD_USERNAME="dcore"
export BUILD_HOSTNAME="lake"

# ==========================================
# Helper Functions
# ==========================================
log() {
    echo
    echo -e "${CYAN}${BOLD}==========================================${RESET}"
    echo -e "${CYAN}${BOLD}$1${RESET}"
    echo -e "${CYAN}${BOLD}==========================================${RESET}"
}

success() {
    echo -e "${GREEN}${BOLD}✓ $1${RESET}"
}

info() {
    echo -e "${BLUE}➜ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

error() {
    echo -e "${RED}${BOLD}✗ $1${RESET}"
}

# ==========================================
# Load Private Environment
# ==========================================
load_env() {
    if [[ -f ".env" ]]; then
        source ".env"
        success "Private environment loaded"
    else
        warning ".env not found"
    fi
}

# ==========================================
# PixelDrain Upload
# ==========================================
upload_pixeldrain() {
    local FILE="$1"
    local RESPONSE
    local FILE_ID

    if [[ ! -f "$FILE" ]]; then
        error "File not found: $FILE"
        return 1
    fi

    if [[ -z "${PIXELDRAIN_TOKEN:-}" ]]; then
        error "PIXELDRAIN_TOKEN is not set"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        error "curl is not installed"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        error "jq is not installed"
        return 1
    fi

    log "Uploading ROM to PixelDrain"

    info "File: $(basename "$FILE")"
    info "Size: $(du -h "$FILE" | cut -f1)"

    echo

    RESPONSE=$(curl \
        --progress-bar \
        -T "$FILE" \
        -u ":${PIXELDRAIN_TOKEN}" \
        "https://pixeldrain.com/api/file/")

    FILE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [[ -z "$FILE_ID" ]]; then
        error "PixelDrain upload failed"
        echo
        echo "$RESPONSE"
        return 1
    fi

    echo
    success "PixelDrain upload completed!"

    echo
    echo -e "${GREEN}${BOLD}Download:${RESET}"
    echo "https://pixeldrain.com/u/${FILE_ID}"
    echo
}

# ==========================================
# Start
# ==========================================
START_TOTAL=$(date +%s)

log "Starting ${ROM_NAME} Build"

info "Device     : ${DEVICE}"
info "Branch     : ${ROM_BRANCH}"
info "Lunch      : ${LUNCH_TARGET}"
info "Build Host : ${BUILD_HOSTNAME}"
info "Build User : ${BUILD_USERNAME}"

# ==========================================
# Cleanup
# ==========================================
log "Cleaning Previous Source"

rm -rf .repo/local_manifests
rm -rf "device/xiaomi/${DEVICE}"

success "Cleanup complete"

# ==========================================
# Repo Init
# ==========================================
log "Initializing ${ROM_NAME}"

repo init \
    -u "${ROM_URL}" \
    -b "${ROM_BRANCH}" \
    --git-lfs \
    --depth=1

success "Repo initialization complete"

# ==========================================
# Local Manifest
# ==========================================
log "Cloning Local Manifest"

git clone \
    --depth=1 \
    "${MANIFEST_URL}" \
    .repo/local_manifests

success "Local manifest ready"

# ==========================================
# Crave Resync
# ==========================================
log "Running Crave Resync"

/opt/crave/resync.sh

success "Crave resync complete"

# ==========================================
# Repo Sync
# ==========================================
log "Syncing Source"

SYNC_START=$(date +%s)

repo sync \
    -c \
    --no-clone-bundle \
    --no-tags \
    --optimized-fetch \
    --prune \
    --force-sync

SYNC_END=$(date +%s)

success "Source sync complete"
info "Sync time: $(((SYNC_END - SYNC_START) / 60)) minutes"

# ==========================================
# Build Environment
# ==========================================
log "Preparing Build Environment"

. build/envsetup.sh

# Load .env AFTER envsetup.sh
load_env

lunch "${LUNCH_TARGET}"

success "Build environment ready"

# ==========================================
# Install Clean
# ==========================================
log "Cleaning Build Output"

make installclean

success "Install clean complete"

# ==========================================
# Build
# ==========================================
log "Building ${ROM_NAME}"

BUILD_START=$(date +%s)

if m evolution; then

    BUILD_END=$(date +%s)
    TOTAL_END=$(date +%s)

    echo
    echo -e "${GREEN}${BOLD}"
    echo "=========================================="
    echo "          BUILD SUCCESSFUL"
    echo "=========================================="
    echo -e "${RESET}"

    success "ROM: ${ROM_NAME}"
    success "Device: ${DEVICE}"

    info "Build time: $(((BUILD_END - BUILD_START) / 60)) minutes"
    info "Total time: $(((TOTAL_END - START_TOTAL) / 60)) minutes"

    # ==========================================
    # Find Newest ROM ZIP
    # ==========================================
    ROM_ZIP=$(find "out/target/product/${DEVICE}" \
        -maxdepth 1 \
        -type f \
        -name "*.zip" \
        ! -name "*target_files*" \
        ! -name "*ota*" \
        -printf '%T@ %p\n' \
        | sort -nr \
        | head -n 1 \
        | cut -d' ' -f2-)

    if [[ -n "$ROM_ZIP" && -f "$ROM_ZIP" ]]; then

        echo
        success "ROM ZIP found"
        info "$(basename "$ROM_ZIP")"
        info "Size: $(du -h "$ROM_ZIP" | cut -f1)"

        # ==========================================
        # PixelDrain Upload
        # ==========================================
        if ! upload_pixeldrain "$ROM_ZIP"; then
            warning "ROM built successfully, but PixelDrain upload failed."
        fi

    else
        warning "ROM ZIP not found. Upload skipped."
    fi

else

    echo
    error "Build failed."
    warning "PixelDrain upload skipped."

    exit 1

fi

# ==========================================
# Finished
# ==========================================
log "Build Finished"

echo
success "Everything completed!"
