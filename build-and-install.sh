#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adeveda Enterprises Private Limited
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Build Mixar (incremental — only changed files recompile) and install the
# resulting macOS app bundle to /Applications with a /usr/local/bin/mixar symlink
# so it can be launched from the shell.
#
# The install step writes under /Applications and /usr/local/bin, so it requires
# sudo and will prompt for the password.
#
# Usage:
#   ./build-and-install.sh
#
# Configuration:
#   Copy .env.example to .env to override MIXAR_ENV (Prod|Dev|UAT) and backend
#   URLs. With no .env, MIXAR_ENV defaults to Prod (builds into build/Prod).
#
# Idempotent: safe to re-run. Re-running only recompiles changed files (CMake
# incremental) and refreshes the installed bundle + symlink.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all build settings (ROOT_DIR, BUILD_DIR, UPSTREAM_DIR, MIXAR_ENV, ...).
# shellcheck source=scripts/unix/settings.sh
source "$SCRIPT_DIR/scripts/unix/settings.sh"

BUILD_ENV_DIR="${BUILD_DIR}/${MIXAR_ENV}"
APP_SRC="$BUILD_ENV_DIR/bin/Mixar.app"
APP_DEST="/Applications/Mixar.app"
EXEC_REL="Contents/MacOS/Mixar"
BIN_LINK="/usr/local/bin/mixar"

echo "=== Mixar build-and-install ==="
echo "Root       : $ROOT_DIR"
echo "Environment: $MIXAR_ENV"
echo "Build dir  : $BUILD_ENV_DIR"
echo "Install    : $APP_DEST  (symlink $BIN_LINK -> \$APP_DEST/$EXEC_REL)"
echo

# --- 1. Initialize upstream submodule + Git-LFS if not already present --------
# One-time: clones the multi-GB Blender upstream submodule and pulls LFS assets.
if [ ! -f "$UPSTREAM_DIR/CMakeLists.txt" ]; then
    echo "--- Initializing upstream submodule + Git-LFS (one-time; may take a while)..."
    "$SCRIPT_DIR/scripts/unix/init.sh"
else
    echo "--- upstream already initialized; skipping init."
fi
echo

# --- 2. Incremental build -----------------------------------------------------
# build.sh re-overlays src/ onto source/ (rsync preserves mtimes, so unchanged
# files keep their timestamps) and runs an incremental CMake build + install +
# Python-package install. With no changed files the compile is a fast no-op.
echo "--- Building (incremental; only changed files recompile)..."
"$SCRIPT_DIR/scripts/unix/build.sh"
echo

# --- 3. Verify the built app bundle exists -----------------------------------
if [ ! -x "$APP_SRC/$EXEC_REL" ]; then
    echo "ERROR: build did not produce an executable at:" >&2
    echo "       $APP_SRC/$EXEC_REL" >&2
    exit 1
fi
echo "--- Build OK: $APP_SRC"
echo

# --- 4. Install to /Applications + symlink /usr/local/bin/mixar (sudo) --------
# Writes outside the user home, so requires sudo. Caches the password once.
echo "--- Installing to $APP_DEST and linking $BIN_LINK (sudo required)..."
sudo -v
sudo mkdir -p "$APP_DEST"
# Mirror the freshly built bundle onto the install location (--delete removes
# stale files from a previous install).
sudo rsync -a --delete \
    --exclude '.DS_Store' \
    "$APP_SRC/" "$APP_DEST/"
sudo chmod +x "$APP_DEST/$EXEC_REL"
sudo mkdir -p /usr/local/bin
sudo ln -sf "$APP_DEST/$EXEC_REL" "$BIN_LINK"

echo
echo "=== Install complete ==="
echo "Mixar is installed at: $APP_DEST"
echo "Launch it with either:"
echo "    mixar"
echo "    open $APP_DEST"
