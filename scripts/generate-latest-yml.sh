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

# Create output directory
mkdir -p dist

# Generate latest-linux.yml
cat > dist/latest-linux.yml << EOF
version: ${VERSION}
releaseDate: '${RELEASE_DATE}'
files:
EOF

# Add standalone DEB
DEB_FILE="dist/alma_${VERSION}-1_amd64.deb"
if [[ -f "$DEB_FILE" ]]; then
    SHA512=$(calculate_sha512 "$DEB_FILE")
    SIZE=$(get_size "$DEB_FILE")
    cat >> dist/latest-linux.yml << EOF
  - url: alma_${VERSION}-1_amd64.deb
    sha512: ${SHA512}
    size: ${SIZE}
    variant: standalone
    format: deb
    arch: amd64
EOF
fi

# Add standalone RPM
RPM_FILE="dist/alma-${VERSION}-1.x86_64.rpm"
if [[ -f "$RPM_FILE" ]]; then
    SHA512=$(calculate_sha512 "$RPM_FILE")
    SIZE=$(get_size "$RPM_FILE")
    cat >> dist/latest-linux.yml << EOF
  - url: alma-${VERSION}-1.x86_64.rpm
    sha512: ${SHA512}
    size: ${SIZE}
    variant: standalone
    format: rpm
    arch: x86_64
EOF
fi

# Add standalone Pacman
PACMAN_FILE="dist/alma-${VERSION}-1-x86_64.pkg.tar.zst"
if [[ -f "$PACMAN_FILE" ]]; then
    SHA512=$(calculate_sha512 "$PACMAN_FILE")
    SIZE=$(get_size "$PACMAN_FILE")
    cat >> dist/latest-linux.yml << EOF
  - url: alma-${VERSION}-1-x86_64.pkg.tar.zst
    sha512: ${SHA512}
    size: ${SIZE}
    variant: standalone
    format: pacman
    arch: x86_64
EOF
fi

# Add system RPM
SYSTEM_RPM_FILE="dist/alma-system-${VERSION}-1.x86_64.rpm"
if [[ -f "$SYSTEM_RPM_FILE" ]]; then
    SHA512=$(calculate_sha512 "$SYSTEM_RPM_FILE")
    SIZE=$(get_size "$SYSTEM_RPM_FILE")
    cat >> dist/latest-linux.yml << EOF
  - url: alma-system-${VERSION}-1.x86_64.rpm
    sha512: ${SHA512}
    size: ${SIZE}
    variant: system
    format: rpm
    arch: x86_64
EOF
fi

# Add system Pacman
SYSTEM_PACMAN_FILE="dist/alma-system-${VERSION}-1-x86_64.pkg.tar.zst"
if [[ -f "$SYSTEM_PACMAN_FILE" ]]; then
    SHA512=$(calculate_sha512 "$SYSTEM_PACMAN_FILE")
    SIZE=$(get_size "$SYSTEM_PACMAN_FILE")
    cat >> dist/latest-linux.yml << EOF
  - url: alma-system-${VERSION}-1-x86_64.pkg.tar.zst
    sha512: ${SHA512}
    size: ${SIZE}
    variant: system
    format: pacman
    arch: x86_64
EOF
fi

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
