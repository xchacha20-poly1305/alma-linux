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

# electron-updater picks the Linux channel file by process.arch:
#   x64   -> <channel>-linux.yml
#   arm64 -> <channel>-linux-arm64.yml
# so each package architecture gets its own manifest pair. Only architectures
# that were actually built (their standalone package exists in dist/) are
# emitted, which keeps amd64-only releases unchanged when upstream has not
# published an arm64 build for a version.
write_arch_manifests() {
    local arch="$1"
    local suffix="$2"
    local latest_file="dist/latest-linux${suffix}.yml"
    local system_file="dist/system-linux${suffix}.yml"

    local pacman_file="dist/alma-${VERSION}-1-${arch}.pkg.tar.zst"
    local system_rpm_file="dist/alma-system-${VERSION}-1.${arch}.rpm"
    local system_pacman_file="dist/alma-system-${VERSION}-1-${arch}.pkg.tar.zst"

    if [[ ! -f "$pacman_file" ]]; then
        echo "Skipping ${arch}: no packages found in dist/"
        return 0
    fi

    write_manifest_header "$latest_file"
    add_package_file "$latest_file" "$pacman_file" standalone pacman "$arch"
    add_package_file "$latest_file" "$system_rpm_file" system rpm "$arch"
    add_package_file "$latest_file" "$system_pacman_file" system pacman "$arch"
    write_manifest_footer "$latest_file" "$pacman_file" "  - Standalone packages include the full Electron runtime
  - System packages require a matching system Electron runtime
  - System packages use the separate $(basename "$system_file") update channel"

    write_manifest_header "$system_file"
    add_package_file "$system_file" "$system_rpm_file" system rpm "$arch"
    add_package_file "$system_file" "$system_pacman_file" system pacman "$arch"
    write_manifest_footer "$system_file" "$system_rpm_file" "  - System packages require a matching system Electron runtime
  - This manifest is used only by packages with channel: system"

    echo "✓ Generated: $latest_file"
    cat "$latest_file"
    echo "✓ Generated: $system_file"
    cat "$system_file"
}

write_arch_manifests x86_64 ""
write_arch_manifests aarch64 "-arm64"

if [[ ! -f dist/latest-linux.yml && ! -f dist/latest-linux-arm64.yml ]]; then
    echo "Error: no packages found in dist/ for version $VERSION" >&2
    exit 1
fi
