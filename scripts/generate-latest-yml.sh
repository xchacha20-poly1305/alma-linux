#!/bin/bash
set -euo pipefail

# Generate latest-linux.yml for auto-update
# Usage: ./generate-latest-yml.sh <VERSION> <RELEASE_DATE> <REPO_OWNER> <REPO_NAME> [RELEASE_NOTES]

VERSION="${1:?VERSION required}"
RELEASE_DATE="${2:?RELEASE_DATE required}"
REPO_OWNER="${3:?REPO_OWNER required}"
REPO_NAME="${4:?REPO_NAME required}"
RELEASE_NOTES="${5:-Release notes for Alma v${VERSION}

For full details, visit: https://alma.now}"

BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}"

echo "Generating latest-linux.yml for version $VERSION..."

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

    cat >> dist/latest-linux.yml << EOF
  - url: ${url}
    sha512: ${sha512}
    size: ${size}
    blockMapSize: ${blockmap_size}
    variant: ${variant}
    format: ${format}
    arch: ${arch}
EOF
}

# Create output directory
mkdir -p dist

# Generate latest-linux.yml
cat > dist/latest-linux.yml << EOF
version: ${VERSION}
releaseDate: '${RELEASE_DATE}'
files:
EOF

DEB_FILE="dist/alma_${VERSION}-1_amd64.deb"
RPM_FILE="dist/alma-${VERSION}-1.x86_64.rpm"
PACMAN_FILE="dist/alma-${VERSION}-1-x86_64.pkg.tar.zst"
SYSTEM_RPM_FILE="dist/alma-system-${VERSION}-1.x86_64.rpm"
SYSTEM_PACMAN_FILE="dist/alma-system-${VERSION}-1-x86_64.pkg.tar.zst"

add_package_file "$DEB_FILE" standalone deb amd64
add_package_file "$RPM_FILE" standalone rpm x86_64
add_package_file "$PACMAN_FILE" standalone pacman x86_64
add_package_file "$SYSTEM_RPM_FILE" system rpm x86_64
add_package_file "$SYSTEM_PACMAN_FILE" system pacman x86_64

# Add path and release notes
cat >> dist/latest-linux.yml << EOF
path: alma_${VERSION}-1_amd64.deb
sha512: $(calculate_sha512 "$DEB_FILE")
releaseNotes: |
$(echo "$RELEASE_NOTES" | sed 's/^/  /')

  ---

  **Package Information:**
  - Standalone packages include the full Electron runtime
  - System RPM/Pacman packages require a matching system Electron runtime
  - For installation instructions, visit: https://github.com/${REPO_OWNER}/${REPO_NAME}
EOF

echo "✓ Generated: dist/latest-linux.yml"
cat dist/latest-linux.yml
