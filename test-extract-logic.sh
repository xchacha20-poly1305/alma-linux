#!/bin/bash
# Test the extraction logic with a small test DEB

set -e

echo "=== Testing extraction logic ==="
echo ""

# Create a minimal test DEB package
echo "Creating test DEB package..."
mkdir -p test-deb-build/DEBIAN
mkdir -p test-deb-build/opt/TestApp/resources
mkdir -p test-deb-build/usr/share/applications

cat > test-deb-build/DEBIAN/control << 'CTRL'
Package: test-app
Version: 1.0.0
Architecture: amd64
Maintainer: Test <test@example.com>
Description: Test application
CTRL

cat > test-deb-build/DEBIAN/postinst << 'POST'
#!/bin/bash
echo "Test postinst"
POST
chmod +x test-deb-build/DEBIAN/postinst

echo "test app content" > test-deb-build/opt/TestApp/resources/app.asar
echo "v30.0.0" > test-deb-build/opt/TestApp/version

cat > test-deb-build/usr/share/applications/test.desktop << 'DESK'
[Desktop Entry]
Name=Test
Exec=/opt/TestApp/test
DESK

# Build the test DEB
dpkg-deb --build test-deb-build test-app.deb 2>&1 | grep -v "warning"

echo "✓ Test DEB created: test-app.deb"
echo ""

# Test extraction
echo "Testing extract-deb.sh..."
./scripts/extract-deb.sh test-app.deb

# Verify results
if [[ -f extracted/APP_PATH ]]; then
    APP_PATH=$(cat extracted/APP_PATH)
    echo "✓ APP_PATH detected: $APP_PATH"
else
    echo "✗ Failed to detect APP_PATH"
    exit 1
fi

if [[ -f "extracted/data/$APP_PATH/resources/app.asar" ]]; then
    echo "✓ Found app.asar"
else
    echo "✗ app.asar not found"
    exit 1
fi

if [[ -f "extracted/DEBIAN/control" ]]; then
    echo "✓ Found control file"
else
    echo "✗ control file not found"
    exit 1
fi

if [[ -f "extracted/DEBIAN/postinst" && -x "extracted/DEBIAN/postinst" ]]; then
    echo "✓ Found postinst (executable)"
else
    echo "✗ postinst not found or not executable"
    exit 1
fi

echo ""
echo "Testing determine-electron.sh..."
ELECTRON_MAJOR=$(./scripts/determine-electron.sh)

if [[ "$ELECTRON_MAJOR" == "30" ]]; then
    echo "✓ Correctly detected Electron major version: $ELECTRON_MAJOR"
else
    echo "✗ Unexpected Electron version: $ELECTRON_MAJOR (expected 30)"
    exit 1
fi

echo ""
echo "Testing system Electron wrapper..."
mkdir -p test-bin
sed "s/@ELECTRON_MAJOR@/30/g" metadata/alma-wrapper.sh > test-alma-wrapper
chmod +x test-alma-wrapper

cat > test-bin/electron30 << 'ELECTRON'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    echo "v30.0.0"
    exit 0
fi
printf '%s\n' "$@" > "$WRAPPER_OUTPUT"
ELECTRON
chmod +x test-bin/electron30

WRAPPER_OUTPUT="$PWD/test-wrapper-output" PATH="$PWD/test-bin:$PATH" ./test-alma-wrapper --test-flag

if [[ "$(sed -n '1p' test-wrapper-output)" == "/usr/lib/alma/resources/app.asar" ]] &&
   [[ "$(sed -n '2p' test-wrapper-output)" == "--test-flag" ]]; then
    echo "✓ Wrapper used versioned Electron command"
else
    echo "✗ Wrapper did not invoke the expected Electron command"
    cat test-wrapper-output
    exit 1
fi

rm -f test-bin/electron30 test-wrapper-output
cat > test-bin/electron << 'ELECTRON'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    echo "v29.0.0"
    exit 0
fi
printf '%s\n' "$@" > "$WRAPPER_OUTPUT"
ELECTRON
chmod +x test-bin/electron

if WRAPPER_OUTPUT="$PWD/test-wrapper-output" PATH="$PWD/test-bin:$PATH" ./test-alma-wrapper --test-flag 2>/dev/null; then
    echo "✗ Wrapper accepted an Electron executable with the wrong major version"
    exit 1
fi

if [[ -f test-wrapper-output ]]; then
    echo "✗ Wrong-version Electron command was executed"
    cat test-wrapper-output
    exit 1
fi

echo "✓ Wrapper rejected wrong-version Electron command"

# Cleanup
rm -rf test-deb-build test-app.deb extracted test-bin test-alma-wrapper test-wrapper-output

echo ""
echo "==================================="
echo "✓ All extraction logic tests passed!"
echo "==================================="
