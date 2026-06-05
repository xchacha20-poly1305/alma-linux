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

# (2) ni()/ti() only ever sets autoUpdater.updateConfigPath for the dev config, so a
#     packaged system build leaves electron-updater pointing at
#     process.resourcesPath/app-update.yml (missing) and update checks fail to
#     load config. Repurpose that no-op-in-production statement to point the
#     updater at the real config when it exists. 115 bytes -> 115 bytes.
ti_after_prefix='/*alma-linux*/T(H(q(n.getAppPath()),"app-update.yml"))&&('
ti_after_suffix='.updateConfigPath=H(q(n.getAppPath()),"app-update.yml"))'

if [[ "${#li_before}" -ne "${#li_after}" ]]; then
    echo "Error: auto-update support replacement is not byte-for-byte equal in length" >&2
    exit 1
fi

count_literal_marker() {
    local marker="$1"

    LITERAL_MARKER="$marker" \
    LC_ALL=C perl -0ne '
        BEGIN {
            $marker = $ENV{LITERAL_MARKER};
        }
        $count += () = /\Q$marker\E/g;
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

count_ti_before_marker() {
    LC_ALL=C perl -0ne '
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        my $marker = qr/!n\.isPackaged&&T\(($name)\)&&\(($name)\.updateConfigPath=\1,\2\.forceDevUpdateConfig=!0,($name)\.info\(`Using dev update config: \$\{\1\}`\)\)/;
        while (/$marker/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

count_ti_after_marker() {
    TI_AFTER_PREFIX="$ti_after_prefix" \
    TI_AFTER_SUFFIX="$ti_after_suffix" \
    LC_ALL=C perl -0ne '
        BEGIN {
            $prefix = $ENV{TI_AFTER_PREFIX};
            $suffix = $ENV{TI_AFTER_SUFFIX};
            $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        }
        while (/\Q$prefix\E$name\Q$suffix\E/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

li_before_count="$(count_literal_marker "$li_before")"
li_after_count="$(count_literal_marker "$li_after")"
ti_before_count="$(count_ti_before_marker)"
ti_after_count="$(count_ti_after_marker)"

# Check if the patch is already applied
if [[ "$li_before_count" -eq 0 ]] &&
    [[ "$li_after_count" -eq 2 ]] &&
    [[ "$ti_before_count" -eq 0 ]] &&
    [[ "$ti_after_count" -eq 1 ]]; then
    echo "  ✓ Auto-update patch already applied, skipping"
    exit 0
fi

# Check if the original patterns exist
if [[ "$li_before_count" -ne 2 ]]; then
    echo "Error: expected 2 auto-update support markers, found $li_before_count" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi
if [[ "$li_after_count" -ne 0 ]]; then
    echo "Error: auto-update support marker appears partially patched" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi
if [[ "$ti_before_count" -ne 1 ]]; then
    echo "Error: expected 1 updater-config marker, found $ti_before_count" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi
if [[ "$ti_after_count" -ne 0 ]]; then
    echo "Error: updater-config marker appears partially patched" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi

TI_AFTER_PREFIX="$ti_after_prefix" \
TI_AFTER_SUFFIX="$ti_after_suffix" \
LC_ALL=C perl -0ne '
    my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
    my $marker = qr/!n\.isPackaged&&T\(($name)\)&&\(($name)\.updateConfigPath=\1,\2\.forceDevUpdateConfig=!0,($name)\.info\(`Using dev update config: \$\{\1\}`\)\)/;
    while (/$marker/g) {
        my $after = $ENV{TI_AFTER_PREFIX} . $2 . $ENV{TI_AFTER_SUFFIX};
        die "Error: updater-config replacement is not byte-for-byte equal in length\n"
            if length($after) != length($&);
    }' \
    "$APP_ASAR"

LI_BEFORE="$li_before" \
LI_AFTER="$li_after" \
TI_AFTER_PREFIX="$ti_after_prefix" \
TI_AFTER_SUFFIX="$ti_after_suffix" \
LC_ALL=C perl -0pi \
    -e 'BEGIN {
            $li_before = $ENV{LI_BEFORE};
            $li_after = $ENV{LI_AFTER};
            $ti_after_prefix = $ENV{TI_AFTER_PREFIX};
            $ti_after_suffix = $ENV{TI_AFTER_SUFFIX};
            $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
            $ti_before = qr/!n\.isPackaged&&T\(($name)\)&&\(($name)\.updateConfigPath=\1,\2\.forceDevUpdateConfig=!0,($name)\.info\(`Using dev update config: \$\{\1\}`\)\)/;
        }
        s#\Q$li_before\E#$li_after#g;
        s#$ti_before#
            my $before = $&;
            my $updater_var = $2;
            my $after = $ti_after_prefix . $updater_var . $ti_after_suffix;
            $after;
        #eg;' \
    "$APP_ASAR"

li_before_count="$(count_literal_marker "$li_before")"
li_after_count="$(count_literal_marker "$li_after")"
ti_before_count="$(count_ti_before_marker)"
ti_after_count="$(count_ti_after_marker)"

if [[ "$li_before_count" -ne 0 ]]; then
    echo "Error: auto-update support marker was not fully patched" >&2
    exit 1
fi
if [[ "$li_after_count" -ne 2 ]]; then
    echo "Error: patched auto-update support marker count is $li_after_count, expected 2" >&2
    exit 1
fi
if [[ "$ti_before_count" -ne 0 ]]; then
    echo "Error: updater-config marker was not fully patched" >&2
    exit 1
fi
if [[ "$ti_after_count" -ne 1 ]]; then
    echo "Error: patched updater-config marker missing" >&2
    exit 1
fi

echo "  ✓ Auto-update now resolves app-update.yml from the app directory"
