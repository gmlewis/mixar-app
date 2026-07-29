#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adeveda Enterprises Private Limited
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/settings.sh"

# First argument selects the build environment folder (defaults to Dev).
BUILD_ENV="${1:-Dev}"

# Determine binary path based on platform
if [[ "$PLATFORM" == "macOS" ]]; then
    BINARY="$ROOT_DIR/build/$BUILD_ENV/bin/Mixar.app/Contents/MacOS/Mixar"
elif [[ "$PLATFORM" == "Linux" ]]; then
    BINARY="$ROOT_DIR/build/$BUILD_ENV/bin/mixar"
else
    echo "Error: Unsupported platform: $PLATFORM" >&2
    exit 1
fi

if [[ ! -x "$BINARY" ]]; then
    echo "Error: Mixar binary not found at:" >&2
    echo "  $BINARY" >&2
    echo "Make sure ./build/$BUILD_ENV exists and is built." >&2
    exit 1
fi

echo "Launching Mixar from build/$BUILD_ENV..."
exec "$BINARY"
