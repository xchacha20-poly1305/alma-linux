#!/bin/bash
# Quick test script to verify the extraction process works

set -e

echo "=== Testing Alma Linux Packaging Scripts ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
for cmd in ar tar wget; do
    if ! command -v $cmd &>/dev/null; then
        echo "  ✗ Missing: $cmd"
        exit 1
    fi
    echo "  ✓ Found: $cmd"
done

echo ""
echo "Downloading test DEB package (this will take a while, ~300MB)..."
if [[ ! -f alma-test.deb ]]; then
    wget -q --show-progress -O alma-test.deb \
        https://updates.alma.now/alma-0.0.809-linux-amd64.deb
else
    echo "  (using cached alma-test.deb)"
fi

echo ""
echo "Testing extraction script..."
./scripts/extract-deb.sh alma-test.deb

if [[ -f extracted/APP_PATH ]]; then
    APP_PATH=$(cat extracted/APP_PATH)
    echo "  ✓ Found APP_PATH: $APP_PATH"
else
    echo "  ✗ APP_PATH not created"
    exit 1
fi

if [[ -f "extracted/data/$APP_PATH/resources/app.asar" ]]; then
    echo "  ✓ Found app.asar"
else
    echo "  ✗ app.asar not found"
    exit 1
fi

if [[ -f "extracted/DEBIAN/control" ]]; then
    echo "  ✓ Found control file"
    echo ""
    echo "Control file preview:"
    head -10 extracted/DEBIAN/control | sed 's/^/    /'
else
    echo "  ✗ control file not found"
    exit 1
fi

echo ""
echo "Testing Electron version detection..."
./scripts/determine-electron.sh

echo ""
echo "==================================="
echo "✓ All tests passed!"
echo "==================================="
echo ""
echo "To build packages, install fpm and run:"
echo "  sudo gem install fpm"
echo "  ELECTRON_MAJOR=\$(./scripts/determine-electron.sh)"
echo "  ./scripts/build-packages.sh 0.0.809 \$ELECTRON_MAJOR"
