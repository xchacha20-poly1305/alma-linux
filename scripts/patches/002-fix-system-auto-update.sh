#!/bin/bash
set -euo pipefail

# Make auto-update work for the *system* package (system Electron launches
# /usr/lib/alma/resources/app.asar). In that setup process.resourcesPath points
# at the system Electron's own resources dir (e.g. /usr/lib/electron37/resources)
# instead of /usr/lib/alma/resources, so Alma's "is auto-update supported" check
# never finds app-update.yml and the About screen shows:
#   "Auto-update is only available for distribution builds."
#
# Fix: resolve the config from path.dirname(app.getAppPath()) instead of
# process.resourcesPath. getAppPath() returns the app.asar path for both layouts:
#   standalone -> /opt/Alma/resources/app.asar      -> dir /opt/Alma/resources
#   system     -> /usr/lib/alma/resources/app.asar  -> dir /usr/lib/alma/resources
# which is exactly where build-packages.sh writes app-update.yml. The standalone
# package is unaffected (same directory as resourcesPath there).

BASE_PATH="${1:?app base path required}"
APP_ASAR="$BASE_PATH/resources/app.asar"

if [[ ! -f "$APP_ASAR" ]]; then
    echo "Error: app.asar not found: $APP_ASAR" >&2
    exit 1
fi

echo "Fixing auto-update detection for system Electron launches..."

# Keep replacements byte-for-byte equal in length so the asar header and file
# offsets remain valid. Repacking would lose unpacked-file metadata.
# H = path.join, q = path.dirname, n = electron app, T = fs.existsSync.

# (1) Support check li() and the macOS pre-warm helper both resolve the config
#     from process.resourcesPath. Swap that for dirname(app.getAppPath()).
#     41 bytes -> 41 bytes (padded with an empty /**/ comment).
li_before='H(process.resourcesPath,"app-update.yml")'
li_after='H(q(n.getAppPath()),"app-update.yml")/**/'

# (2) ti() only ever sets autoUpdater.updateConfigPath for the dev config, so a
#     packaged system build leaves electron-updater pointing at
#     process.resourcesPath/app-update.yml (missing) and update checks fail to
#     load config. Repurpose that no-op-in-production statement to point the
#     updater at the real config when it exists. 115 bytes -> 115 bytes.
ti_before='!n.isPackaged&&T(Vr)&&(ei.updateConfigPath=Vr,ei.forceDevUpdateConfig=!0,Kr.info(`Using dev update config: ${Vr}`))'
ti_after='/*alma-linux*/T(H(q(n.getAppPath()),"app-update.yml"))&&(ei.updateConfigPath=H(q(n.getAppPath()),"app-update.yml"))'

# Check if the patch is already applied
if grep -aFq "$li_after" "$APP_ASAR" && grep -aFq "$ti_after" "$APP_ASAR"; then
    echo "  ✓ Auto-update patch already applied, skipping"
    exit 0
fi

# Check if the original patterns exist
if ! grep -aFq "$li_before" "$APP_ASAR"; then
    echo "Error: could not find auto-update support marker in app.asar" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi
if ! grep -aFq "$ti_before" "$APP_ASAR"; then
    echo "Error: could not find updater-config marker in app.asar" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi

LI_BEFORE="$li_before" \
LI_AFTER="$li_after" \
TI_BEFORE="$ti_before" \
TI_AFTER="$ti_after" \
LC_ALL=C perl -0pi \
    -e 'BEGIN {
            $li_before = $ENV{LI_BEFORE};
            $li_after = $ENV{LI_AFTER};
            $ti_before = $ENV{TI_BEFORE};
            $ti_after = $ENV{TI_AFTER};
        }
        s#\Q$li_before\E#$li_after#g;
        s#\Q$ti_before\E#$ti_after#g;' \
    "$APP_ASAR"

if grep -aFq "$li_before" "$APP_ASAR"; then
    echo "Error: auto-update support marker was not fully patched" >&2
    exit 1
fi
if grep -aFq "$ti_before" "$APP_ASAR"; then
    echo "Error: updater-config marker was not fully patched" >&2
    exit 1
fi
if ! grep -aFq "$li_after" "$APP_ASAR"; then
    echo "Error: patched auto-update support marker missing" >&2
    exit 1
fi
if ! grep -aFq "$ti_after" "$APP_ASAR"; then
    echo "Error: patched updater-config marker missing" >&2
    exit 1
fi

echo "  ✓ Auto-update now resolves app-update.yml from the app directory"
