#!/bin/bash
set -euo pipefail

# Generate latest-linux.yml and system-linux.yml for auto-update
# Usage: ./generate-latest-yml.sh <VERSION> <RELEASE_DATE> <REPO_OWNER> <REPO_NAME> [RELEASE_NOTES]

VERSION="${1:?VERSION required}"
RELEASE_DATE="${2:?RELEASE_DATE required}"
REPO_OWNER="${3:?REPO_OWNER required}"
REPO_NAME="${4:?REPO_NAME required}"
RELEASE_NOTES="${5:-Release notes for Alma v${VERSION}

For full details, visit: https://alma.now}"

BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}"

echo "Generating update manifests for version $VERSION..."

# Calculate checksums for all packages (Base64 format for electron-updater)
calculate_sha512() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha512sum "$file" | awk '{print $1}' | xxd -r -p | base64 -w 0
    else
        echo "Error: File not found: $file" >&2
        return 1
    fi
}

# Get file size
get_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null
    else
        echo "0"
    fi
}

add_package_file() {
    local output_file="$1"
    shift
    local file="$1"
    local variant="$2"
    local format="$3"
    local arch="$4"
    local blockmap_file="${file}.blockmap"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    if [[ ! -f "$blockmap_file" ]]; then
        echo "Error: Missing blockmap for $file: $blockmap_file" >&2
        return 1
    fi

    local url
    local sha512
    local size
    local blockmap_size
    url=$(basename "$file")
    sha512=$(calculate_sha512 "$file")
    size=$(get_size "$file")
    blockmap_size=$(get_size "$blockmap_file")

    cat >> "$output_file" << EOF
  - url: ${url}
    sha512: ${sha512}
    size: ${size}
    blockMapSize: ${blockmap_size}
    variant: ${variant}
    format: ${format}
    arch: ${arch}
EOF
}

write_manifest_header() {
    local output_file="$1"

    cat > "$output_file" << EOF
version: ${VERSION}
releaseDate: '${RELEASE_DATE}'
files:
EOF
}

write_manifest_footer() {
    local output_file="$1"
    local default_file="$2"
    local package_info="$3"

    cat >> "$output_file" << EOF
path: $(basename "$default_file")
sha512: $(calculate_sha512 "$default_file")
releaseNotes: |
$(echo "$RELEASE_NOTES" | sed 's/^/  /')

  ---

  **Package Information:**
${package_info}
  - For installation instructions, visit: https://github.com/${REPO_OWNER}/${REPO_NAME}
EOF
}

# Create output directory
mkdir -p dist

PACMAN_FILE="dist/alma-${VERSION}-1-x86_64.pkg.tar.zst"
SYSTEM_RPM_FILE="dist/alma-system-${VERSION}-1.x86_64.rpm"
SYSTEM_PACMAN_FILE="dist/alma-system-${VERSION}-1-x86_64.pkg.tar.zst"

write_manifest_header dist/latest-linux.yml
add_package_file dist/latest-linux.yml "$PACMAN_FILE" standalone pacman x86_64
add_package_file dist/latest-linux.yml "$SYSTEM_RPM_FILE" system rpm x86_64
add_package_file dist/latest-linux.yml "$SYSTEM_PACMAN_FILE" system pacman x86_64
write_manifest_footer dist/latest-linux.yml "$PACMAN_FILE" "  - Standalone packages include the full Electron runtime
  - System packages require a matching system Electron runtime
  - System packages use the separate system-linux.yml update channel"

write_manifest_header dist/system-linux.yml
add_package_file dist/system-linux.yml "$SYSTEM_RPM_FILE" system rpm x86_64
add_package_file dist/system-linux.yml "$SYSTEM_PACMAN_FILE" system pacman x86_64
write_manifest_footer dist/system-linux.yml "$SYSTEM_RPM_FILE" "  - System packages require a matching system Electron runtime
  - This manifest is used only by packages with channel: system"

echo "✓ Generated: dist/latest-linux.yml"
cat dist/latest-linux.yml
echo "✓ Generated: dist/system-linux.yml"
cat dist/system-linux.yml
