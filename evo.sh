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
SOURCEFORGE_UPLOAD_OK=0

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
# Telegram - Build Success
# ==========================================
telegram_build_success() {
    local FILE="$1"
    local BUILD_TIME="$2"

    send_telegram "✅ BUILD SUCCESSFUL

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}
Branch   : ${ROM_BRANCH}

📦 File
$(basename "$FILE")

💾 Size
$(du -h "$FILE" | cut -f1)

⏱ Build time
${BUILD_TIME} minutes

📤 Uploading to mirrors..."
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

⚠️ Check the build log for details."
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

    # --------------------------------------
    # SourceForge
    # --------------------------------------
    if [[ "${SOURCEFORGE_UPLOAD_OK}" == "1" ]]; then
        MESSAGE="${MESSAGE}

🟢 SourceForge
https://sourceforge.net/projects/${SOURCEFORGE_PROJECT}/files/"
    else
        MESSAGE="${MESSAGE}

🔴 SourceForge
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

    log "Uploading ROM to GoFile"

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
# SourceForge Upload
# ==========================================
upload_sourceforge() {
    local FILE="$1"
    local UPLOAD_PATH

    SOURCEFORGE_UPLOAD_OK=0

    if [[ ! -f "$FILE" ]]; then
        error "File not found: $FILE"
        return 1
    fi

    if [[ -z "${SOURCEFORGE_USERNAME:-}" ||
          -z "${SOURCEFORGE_PROJECT:-}" ]]; then
        warning "SourceForge credentials are not configured"
        warning "Skipping SourceForge upload"
        return 1
    fi

    if ! command -v scp >/dev/null 2>&1; then
        error "scp is not installed"
        return 1
    fi

    log "Uploading ROM to SourceForge"

    info "File: $(basename "$FILE")"
    info "Size: $(du -h "$FILE" | cut -f1)"
    info "Project: ${SOURCEFORGE_PROJECT}"

    UPLOAD_PATH="${SOURCEFORGE_USERNAME}@frs.sourceforge.net:/home/frs/project/${SOURCEFORGE_PROJECT}"

    echo

    if scp "$FILE" "$UPLOAD_PATH"; then

        SOURCEFORGE_UPLOAD_OK=1

        success "SourceForge upload completed!"

        echo
        echo -e "${GREEN}${BOLD}SourceForge:${RESET}"
        echo "https://sourceforge.net/projects/${SOURCEFORGE_PROJECT}/files/"
        echo

        return 0

    else

        error "SourceForge upload failed"
        return 1

    fi
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

    /opt/crave/resync.sh

else

    repo sync \
        -c \
        --force-sync \
        --no-tags \
        --no-clone-bundle \
        --force-remove-dirty

fi

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

# Save complete build output
BUILD_LOG="out/target/product/${DEVICE}/build.log"

# Make sure the directory exists
mkdir -p "out/target/product/${DEVICE}"

info "Build log: ${BUILD_LOG}"
echo

# ==========================================
# Run Build + Save Log
# ==========================================
if m evolution 2>&1 | tee "${BUILD_LOG}"; then

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
    info "Full log: ${BUILD_LOG}"

    echo
    echo -e "${RED}${BOLD}"
    echo "=========================================="
    echo "          LAST 100 LOG LINES"
    echo "=========================================="
    echo -e "${RESET}"

    tail -100 "${BUILD_LOG}"

    # ======================================
    # Upload Build Log ONLY to GoFile
    # ======================================
    log "Uploading Build Log to GoFile"

    GOFILE_URL=""

    upload_gofile "${BUILD_LOG}" || true

    BUILD_LOG_GOFILE="${GOFILE_URL}"

    # ======================================
    # Telegram - Build Failed
    # ======================================
    FAILURE_MESSAGE="❌ BUILD FAILED

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}
Branch   : ${ROM_BRANCH}
Host     : ${BUILD_HOSTNAME}

⏱ Build time
${BUILD_TIME} minutes

📋 Full build log"

    if [[ -n "${BUILD_LOG_GOFILE}" ]]; then

        FAILURE_MESSAGE="${FAILURE_MESSAGE}

🟢 GoFile
${BUILD_LOG_GOFILE}"

    else

        FAILURE_MESSAGE="${FAILURE_MESSAGE}

🔴 GoFile
Log upload failed"

    fi

    FAILURE_MESSAGE="${FAILURE_MESSAGE}

🔎 Last 100 lines:

$(tail -100 "${BUILD_LOG}")"

    send_telegram "${FAILURE_MESSAGE}"

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
info "Build log: ${BUILD_LOG}"

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

if [[ -n "${ROM_ZIP}" && -f "${ROM_ZIP}" ]]; then

    echo
    success "ROM ZIP found"
    info "$(basename "${ROM_ZIP}")"
    info "Size: $(du -h "${ROM_ZIP}" | cut -f1)"

    # ======================================
    # Telegram - Build Success
    # ======================================
    telegram_build_success \
        "${ROM_ZIP}" \
        "${BUILD_TIME}"

    # ======================================
    # Upload ROM to PixelDrain
    # ======================================
    upload_pixeldrain "${ROM_ZIP}" || true

    # ======================================
    # Upload ROM to GoFile
    # ======================================
    upload_gofile "${ROM_ZIP}" || true

    # ======================================
    # Upload ROM to SourceForge
    # ======================================
    upload_sourceforge "${ROM_ZIP}" || true

    # ======================================
    # Send All Upload Links
    # ======================================
    telegram_upload_results "${ROM_ZIP}"

else

    warning "ROM ZIP not found"
    warning "Upload skipped"

    send_telegram "⚠️ BUILD COMPLETED

ROM      : ${ROM_NAME}
Device   : ${DEVICE}
Variant  : ${BUILD_VARIANT}

⚠️ ROM ZIP was not found.
Upload skipped."

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
