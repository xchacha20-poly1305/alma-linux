#!/bin/bash
set -euo pipefail

# Determine Electron version from extracted DEB package
# Outputs major version number (e.g., "37")

if [[ ! -f "extracted/APP_PATH" ]]; then
    echo "Error: Run extract-deb.sh first" >&2
    exit 1
fi

APP_PATH=$(cat extracted/APP_PATH)
BASE_PATH="extracted/data/$APP_PATH"

# Try multiple methods to detect Electron version
ELECTRON_VERSION=""

# Method 1: Read version file (most reliable)
if [[ -f "$BASE_PATH/version" ]]; then
    ELECTRON_VERSION=$(cat "$BASE_PATH/version")
    echo "  [Method 1] Found version file: $ELECTRON_VERSION" >&2
fi

# Method 2: Parse package.json in app.asar (requires asar tool)
if [[ -z "$ELECTRON_VERSION" ]] && command -v asar &>/dev/null; then
    if [[ -f "$BASE_PATH/resources/app.asar" ]]; then
        PACKAGE_JSON=$(asar extract "$BASE_PATH/resources/app.asar" - 2>/dev/null | grep -A 5 '"electron"' || true)
        if [[ -n "$PACKAGE_JSON" ]]; then
            ELECTRON_VERSION=$(echo "$PACKAGE_JSON" | grep -oP '"electron":\s*"\K[^"]+' || true)
            echo "  [Method 2] Extracted from app.asar: $ELECTRON_VERSION" >&2
        fi
    fi
fi

# Method 3: Extract from Electron binary using strings
if [[ -z "$ELECTRON_VERSION" ]]; then
    ELECTRON_BINARY=""
    # Try common binary names
    for binary_name in alma Alma electron; do
        if [[ -f "$BASE_PATH/$binary_name" ]]; then
            ELECTRON_BINARY="$BASE_PATH/$binary_name"
            break
        fi
    done

    if [[ -n "$ELECTRON_BINARY" ]] && command -v strings &>/dev/null; then
        ELECTRON_VERSION=$(strings "$ELECTRON_BINARY" | grep -oP 'Electron/\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [[ -n "$ELECTRON_VERSION" ]]; then
            echo "  [Method 3] Extracted from binary: $ELECTRON_VERSION" >&2
        fi
    fi
fi

# Method 4: Check chrome-sandbox or other Electron binaries
if [[ -z "$ELECTRON_VERSION" ]] && [[ -f "$BASE_PATH/chrome-sandbox" ]]; then
    # Electron binaries don't always expose version, but we can try
    echo "  [Method 4] Binary found but version not embedded" >&2
fi

# Method 5: Parse DEBIAN/control for any Electron references
if [[ -z "$ELECTRON_VERSION" ]] && [[ -f "extracted/DEBIAN/control" ]]; then
    CONTROL_ELECTRON=$(grep -i electron extracted/DEBIAN/control | grep -oP '\d+\.\d+\.\d+' | head -1 || true)
    if [[ -n "$CONTROL_ELECTRON" ]]; then
        ELECTRON_VERSION="$CONTROL_ELECTRON"
        echo "  [Method 5] Found in control file: $ELECTRON_VERSION" >&2
    fi
fi

if [[ -z "$ELECTRON_VERSION" ]]; then
    echo "Error: Could not determine Electron version" >&2
    echo "Tried:" >&2
    echo "  - $BASE_PATH/version" >&2
    echo "  - app.asar package.json" >&2
    echo "  - DEBIAN/control" >&2
    exit 1
fi

# Clean up version string (remove 'v' prefix if present)
ELECTRON_VERSION="${ELECTRON_VERSION#v}"

# Extract major version
ELECTRON_MAJOR=$(echo "$ELECTRON_VERSION" | cut -d. -f1)

if [[ ! "$ELECTRON_MAJOR" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid major version extracted: $ELECTRON_MAJOR" >&2
    exit 1
fi

echo "  ✓ Electron version: $ELECTRON_VERSION (major: $ELECTRON_MAJOR)" >&2
echo "$ELECTRON_MAJOR"
