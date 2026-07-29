#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adeveda Enterprises Private Limited
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Build Mixar (incremental — only changed files recompile) and install the
# resulting application so it can be launched from the shell.
#
# macOS:  Installs the .app bundle to /Applications and symlinks the binary
#         to /usr/local/bin/mixar.
# Linux:  Installs the binary to /usr/local/bin/mixar and shared resources
#         to /usr/local/share/mixar/.
#
# The install step writes outside the user home, so it requires sudo and
# will prompt for the password.
#
# Usage:
#   ./build-and-install.sh
#
# Configuration:
#   Copy .env.example to .env to override MIXAR_ENV (Prod|Dev|UAT) and backend
#   URLs. With no .env, MIXAR_ENV defaults to Prod (builds into build/Prod).
#
# Idempotent: safe to re-run. Re-running only recompiles changed files (CMake
# incremental) and refreshes the installed files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all build settings (ROOT_DIR, BUILD_DIR, UPSTREAM_DIR, MIXAR_ENV, ...).
# shellcheck source=scripts/unix/settings.sh
source "$SCRIPT_DIR/scripts/unix/settings.sh"
# NOTE: settings.sh reassigns SCRIPT_DIR to its own dir (scripts/unix), so use
# the ROOT_DIR it exports (the repo root) for any further repo-relative paths.

BUILD_ENV_DIR="${BUILD_DIR}/${MIXAR_ENV}"

# --- Platform detection and paths ---------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macOS"
    # macOS: app bundle layout
    APP_SRC="$BUILD_ENV_DIR/bin/Mixar.app"
    APP_DEST="/Applications/Mixar.app"
    EXEC_REL="Contents/MacOS/Mixar"
    BIN_LINK="/usr/local/bin/mixar"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="Linux"
    # Linux: portable install under /usr/local
    APP_SRC="$BUILD_ENV_DIR/bin"
    APP_DEST="/usr/local"
    EXEC_REL="bin/mixar"
    BIN_LINK="/usr/local/bin/mixar"
else
    echo "ERROR: unsupported platform: $OSTYPE" >&2
    exit 1
fi

# --- Verify the built binary exists before attempting install ------------------
if [[ "$PLATFORM" == "macOS" ]]; then
    BUILT_BINARY="$BUILD_ENV_DIR/bin/Mixar.app/Contents/MacOS/Mixar"
else
    BUILT_BINARY="$BUILD_ENV_DIR/bin/mixar"
fi

echo "=== Mixar build-and-install ==="
echo "Root       : $ROOT_DIR"
echo "Platform   : $PLATFORM"
echo "Environment: $MIXAR_ENV"
echo "Build dir  : $BUILD_ENV_DIR"
if [[ "$PLATFORM" == "macOS" ]]; then
    echo "Install    : $APP_DEST  (symlink $BIN_LINK -> \$APP_DEST/$EXEC_REL)"
else
    echo "Install    : $APP_DEST  (symlink $BIN_LINK -> $APP_DEST/$EXEC_REL)"
fi
echo

# --- 1. Initialize upstream submodule + Git-LFS if not already present --------
# One-time: clones the multi-GB Blender upstream submodule and pulls LFS assets.
if [ ! -f "$UPSTREAM_DIR/CMakeLists.txt" ]; then
    echo "--- Initializing upstream submodule + Git-LFS (one-time; may take a while)..."
    "$ROOT_DIR/scripts/unix/init.sh"
else
    echo "--- upstream already initialized; skipping init."
fi
echo

# --- 2. Incremental build -----------------------------------------------------
# build.sh re-overlays src/ onto source/ (rsync preserves mtimes, so unchanged
# files keep their timestamps) and runs an incremental CMake build + install +
# Python-package install. With no changed files the compile is a fast no-op.
echo "--- Building (incremental; only changed files recompile)..."
"$ROOT_DIR/scripts/unix/build.sh"
echo

# --- 3. Verify the built binary exists ----------------------------------------
if [ ! -x "$BUILT_BINARY" ]; then
    echo "ERROR: build did not produce an executable at:" >&2
    echo "       $BUILT_BINARY" >&2
    exit 1
fi
echo "--- Build OK: $BUILT_BINARY"
echo

# --- 4. Install (sudo required) -----------------------------------------------
echo "--- Installing Mixar ($PLATFORM)..."

if [[ "$PLATFORM" == "macOS" ]]; then
    # macOS: rsync the .app bundle to /Applications + symlink
    echo "    Installing to $APP_DEST and linking $BIN_LINK (sudo required)..."
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

elif [[ "$PLATFORM" == "Linux" ]]; then
    # Linux: install binary to /usr/local/bin, resources to /usr/local/share/mixar/,
    # and create a desktop entry.
    echo "    Installing binary to /usr/local/bin/mixar and resources (sudo required)..."
    sudo -v

    # Install the binary
    sudo mkdir -p /usr/local/bin
    sudo install -m 755 "$APP_SRC/bin/mixar" /usr/local/bin/mixar

    # Install shared resources (version data, scripts, Python, etc.)
    if [ -d "$APP_SRC/share" ]; then
        sudo rsync -a --delete "$APP_SRC/share/" /usr/local/share/
    fi

    # Install the version directory (5.0/ — contains Python, scripts, config)
    if [ -d "$APP_SRC/$BLENDER_VERSION" ]; then
        sudo mkdir -p "/usr/local/share/mixar/$BLENDER_VERSION"
        sudo rsync -a --delete \
            "$APP_SRC/$BLENDER_VERSION/" "/usr/local/share/mixar/$BLENDER_VERSION/"
    fi

    # Install shared libraries if present (portable build)
    if [ -d "$APP_SRC/lib" ]; then
        sudo mkdir -p /usr/local/lib/mixar
        sudo rsync -a --delete "$APP_SRC/lib/" /usr/local/lib/mixar/
    fi

    # Install .desktop file for desktop integration
    DESKTOP_SRC="$ROOT_DIR/src/release/freedesktop/mixar.desktop"
    if [ -f "$DESKTOP_SRC" ]; then
        sudo mkdir -p /usr/local/share/applications
        sudo install -m 644 "$DESKTOP_SRC" /usr/local/share/applications/mixar.desktop
    elif [ -f "$APP_SRC/share/applications/mixar.desktop" ]; then
        sudo mkdir -p /usr/local/share/applications
        sudo install -m 644 "$APP_SRC/share/applications/mixar.desktop" /usr/local/share/applications/mixar.desktop
    fi

    # Install icons for desktop integration
    for icon_src in \
        "$ROOT_DIR/src/release/freedesktop/icons/scalable/apps/mixar.svg" \
        "$APP_SRC/share/icons/hicolor/scalable/apps/mixar.svg"; do
        if [ -f "$icon_src" ]; then
            sudo mkdir -p /usr/local/share/icons/hicolor/scalable/apps
            sudo install -m 644 "$icon_src" /usr/local/share/icons/hicolor/scalable/apps/mixar.svg
            break
        fi
    done
    for icon_src in \
        "$ROOT_DIR/src/release/freedesktop/icons/symbolic/apps/mixar-symbolic.svg" \
        "$APP_SRC/share/icons/hicolor/symbolic/apps/mixar-symbolic.svg"; do
        if [ -f "$icon_src" ]; then
            sudo mkdir -p /usr/local/share/icons/hicolor/symbolic/apps
            sudo install -m 644 "$icon_src" /usr/local/share/icons/hicolor/symbolic/apps/mixar-symbolic.svg
            break
        fi
    done

    # Install metainfo XML for app stores
    for meta_src in \
        "$ROOT_DIR/src/release/freedesktop/org.mixar.Mixar.metainfo.xml" \
        "$APP_SRC/share/metainfo/org.mixar.Mixar.metainfo.xml"; do
        if [ -f "$meta_src" ]; then
            sudo mkdir -p /usr/local/share/metainfo
            sudo install -m 644 "$meta_src" /usr/local/share/metainfo/org.mixar.Mixar.metainfo.xml
            break
        fi
    done

    # Update desktop database and icon cache
    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/local/share/applications/ 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        sudo gtk-update-icon-cache /usr/local/share/icons/hicolor/ 2>/dev/null || true
    fi
fi

echo
echo "=== Install complete ==="
if [[ "$PLATFORM" == "macOS" ]]; then
    echo "Mixar is installed at: $APP_DEST"
    echo "Launch it with either:"
    echo "    mixar"
    echo "    open $APP_DEST"
else
    echo "Mixar is installed at: /usr/local/bin/mixar"
    echo "Launch it with:"
    echo "    mixar"
fi
