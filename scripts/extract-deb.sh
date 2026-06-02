#!/bin/bash
set -euo pipefail

# Extract DEB package to get app content and maintainer scripts
# Usage: ./extract-deb.sh <path-to-deb-file>

DEB_FILE="${1:?DEB file path required}"

if [[ ! -f "$DEB_FILE" ]]; then
    echo "Error: DEB file not found: $DEB_FILE" >&2
    exit 1
fi

echo "Extracting DEB package: $DEB_FILE"

# Clean up previous extraction
rm -rf extracted
mkdir -p extracted/DEBIAN extracted/data

# Extract control files (metadata, maintainer scripts)
echo "Extracting control files..."
if ar p "$DEB_FILE" control.tar.gz 2>/dev/null | tar xzf - -C extracted/DEBIAN 2>/dev/null; then
    echo "  ✓ Extracted control.tar.gz"
elif ar p "$DEB_FILE" control.tar.xz 2>/dev/null | tar xJf - -C extracted/DEBIAN 2>/dev/null; then
    echo "  ✓ Extracted control.tar.xz"
else
    echo "Error: Failed to extract control archive" >&2
    exit 1
fi

# Extract data files (application content)
echo "Extracting data files..."
if ar p "$DEB_FILE" data.tar.xz 2>/dev/null | tar xJf - -C extracted/data 2>/dev/null; then
    echo "  ✓ Extracted data.tar.xz"
elif ar p "$DEB_FILE" data.tar.gz 2>/dev/null | tar xzf - -C extracted/data 2>/dev/null; then
    echo "  ✓ Extracted data.tar.gz"
elif ar p "$DEB_FILE" data.tar.zst 2>/dev/null | tar --zstd -xf - -C extracted/data 2>/dev/null; then
    echo "  ✓ Extracted data.tar.zst"
else
    echo "Error: Failed to extract data archive" >&2
    exit 1
fi

# Detect installation path (search all subdirectories in /opt)
APP_PATH=""
if [[ -d "extracted/data/opt" ]]; then
    # Find the first directory in /opt that contains resources/app.asar
    while IFS= read -r -d '' dir; do
        if [[ -f "$dir/resources/app.asar" ]]; then
            APP_PATH="${dir#extracted/data/}"
            break
        fi
    done < <(find extracted/data/opt -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
fi

if [[ -z "$APP_PATH" ]]; then
    echo "Error: Could not find application directory in /opt" >&2
    echo "Available directories:" >&2
    ls -la extracted/data/opt/ 2>/dev/null || echo "  (none)" >&2
    echo ""
    echo "Looking for a directory containing resources/app.asar" >&2
    exit 1
fi

echo "  ✓ Found application at: $APP_PATH"

# Verify critical files exist
CRITICAL_FILES=(
    "extracted/data/$APP_PATH/resources/app.asar"
    "extracted/DEBIAN/control"
)

echo "Verifying critical files..."
for file in "${CRITICAL_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Missing critical file: $file" >&2
        exit 1
    fi
    echo "  ✓ Found: $file"
done

# Optional: Check for maintainer scripts
for script in postinst preinst prerm postrm; do
    if [[ -f "extracted/DEBIAN/$script" ]]; then
        echo "  ✓ Found maintainer script: $script"
        chmod +x "extracted/DEBIAN/$script"
    fi
done

echo ""
echo "Extraction complete!"
echo "  Control files: extracted/DEBIAN/"
echo "  Data files: extracted/data/"
echo "  App location: extracted/data/$APP_PATH/"

# Save app path for other scripts
echo "$APP_PATH" > extracted/APP_PATH
