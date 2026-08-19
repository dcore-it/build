#!/bin/bash

set -e

# ==========================================
# Configuration
# ==========================================
ROM_NAME="Evolution-X"
ROM_URL="https://github.com/Evolution-X/manifest"
ROM_BRANCH="cnb"
MANIFEST_URL="https://github.com/dcore-it/manifest_peridot.git"

DEVICE="peridot"
BUILD_VARIANT="cp2a-user"

export TZ="Asia/Jakarta"
export BUILD_USERNAME="dcore"
export BUILD_HOSTNAME="lake"

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
# Upload Result Variables
# ==========================================
PIXELDRAIN_URL=""
GOFILE_URL=""

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
# Load .env
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
# Telegram
# ==========================================
send_telegram() {
    local MESSAGE="$1"

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ||
          -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        warning "curl is not installed"
        return 0
    fi

    curl -s \
        --fail \
        -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${MESSAGE}" \
        >/dev/null || warning "Telegram notification failed"
}

# ==========================================
# Telegram - Build Started
# ==========================================
telegram_build_start() {
    send_telegram "🚀 BUILD STARTED

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}
Branch   : ${ROM_BRANCH}
Host     : ${BUILD_HOSTNAME}
Builder  : ${BUILD_USERNAME}

⏳ Build in progress..."
}

# ==========================================
# Telegram - Build Failed
# ==========================================
telegram_build_failed() {
    send_telegram "❌ BUILD FAILED

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}
Branch   : ${ROM_BRANCH}
Host     : ${BUILD_HOSTNAME}

⚠️ Check the build output for details."
}

# ==========================================
# Telegram - Upload Results
# ==========================================
telegram_upload_results() {
    local FILE="$1"

    local MESSAGE="📦 UPLOAD COMPLETE

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}

📄 File
$(basename "$FILE")

💾 Size
$(du -h "$FILE" | cut -f1)"

    # --------------------------------------
    # PixelDrain
    # --------------------------------------
    if [[ -n "${PIXELDRAIN_URL}" ]]; then
        MESSAGE="${MESSAGE}

🟢 PixelDrain
${PIXELDRAIN_URL}"
    else
        MESSAGE="${MESSAGE}

🔴 PixelDrain
Upload failed/skipped"
    fi

    # --------------------------------------
    # GoFile
    # --------------------------------------
    if [[ -n "${GOFILE_URL}" ]]; then
        MESSAGE="${MESSAGE}

🟢 GoFile
${GOFILE_URL}"
    else
        MESSAGE="${MESSAGE}

🔴 GoFile
Upload failed/skipped"
    fi

    send_telegram "$MESSAGE"
}

# ==========================================
# Telegram - Finished
# ==========================================
telegram_finished() {
    local TOTAL_TIME="$1"

    send_telegram "🏁 BUILD JOB FINISHED

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}
Host     : ${BUILD_HOSTNAME}

⏱ Total time
${TOTAL_TIME} minutes"
}

# ==========================================
# PixelDrain Upload
# ==========================================
upload_pixeldrain() {
    local FILE="$1"
    local RESPONSE
    local FILE_ID

    PIXELDRAIN_URL=""

    if [[ ! -f "$FILE" ]]; then
        error "File not found: $FILE"
        return 1
    fi

    if [[ -z "${PIXELDRAIN_TOKEN:-}" ]]; then
        warning "PIXELDRAIN_TOKEN is not set"
        warning "Skipping PixelDrain upload"
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

    log "Uploading $(basename "$FILE") to PixelDrain"

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

    PIXELDRAIN_URL="https://pixeldrain.com/u/${FILE_ID}"

    echo
    success "PixelDrain upload completed!"

    echo
    echo -e "${GREEN}${BOLD}PixelDrain:${RESET}"
    echo "$PIXELDRAIN_URL"
    echo
}

# ==========================================
# GoFile Upload
# ==========================================
upload_gofile() {
    local FILE="$1"
    local RESPONSE
    local DOWNLOAD_URL

    GOFILE_URL=""

    if [[ ! -f "$FILE" ]]; then
        error "File not found: $FILE"
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

    log "Uploading $(basename "$FILE") to GoFile"

    info "File: $(basename "$FILE")"
    info "Size: $(du -h "$FILE" | cut -f1)"
    info "Region: Singapore"

    echo

    RESPONSE=$(curl \
        --progress-bar \
        -X POST \
        -F "file=@${FILE}" \
        "https://upload-ap-sgp.gofile.io/uploadfile")

    DOWNLOAD_URL=$(echo "$RESPONSE" | jq -r '.data.downloadPage // empty')

    if [[ -z "$DOWNLOAD_URL" ]]; then
        error "GoFile upload failed"

        echo
        echo "$RESPONSE"

        return 1
    fi

    GOFILE_URL="$DOWNLOAD_URL"

    echo
    success "GoFile upload completed!"

    echo
    echo -e "${GREEN}${BOLD}GoFile:${RESET}"
    echo "$GOFILE_URL"
    echo
}

# ==========================================
# Start
# ==========================================
START_TOTAL=$(date +%s)

log "Starting ${ROM_NAME} Build"

info "Device     : ${DEVICE}"
info "Variant    : ${BUILD_VARIANT}"
info "Branch     : ${ROM_BRANCH}"
info "Lunch      : lineage_peridot-cp2a-user"
info "Host       : ${BUILD_HOSTNAME}"
info "User       : ${BUILD_USERNAME}"

# ==========================================
# Clean Previous Source
# ==========================================
log "Cleaning Previous Source"

rm -rf .repo/local_manifests
rm -rf "device/xiaomi/${DEVICE}"
rm -rf "out/target/product/${DEVICE}"

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
# Clone Local Manifest
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
log "Syncing Source"

SYNC_START=$(date +%s)

if [[ -f /opt/crave/resync.sh ]]; then

    info "Running Crave resync..."

    /opt/crave/resync.sh || {
        warning "Crave resync returned an error"
        warning "Starting forced repo sync..."
    }

    info "Running forced repo sync..."

    repo sync \
        -c \
        --force-sync \
        --force-remove-dirty \
        --no-tags \
        --no-clone-bundle \
        || {
            warning "Forced repo sync returned an error"
            warning "Continuing build anyway..."
        }

else

    warning "Crave resync script not found"
    info "Running forced repo sync..."

    repo sync \
        -c \
        --force-sync \
        --force-remove-dirty \
        --no-tags \
        --no-clone-bundle \
        || {
            warning "Repo sync returned an error"
            warning "Continuing build anyway..."
        }

fi

SYNC_END=$(date +%s)

success "Source sync stage finished"
info "Sync time: $(((SYNC_END - SYNC_START) / 60)) minutes"

# ==========================================
# Build Environment
# ==========================================
log "Preparing Build Environment"

. build/envsetup.sh

# Load .env AFTER envsetup.sh
load_env

lunch lineage_peridot-cp2a-user

success "Build environment ready"

# ==========================================
# Telegram - Build Started
# ==========================================
telegram_build_start

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

    BUILD_SUCCESS=1

else

    BUILD_SUCCESS=0

fi

BUILD_END=$(date +%s)
BUILD_TIME=$(((BUILD_END - BUILD_START) / 60))

# ==========================================
# Build Failed
# ==========================================
if [[ "${BUILD_SUCCESS}" == "0" ]]; then

    echo
    error "BUILD FAILED"
    info "Build time: ${BUILD_TIME} minutes"

    telegram_build_failed

    exit 1

fi

# ==========================================
# Build Successful
# ==========================================
echo
echo -e "${GREEN}${BOLD}"
echo "=========================================="
echo "          BUILD SUCCESSFUL"
echo "=========================================="
echo -e "${RESET}"

success "ROM: ${ROM_NAME}"
success "Device: ${DEVICE}"
info "Build time: ${BUILD_TIME} minutes"

# ==========================================
# Find Build Artifacts
# ==========================================
ARTIFACTS=()

# ------------------------------------------
# ROM ZIP files
# ------------------------------------------
while IFS= read -r -d '' FILE; do
    ARTIFACTS+=("$FILE")
done < <(
    find "out/target/product/${DEVICE}" \
        -maxdepth 1 \
        -type f \
        -name "*.zip" \
        ! -name "*target_files*" \
        ! -name "*ota*" \
        -print0
)

# ------------------------------------------
# Selected boot images ONLY
# ------------------------------------------
for IMG in \
    "vendor_boot.img" \
    "dtbo.img" \
    "boot.img" \
    "recovery.img"
do
    IMG_PATH="out/target/product/${DEVICE}/${IMG}"

    if [[ -f "${IMG_PATH}" ]]; then
        ARTIFACTS+=("${IMG_PATH}")
    fi
done

# ==========================================
# Check Artifacts
# ==========================================
if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then

    warning "No ROM or selected image artifacts found"

    send_telegram "⚠️ BUILD COMPLETED

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}

⚠️ No ROM or selected image artifacts were found.
Upload skipped."

else

    success "Found ${#ARTIFACTS[@]} artifact(s)"

    # ======================================
    # Upload Each Artifact
    # ======================================
    for ARTIFACT in "${ARTIFACTS[@]}"; do

        echo
        log "Processing $(basename "${ARTIFACT}")"

        info "Size: $(du -h "${ARTIFACT}" | cut -f1)"

        # ----------------------------------
        # PixelDrain
        # ----------------------------------
        upload_pixeldrain "${ARTIFACT}" || true

        ARTIFACT_PIXELDRAIN="${PIXELDRAIN_URL}"

        # ----------------------------------
        # GoFile
        # ----------------------------------
        upload_gofile "${ARTIFACT}" || true

        ARTIFACT_GOFILE="${GOFILE_URL}"

        # ----------------------------------
        # Telegram
        # ----------------------------------
        ARTIFACT_MESSAGE="📦 UPLOAD COMPLETE

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}

📄 File
$(basename "${ARTIFACT}")

💾 Size
$(du -h "${ARTIFACT}" | cut -f1)"

        if [[ -n "${ARTIFACT_PIXELDRAIN}" ]]; then
            ARTIFACT_MESSAGE="${ARTIFACT_MESSAGE}

🟢 PixelDrain
${ARTIFACT_PIXELDRAIN}"
        else
            ARTIFACT_MESSAGE="${ARTIFACT_MESSAGE}

🔴 PixelDrain
Upload failed/skipped"
        fi

        if [[ -n "${ARTIFACT_GOFILE}" ]]; then
            ARTIFACT_MESSAGE="${ARTIFACT_MESSAGE}

🟢 GoFile
${ARTIFACT_GOFILE}"
        else
            ARTIFACT_MESSAGE="${ARTIFACT_MESSAGE}

🔴 GoFile
Upload failed/skipped"
        fi

        send_telegram "${ARTIFACT_MESSAGE}"

    done

fi

# ==========================================
# Finished
# ==========================================
TOTAL_END=$(date +%s)
TOTAL_TIME=$(((TOTAL_END - START_TOTAL) / 60))

log "Build Finished"

success "Everything completed!"
info "Total time: ${TOTAL_TIME} minutes"

telegram_finished "${TOTAL_TIME}"

echo
