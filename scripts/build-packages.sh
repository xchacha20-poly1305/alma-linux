#!/bin/bash
set -euo pipefail

# Build all package variants using fpm
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
    SOURCE_DATE_EPOCH=$(date +%s)
    echo "Warning: SOURCE_DATE_EPOCH not set, using current time: $SOURCE_DATE_EPOCH" >&2
fi
export SOURCE_DATE_EPOCH

echo "Building packages for Alma v$VERSION (Electron $ELECTRON_MAJOR)"
echo "Source: $BASE_PATH"
echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH ($(date -d @$SOURCE_DATE_EPOCH 2>/dev/null || date -r $SOURCE_DATE_EPOCH 2>/dev/null))"
echo ""

# Create dist directory
mkdir -p dist

# Normalize timestamps for reproducible builds
echo "Normalizing file timestamps..."
find extracted/data -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} + 2>/dev/null || true
echo "  ✓ Timestamps normalized to $(date -d @$SOURCE_DATE_EPOCH 2>/dev/null || date -r $SOURCE_DATE_EPOCH 2>/dev/null)"
echo ""

# Replace app-update.yml in standalone packages to point to this repository
echo "Updating app-update.yml for standalone packages..."
if [[ -f "$BASE_PATH/resources/app-update.yml" ]]; then
    cat > "$BASE_PATH/resources/app-update.yml" << 'EOF'
provider: github
owner: xchacha20-poly1305
repo: alma-linux
updaterCacheDirName: alma-updater
EOF
fi

# Common metadata
DESCRIPTION="Elegant AI Provider Orchestration"
VENDOR="Alma"
MAINTAINER="安容 <HystericalDragons@proton.me>"
LICENSE="Proprietary"
URL="https://alma.now"

# =============================================================================
# STANDALONE PACKAGES (include full Electron runtime)
# =============================================================================

echo "=== Building Standalone Packages ==="
echo ""

# --- Standalone RPM ---
echo "[1/5] Building standalone RPM..."
fpm -s dir -t rpm \
    -n alma \
    -v "$VERSION" \
    --iteration 1 \
    --architecture x86_64 \
    --description "$DESCRIPTION (standalone with bundled Electron)" \
    --vendor "$VENDOR" \
    --maintainer "$MAINTAINER" \
    --license "$LICENSE" \
    --url "$URL" \
    --prefix / \
    $([ -f extracted/DEBIAN/postinst ] && echo "--after-install extracted/DEBIAN/postinst") \
    $([ -f extracted/DEBIAN/prerm ] && echo "--before-remove extracted/DEBIAN/prerm") \
    --rpm-summary "$DESCRIPTION" \
    --rpm-attr 755,root,root:/opt \
    -C extracted/data \
    -p "dist/alma-VERSION-ITERATION.ARCH.rpm" \
    .

echo "  ✓ Created: $(ls -1 dist/alma-$VERSION-*.rpm 2>/dev/null | head -1)"
echo ""

# --- Standalone Pacman ---
echo "[2/5] Building standalone Pacman..."
fpm -s dir -t pacman \
    -n alma \
    -v "$VERSION" \
    --iteration 1 \
    --architecture x86_64 \
    --description "$DESCRIPTION (standalone with bundled Electron)" \
    --vendor "$VENDOR" \
    --maintainer "$MAINTAINER" \
    --license "$LICENSE" \
    --url "$URL" \
    --prefix / \
    $([ -f extracted/DEBIAN/postinst ] && echo "--after-install extracted/DEBIAN/postinst") \
    $([ -f extracted/DEBIAN/prerm ] && echo "--before-remove extracted/DEBIAN/prerm") \
    -C extracted/data \
    -p "dist/alma-VERSION-ITERATION-ARCH.pkg.tar.zst" \
    .

echo "  ✓ Created: $(ls -1 dist/alma-$VERSION-*.pkg.tar.zst 2>/dev/null | head -1)"
echo ""

# --- Standalone DEB ---
echo "[3/5] Building standalone DEB..."
fpm -s dir -t deb \
    -n alma \
    -v "$VERSION" \
    --iteration 1 \
    --architecture amd64 \
    --description "$DESCRIPTION (standalone with bundled Electron)" \
    --vendor "$VENDOR" \
    --maintainer "$MAINTAINER" \
    --license "$LICENSE" \
    --url "$URL" \
    --prefix / \
    $([ -f extracted/DEBIAN/postinst ] && echo "--after-install extracted/DEBIAN/postinst") \
    $([ -f extracted/DEBIAN/prerm ] && echo "--before-remove extracted/DEBIAN/prerm") \
    $([ -f extracted/DEBIAN/postrm ] && echo "--after-remove extracted/DEBIAN/postrm") \
    --deb-priority optional \
    -C extracted/data \
    -p "dist/alma_VERSION-ITERATION_ARCH.deb" \
    .

echo "  ✓ Created: $(ls -1 dist/alma_$VERSION-*.deb 2>/dev/null | head -1)"
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

# Normalize timestamps for system package
find extracted/system-build -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} + 2>/dev/null || true

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

echo "  ✓ System package content ready"
echo ""

# --- System RPM ---
echo "[4/5] Building system RPM..."
fpm -s dir -t rpm \
    -n alma-system \
    -v "$VERSION" \
    --iteration 1 \
    --architecture x86_64 \
    --description "$DESCRIPTION (uses system Electron runtime)" \
    --vendor "$VENDOR" \
    --maintainer "$MAINTAINER" \
    --license "$LICENSE" \
    --url "$URL" \
    --conflicts alma \
    --after-install extracted/system-postinst.sh \
    --rpm-summary "$DESCRIPTION (system Electron runtime)" \
    --rpm-attr 755,root,root:/usr/lib/alma \
    --rpm-attr 755,root,root:/usr/bin/alma \
    -C extracted/system-build \
    -p "dist/alma-system-VERSION-ITERATION.ARCH.rpm" \
    .

echo "  ✓ Created: $(ls -1 dist/alma-system-$VERSION-*.rpm 2>/dev/null | head -1)"
echo ""

# --- System Pacman ---
echo "[5/5] Building system Pacman..."
fpm -s dir -t pacman \
    -n alma-system \
    -v "$VERSION" \
    --iteration 1 \
    --architecture x86_64 \
    --description "$DESCRIPTION (uses system Electron runtime)" \
    --vendor "$VENDOR" \
    --maintainer "$MAINTAINER" \
    --license "$LICENSE" \
    --url "$URL" \
    --depends "electron${ELECTRON_MAJOR}>=1.0.0" \
    --conflicts alma \
    --after-install extracted/system-postinst.sh \
    -C extracted/system-build \
    -p "dist/alma-system-VERSION-ITERATION-ARCH.pkg.tar.zst" \
    .

echo "  ✓ Created: $(ls -1 dist/alma-system-$VERSION-*.pkg.tar.zst 2>/dev/null | head -1)"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "==================================="
echo "Build complete!"
echo "==================================="
echo ""
echo "Standalone packages (with Electron):"
ls -lh dist/alma-$VERSION-*.rpm dist/alma-$VERSION-*.pkg.tar.zst dist/alma_$VERSION-*.deb 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}'
echo ""
echo "System packages (use system Electron $ELECTRON_MAJOR):"
ls -lh dist/alma-system-$VERSION-*.rpm dist/alma-system-$VERSION-*.pkg.tar.zst 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}'
echo ""
echo "Total packages: $(ls -1 dist/*.{rpm,pkg.tar.zst,deb} 2>/dev/null | wc -l)"
