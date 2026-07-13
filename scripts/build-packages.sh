#!/bin/bash
set -euo pipefail

# Build all package variants using nfpm
# Usage: ./build-packages.sh <VERSION> <ELECTRON_MAJOR>

VERSION="${1:?VERSION required}"
ELECTRON_MAJOR="${2:?ELECTRON_MAJOR required}"

if [[ ! -f "extracted/APP_PATH" ]]; then
    echo "Error: Run extract-deb.sh first" >&2
    exit 1
fi

APP_PATH=$(cat extracted/APP_PATH)
BASE_PATH="extracted/data/$APP_PATH"

# Set SOURCE_DATE_EPOCH for reproducible builds if not already set
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
    if SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 2>/dev/null); then
        echo "SOURCE_DATE_EPOCH not set, using git HEAD timestamp: $SOURCE_DATE_EPOCH" >&2
    else
        SOURCE_DATE_EPOCH=$(date +%s)
        echo "Warning: SOURCE_DATE_EPOCH not set and git timestamp unavailable, using current time: $SOURCE_DATE_EPOCH" >&2
    fi
fi
export SOURCE_DATE_EPOCH

format_epoch() {
    date -d "@$SOURCE_DATE_EPOCH" 2>/dev/null || date -r "$SOURCE_DATE_EPOCH" 2>/dev/null
}

format_epoch_rfc3339() {
    date -u -d "@$SOURCE_DATE_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

normalize_timestamps() {
    local path
    for path in "$@"; do
        [[ -e "$path" || -L "$path" ]] || continue
        find "$path" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} + 2>/dev/null || true
    done
}

normalize_package() {
    local package_path="$1"
    [[ -f "$package_path" ]] || return 0
    touch -h -d "@${SOURCE_DATE_EPOCH}" "$package_path" 2>/dev/null || true
}

set_package_type() {
    local resources_dir="$1"
    local package_type="$2"

    printf '%s\n' "$package_type" > "$resources_dir/package-type"
    normalize_package "$resources_dir/package-type"
}

prepare_app_builder_candidate() {
    local candidate="$1"

    [[ -f "$candidate" ]] || return 1
    if [[ ! -x "$candidate" ]]; then
        chmod +x "$candidate" 2>/dev/null || return 1
    fi
    echo "$candidate"
}

resolve_app_builder() {
    local candidate
    local npm_root

    if [[ -n "${APP_BUILDER_PATH:-}" ]] && prepare_app_builder_candidate "$APP_BUILDER_PATH"; then
        return 0
    fi

    if command -v node >/dev/null 2>&1; then
        if candidate=$(node -p 'require("app-builder-bin").appBuilderPath' 2>/dev/null) && prepare_app_builder_candidate "$candidate"; then
            return 0
        fi

        if command -v npm >/dev/null 2>&1; then
            npm_root=$(npm root -g 2>/dev/null || true)
            if [[ -n "$npm_root" ]] && candidate=$(NODE_PATH="$npm_root" node -p 'require("app-builder-bin").appBuilderPath' 2>/dev/null) && prepare_app_builder_candidate "$candidate"; then
                return 0
            fi
        fi
    fi

    if command -v app-builder >/dev/null 2>&1; then
        command -v app-builder
        return 0
    fi

    echo "Error: app-builder not found. Install app-builder-bin or set APP_BUILDER_PATH." >&2
    return 1
}

generate_blockmap() {
    local package_path="$1"
    local blockmap_path="${package_path}.blockmap"

    APP_BUILDER_PATH=$(resolve_app_builder)
    "$APP_BUILDER_PATH" blockmap \
        --input "$package_path" \
        --output "$blockmap_path" >/dev/null
    normalize_package "$blockmap_path"
}

NFPM_MTIME="$(format_epoch_rfc3339)"

append_script_if_exists() {
    local config_path="$1"
    local script_key="$2"
    local script_path="$3"

    [[ -f "$script_path" ]] || return 0
    printf '  %s: %s\n' "$script_key" "$script_path" >> "$config_path"
}

append_scripts_section() {
    local config_path="$1"
    shift

    local has_scripts=0
    local script_path
    for script_path in "$@"; do
        if [[ -f "$script_path" ]]; then
            has_scripts=1
            break
        fi
    done

    [[ "$has_scripts" -eq 1 ]] || return 0
    echo "scripts:" >> "$config_path"
}

append_list_item_if_set() {
    local config_path="$1"
    local field="$2"
    local value="$3"

    [[ -n "$value" ]] || return 0
    {
        printf '%s:\n' "$field"
        printf '  - %s\n' "$value"
    } >> "$config_path"
}

append_contents() {
    local config_path="$1"
    local source_dir="$2"

    local path
    local base
    local has_contents=0

    echo "contents:" >> "$config_path"
    for path in "$source_dir"/* "$source_dir"/.[!.]* "$source_dir"/..?*; do
        [[ -e "$path" || -L "$path" ]] || continue
        base=$(basename "$path")
        has_contents=1
        printf '  - src: %s\n' "$path" >> "$config_path"
        printf '    dst: /%s\n' "$base" >> "$config_path"
        if [[ -d "$path" && ! -L "$path" ]]; then
            printf '    type: tree\n' >> "$config_path"
        fi
    done

    if [[ "$has_contents" -eq 0 ]]; then
        echo "Error: no package contents found in $source_dir" >&2
        exit 1
    fi
}

write_nfpm_config() {
    local config_path="$1"
    local package_name="$2"
    local arch="$3"
    local description="$4"
    local source_dir="$5"
    local packager="$6"
    local depends="${7:-}"
    local conflicts="${8:-}"
    local rpm_summary="${9:-$description}"

    cat > "$config_path" << EOF
name: $package_name
arch: $arch
platform: linux
version: $VERSION
release: "1"
version_schema: none
section: utils
priority: optional
maintainer: $MAINTAINER
description: $description
vendor: $VENDOR
homepage: $URL
license: $LICENSE
mtime: $NFPM_MTIME
EOF

    append_contents "$config_path" "$source_dir"

    append_list_item_if_set "$config_path" depends "$depends"
    append_list_item_if_set "$config_path" conflicts "$conflicts"

    if [[ "$packager" == "rpm" ]]; then
        cat >> "$config_path" << EOF
rpm:
  summary: $rpm_summary
EOF
    elif [[ "$packager" == "archlinux" ]]; then
        cat >> "$config_path" << EOF
archlinux:
  packager: $MAINTAINER
EOF
    elif [[ "$packager" == "deb" ]]; then
        cat >> "$config_path" << EOF
deb:
  compression: xz
EOF
    fi
}

build_nfpm_package() {
    local config_path="$1"
    local packager="$2"
    local target_path="$3"

    nfpm package \
        --config "$config_path" \
        --packager "$packager" \
        --target "$target_path"
    normalize_package "$target_path"
    generate_blockmap "$target_path"
}

echo "Building packages for Alma v$VERSION (Electron $ELECTRON_MAJOR)"
echo "Source: $BASE_PATH"
echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH ($(format_epoch))"
echo "nFPM mtime: $NFPM_MTIME"
echo ""

# Create dist directory
mkdir -p dist

# Replace app-update.yml in standalone packages to point to this repository
echo "Updating app-update.yml for standalone packages..."
if [[ -f "$BASE_PATH/resources/app-update.yml" ]]; then
    cat > "$BASE_PATH/resources/app-update.yml" << 'EOF'
provider: github
owner: xchacha20-poly1305
repo: alma-linux
updaterCacheDirName: alma-updater
url: https://github.com/xchacha20-poly1305/alma-linux/releases/download/
EOF
fi

./scripts/apply-patches.sh "$BASE_PATH"

# Normalize timestamps after all standalone package content changes.
echo "Normalizing standalone file timestamps..."
normalize_timestamps extracted/data extracted/DEBIAN
echo "  ✓ Timestamps normalized to $(format_epoch)"
echo ""

# Common metadata
DESCRIPTION="Elegant AI Provider Orchestration"
VENDOR="Alma"
MAINTAINER="安容 <HystericalDragons@proton.me>"
LICENSE="Proprietary"
URL="https://alma.now"

STANDALONE_PACMAN="dist/alma-${VERSION}-1-x86_64.pkg.tar.zst"
STANDALONE_DEB="dist/alma_${VERSION}-1_amd64.deb"
SYSTEM_RPM="dist/alma-system-${VERSION}-1.x86_64.rpm"
SYSTEM_PACMAN="dist/alma-system-${VERSION}-1-x86_64.pkg.tar.zst"

# =============================================================================
# STANDALONE PACKAGES (include full Electron runtime)
# =============================================================================

echo "=== Building Standalone Packages ==="
echo ""

# --- Standalone Pacman ---
echo "[1/4] Building standalone Pacman..."
set_package_type "$BASE_PATH/resources" pacman
write_nfpm_config extracted/nfpm-standalone-archlinux.yaml \
    alma \
    x86_64 \
    "$DESCRIPTION (standalone with bundled Electron)" \
    extracted/data \
    archlinux
append_scripts_section extracted/nfpm-standalone-archlinux.yaml extracted/DEBIAN/postinst extracted/DEBIAN/prerm
append_script_if_exists extracted/nfpm-standalone-archlinux.yaml postinstall extracted/DEBIAN/postinst
append_script_if_exists extracted/nfpm-standalone-archlinux.yaml preremove extracted/DEBIAN/prerm
build_nfpm_package extracted/nfpm-standalone-archlinux.yaml archlinux "$STANDALONE_PACMAN"
echo "  ✓ Created: $STANDALONE_PACMAN"
echo ""

# --- Standalone DEB ---
echo "[2/4] Building standalone DEB..."
set_package_type "$BASE_PATH/resources" deb
write_nfpm_config extracted/nfpm-standalone-deb.yaml \
    alma \
    amd64 \
    "$DESCRIPTION (standalone with bundled Electron)" \
    extracted/data \
    deb
append_scripts_section extracted/nfpm-standalone-deb.yaml extracted/DEBIAN/postinst extracted/DEBIAN/prerm extracted/DEBIAN/postrm
append_script_if_exists extracted/nfpm-standalone-deb.yaml postinstall extracted/DEBIAN/postinst
append_script_if_exists extracted/nfpm-standalone-deb.yaml preremove extracted/DEBIAN/prerm
append_script_if_exists extracted/nfpm-standalone-deb.yaml postremove extracted/DEBIAN/postrm
build_nfpm_package extracted/nfpm-standalone-deb.yaml deb "$STANDALONE_DEB"
echo "  ✓ Created: $STANDALONE_DEB"
echo ""

# =============================================================================
# SYSTEM PACKAGES (use system Electron)
# =============================================================================

echo "=== Building System Packages ==="
echo ""

# Prepare system package content
rm -rf extracted/system-build
mkdir -p extracted/system-build/usr/lib/alma
mkdir -p extracted/system-build/usr/bin
mkdir -p extracted/system-build/usr/share/applications
mkdir -p extracted/system-build/usr/share/icons/hicolor

# Copy only resources (no Electron binary)
echo "Preparing system package content..."
cp -r "$BASE_PATH/resources" extracted/system-build/usr/lib/alma/

# Replace app-update.yml to point to this repository
echo "Updating app-update.yml for system package..."
cat > extracted/system-build/usr/lib/alma/resources/app-update.yml << 'EOF'
provider: github
owner: xchacha20-poly1305
repo: alma-linux
channel: system
updaterCacheDirName: alma-updater
EOF

# Copy wrapper script and bake in the Electron major version used by launcher lookup.
sed "s/@ELECTRON_MAJOR@/${ELECTRON_MAJOR}/g" \
    metadata/alma-wrapper.sh > extracted/system-build/usr/bin/alma
chmod +x extracted/system-build/usr/bin/alma

# Copy desktop file and icons
if [[ -d "extracted/data/usr/share/applications" ]]; then
    cp -r extracted/data/usr/share/applications/* extracted/system-build/usr/share/applications/ 2>/dev/null || true
fi
if [[ -d "extracted/data/usr/share/icons" ]]; then
    cp -r extracted/data/usr/share/icons/* extracted/system-build/usr/share/icons/ 2>/dev/null || true
fi

# Modify desktop file to use wrapper
if [[ -f extracted/system-build/usr/share/applications/alma.desktop ]]; then
    sed -i 's|Exec=.*|Exec=/usr/bin/alma %U|g' extracted/system-build/usr/share/applications/alma.desktop
fi

# Create system-specific postinst (simplified, no Electron binary handling)
cat > extracted/system-postinst.sh << 'EOF'
#!/bin/bash
# System package postinstall - update desktop database and icon cache

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q /usr/share/applications || true
fi

if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi

exit 0
EOF
chmod +x extracted/system-postinst.sh

# Normalize timestamps after all system package content changes.
normalize_timestamps extracted/system-build extracted/system-postinst.sh

echo "  ✓ System package content ready"
echo ""

# --- System RPM ---
echo "[3/4] Building system RPM..."
set_package_type extracted/system-build/usr/lib/alma/resources rpm
write_nfpm_config extracted/nfpm-system-rpm.yaml \
    alma-system \
    x86_64 \
    "$DESCRIPTION (uses system Electron runtime)" \
    extracted/system-build \
    rpm \
    "" \
    alma \
    "$DESCRIPTION (system Electron runtime)"
append_scripts_section extracted/nfpm-system-rpm.yaml extracted/system-postinst.sh
append_script_if_exists extracted/nfpm-system-rpm.yaml postinstall extracted/system-postinst.sh
build_nfpm_package extracted/nfpm-system-rpm.yaml rpm "$SYSTEM_RPM"
echo "  ✓ Created: $SYSTEM_RPM"
echo ""

# --- System Pacman ---
echo "[4/4] Building system Pacman..."
set_package_type extracted/system-build/usr/lib/alma/resources pacman
write_nfpm_config extracted/nfpm-system-archlinux.yaml \
    alma-system \
    x86_64 \
    "$DESCRIPTION (uses system Electron runtime)" \
    extracted/system-build \
    archlinux \
    "electron${ELECTRON_MAJOR}>=1.0.0" \
    alma
append_scripts_section extracted/nfpm-system-archlinux.yaml extracted/system-postinst.sh
append_script_if_exists extracted/nfpm-system-archlinux.yaml postinstall extracted/system-postinst.sh
build_nfpm_package extracted/nfpm-system-archlinux.yaml archlinux "$SYSTEM_PACMAN"
echo "  ✓ Created: $SYSTEM_PACMAN"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "==================================="
echo "Build complete!"
echo "==================================="
echo ""
echo "Standalone packages (with Electron):"
ls -lh dist/alma-$VERSION-*.pkg.tar.zst dist/alma_$VERSION-*.deb 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}'
echo ""
echo "System packages (use system Electron $ELECTRON_MAJOR):"
ls -lh dist/alma-system-$VERSION-*.rpm dist/alma-system-$VERSION-*.pkg.tar.zst 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}'
echo ""
echo "Total packages: $(ls -1 dist/*.{rpm,pkg.tar.zst,deb} 2>/dev/null | wc -l)"
echo "Total blockmaps: $(ls -1 dist/*.blockmap 2>/dev/null | wc -l)"
