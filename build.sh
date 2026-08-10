#!/bin/bash

set -e

# =====================================
# Configuration
# =====================================
ROM_URL="https://github.com/Evolution-X/manifest"
ROM_BRANCH="cnb"
MANIFEST_URL="https://github.com/dcore-it/manifest_peridot.git"

DEVICE="peridot"
LUNCH_TARGET="lineage_peridot-cp2a-user"

export TZ="Asia/Jakarta"
export BUILD_USERNAME="dcore"
export BUILD_HOSTNAME="lake"

# =====================================
# Helper
# =====================================
log() {
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# =====================================
# Cleanup
# =====================================
log "Cleaning previous source"

rm -rf .repo/local_manifests
rm -rf "device/xiaomi/$DEVICE"

# =====================================
# Repo Init
# =====================================
log "Initializing Evolution-X"

repo init \
    -u "$ROM_URL" \
    -b "$ROM_BRANCH" \
    --git-lfs \
    --depth=1

# =====================================
# Local Manifest
# =====================================
log "Cloning local manifest"

git clone --depth=1 \
    "$MANIFEST_URL" \
    .repo/local_manifests

# =====================================
# Sync
# =====================================
log "Running Crave resync"

/opt/crave/resync.sh

log "Syncing repositories"

repo sync \
    -c \
    --no-clone-bundle \
    --no-tags \
    --optimized-fetch \
    --prune \
    --force-sync

# =====================================
# Build Environment
# =====================================
log "Preparing build environment"

. build/envsetup.sh

lunch "$LUNCH_TARGET"

make installclean

# =====================================
# Build
# =====================================
log "Building Evolution-X"

START=$(date +%s)

m evolution

END=$(date +%s)

echo
echo "Build completed successfully!"
echo "Build time: $(((END - START) / 60)) minutes"

log "Done!"
