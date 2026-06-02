# Alma Linux Packages

Automated packaging tool to build multiple Linux package formats for [Alma](https://alma.now).

## Overview

This repository automatically checks for new Alma releases daily and builds the following package formats:

- **RPM** (Fedora, RHEL, openSUSE, etc.)
- **Pacman** (Arch Linux, Manjaro, etc.)
- **DEB** (Debian, Ubuntu, etc.)

Package variants:

- **Standalone** - Includes complete Electron runtime, ready to use out of the box
- **System** - Available for RPM and Pacman only. Uses a distribution-provided Electron runtime, and the launcher rejects executables whose major version does not match Alma's required Electron major.

## Installation

### Arch Linux

**Standalone version:**
```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-VERSION-1-x86_64.pkg.tar.zst
sudo pacman -U alma-VERSION-1-x86_64.pkg.tar.zst
```

**System version** (requires the matching Arch Electron package):
```bash
sudo pacman -S electronXX  # XX is the major version number, e.g., electron38
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-system-VERSION-1-x86_64.pkg.tar.zst
sudo pacman -U alma-system-VERSION-1-x86_64.pkg.tar.zst
```

### Fedora/RHEL

**Standalone version:**
```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-VERSION-1.x86_64.rpm
sudo rpm -i alma-VERSION-1.x86_64.rpm
```

**System version:**

Only use this variant if your distribution provides a compatible Electron runtime. Package names and executable names vary between RPM distributions.

```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-system-VERSION-1.x86_64.rpm
sudo rpm -i alma-system-VERSION-1.x86_64.rpm
```

### Debian/Ubuntu

Only the standalone DEB package is provided. This repository does not ship a system-Electron DEB because Debian/Ubuntu do not consistently provide a compatible Electron runtime through apt.

```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma_VERSION-1_amd64.deb
sudo dpkg -i alma_VERSION-1_amd64.deb
sudo apt-get install -f  # Install dependencies if needed
```

## System Requirements

### Standalone Version
- **No special requirements** - All runtime dependencies included
- Disk space: approximately 300-500 MB

### System Version
- Available package formats: RPM and Pacman
- **Requires system Electron** - Must install a compatible Electron runtime for your distribution
- Disk space: approximately 50-100 MB
- Supported Electron versions: Check the [Releases](https://github.com/xchacha20-poly1305/alma-linux/releases) page for the Electron version required by your Alma version
- Launcher lookup order: `ALMA_ELECTRON`, `electronXX`, `electron-XX`, `electron`, `electronjs`; each candidate must report the required major version via `--version`

Check required Electron version:
```bash
# See the latest release description for the required Electron version
```

## Privacy Defaults

Packages built by this repository disable Alma's Activity Recorder by default on first run. This prevents new Linux installs from immediately starting periodic screen captures, which can trigger repeated screen-sharing prompts on Wayland/xdg-desktop-portal systems.

Users can still enable the recorder explicitly from Alma, or with:

```bash
alma activity start
alma activity config set enabled true
```

## Auto-Update

Alma has built-in auto-update functionality powered by [electron-updater](https://github.com/electron-userland/electron-builder). **Packages from this repository are pre-configured to receive updates from this repository**, no manual configuration needed.

After installation, Alma will automatically check for and download updates from this repository. The update configuration is built into the package:

```yaml
provider: github
owner: xchacha20-poly1305
repo: alma-linux
```

To switch back to the official update source, manually edit the configuration file:
- **Standalone version**: `/opt/Alma/resources/app-update.yml`
- **System version**: `/usr/lib/alma/resources/app-update.yml`

Change to:
```yaml
provider: generic
url: https://updates.alma.now/
updaterCacheDirName: alma-updater
```

**Technical Details**: Alma uses electron-updater 6.6.2, which fully supports GitHub Releases as an update source. The `latest-linux.yml` manifest contains version information, file lists, and SHA512 checksums to ensure secure and reliable updates.

## How It Works

1. **Daily Check** - GitHub Actions runs automatically every day at UTC 02:00
2. **Version Detection** - Fetches `https://updates.alma.now/latest-linux.yml` and parses version number
3. **Build Packages** - If a new version is found:
   - Downloads upstream DEB package
   - Verifies SHA512 checksum
   - Extracts application contents and metadata
   - Applies repository-maintained patches, including disabling the first-run Activity Recorder default for Linux packages
   - Normalizes file timestamps for reproducible builds
   - Repackages into RPM and Pacman formats using fpm 1.17.0
   - Builds system RPM/Pacman versions (contains only app resources and uses matching system Electron runtime)
   - Generates `latest-linux.yml` update manifest
4. **Release** - Creates GitHub Release and uploads all packages and update manifest

### Reproducible Builds

This project implements reproducible builds, ensuring identical inputs produce identical outputs:

- **Fixed Tool Versions**: fpm 1.17.0, yq 4.53.2
- **Fixed Build Environment**: Ubuntu 24.04
- **Normalized Timestamps**: Uses `SOURCE_DATE_EPOCH` environment variable
- **Deterministic Packaging**: All file timestamps unified to release date

This allows anyone to verify the integrity of build artifacts, enhancing security and trustworthiness.

## Technology Stack

- **Packaging Tool**: [fpm](https://github.com/jordansissel/fpm)
- **CI/CD**: GitHub Actions
- **Source Format**: DEB (downloaded from upstream)

## Development

### Local Build

```bash
# 1. Clone repository
git clone https://github.com/xchacha20-poly1305/alma-linux.git
cd alma-linux

# 2. Install dependencies
sudo gem install --no-document fpm -v 1.17.0
sudo apt-get install binutils tar xz-utils wget

# 3. Download latest version
wget https://updates.alma.now/alma-0.0.809-linux-amd64.deb -O alma.deb

# 4. Extract DEB package
chmod +x scripts/extract-deb.sh
./scripts/extract-deb.sh alma.deb

# 5. Detect Electron version
chmod +x scripts/determine-electron.sh
ELECTRON_MAJOR=$(./scripts/determine-electron.sh)

# 6. Build all packages (reproducible builds)
chmod +x scripts/build-packages.sh
export SOURCE_DATE_EPOCH=$(date -d "2024-01-01" +%s)  # Use fixed date or release date
./scripts/build-packages.sh 0.0.809 $ELECTRON_MAJOR

# Generated packages are in the dist/ directory
ls -lh dist/
```

### Project Structure

```
.
├── .github/workflows/
│   └── package.yml           # GitHub Actions workflow
├── scripts/
│   ├── extract-deb.sh        # DEB extraction script
│   ├── build-packages.sh     # Main packaging script
│   ├── determine-electron.sh # Electron version detection
│   └── generate-latest-yml.sh # Update manifest generator
├── metadata/
│   └── alma-wrapper.sh       # System version launcher script
└── dist/                     # Build artifacts (not committed to git)
```

## FAQ

### Q: What's the difference between Standalone and System versions?

**Standalone**: Includes complete Electron runtime, ready to use out of the box, but larger size (~300MB).

**System**: Uses system-installed Electron, smaller size (~50MB), but requires a compatible Electron package and executable from your distribution. The system variant is not provided as a DEB package.

### Q: System version says Electron not found?

Make sure you've installed the matching major version of Electron:

```bash
# Arch Linux
sudo pacman -S electronXX
```

Where `XX` is the major version number, which you can find on the Release page.

The launcher searches `electronXX`, `electron-XX`, `electron`, and `electronjs`, but it only uses a command when `--version` reports the required Electron major. If your distribution uses another name, set `ALMA_ELECTRON` to a matching executable:

```bash
ALMA_ELECTRON=/path/to/electron alma
```

### Q: Why not just use the upstream AppImage/DEB directly?

- Upstream only provides AppImage and DEB formats
- RPM and Pacman users need native package formats for better package manager integration
- RPM/Pacman system versions reduce disk usage when a matching Electron runtime is available

### Q: Do packages auto-update?

Yes. Alma has built-in auto-update support via electron-updater, and **packages from this repository are pre-configured to automatically receive updates from this repository**. No manual configuration needed.

After installation, Alma will automatically check for new versions from this repository and prompt you to update.

## License

This packaging script is licensed under MIT License. Alma is not open source, if this project violates your rights, please contact us to delete it.
