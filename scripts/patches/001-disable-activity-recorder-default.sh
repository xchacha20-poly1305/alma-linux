#!/bin/bash
set -euo pipefail

# Disable Alma Activity Recorder by default for first-run Linux installs.

BASE_PATH="${1:?app base path required}"
APP_ASAR="$BASE_PATH/resources/app.asar"

if [[ ! -f "$APP_ASAR" ]]; then
    echo "Error: app.asar not found: $APP_ASAR" >&2
    exit 1
fi

echo "Disabling Activity Recorder by default for first-run Linux installs..."

# Keep replacements byte-for-byte equal in length so the asar header and
# file offsets remain valid. Repacking would lose unpacked-file metadata.
default_config_before='enabled:!0,outputDir'
default_config_after='enabled:!1,outputDir'
autostart_before='n&&!1===n.enabled||('
autostart_after='n&&!!n.enabled&&   ('

count_autostart_marker() {
    local marker="$1"

    AUTOSTART_MARKER="$marker" \
    LC_ALL=C perl -0ne '
        BEGIN {
            $marker = $ENV{AUTOSTART_MARKER};
            $prefix = qr/initializeActivityRecorder\(\)\{try\{const e=[A-Za-z_\$][A-Za-z0-9_\$]*\.getSettings\(\),t=e\?JSON\.parse\(e\.settingsData\):\{\},n=t\?\.activityRecorder;/;
        }
        while (/$prefix\Q$marker\E/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

if ! grep -aFq "$default_config_before" "$APP_ASAR" &&
    grep -aFq "$default_config_after" "$APP_ASAR" &&
    [[ "$(count_autostart_marker "$autostart_before")" -eq 0 ]] &&
    [[ "$(count_autostart_marker "$autostart_after")" -ne 0 ]]; then
    echo "  ✓ Activity Recorder patch already applied, skipping"
    exit 0
fi

if ! grep -aFq "$default_config_before" "$APP_ASAR"; then
    echo "Error: could not find Activity Recorder default config marker in app.asar" >&2
    exit 1
fi

autostart_before_count="$(count_autostart_marker "$autostart_before")"
if [[ "$autostart_before_count" -eq 0 ]]; then
    echo "Error: could not find Activity Recorder auto-start marker in app.asar" >&2
    exit 1
fi

DEFAULT_CONFIG_BEFORE="$default_config_before" \
DEFAULT_CONFIG_AFTER="$default_config_after" \
AUTOSTART_BEFORE="$autostart_before" \
AUTOSTART_AFTER="$autostart_after" \
LC_ALL=C perl -0pi \
    -e 'BEGIN {
            $default_config_before = $ENV{DEFAULT_CONFIG_BEFORE};
            $default_config_after = $ENV{DEFAULT_CONFIG_AFTER};
            $autostart_before = $ENV{AUTOSTART_BEFORE};
            $autostart_after = $ENV{AUTOSTART_AFTER};
        }
        s/\Q$default_config_before\E/$default_config_after/g;
        $autostart_prefix = qr/(initializeActivityRecorder\(\)\{try\{const e=[A-Za-z_\$][A-Za-z0-9_\$]*\.getSettings\(\),t=e\?JSON\.parse\(e\.settingsData\):\{\},n=t\?\.activityRecorder;)/;
        s/($autostart_prefix)\Q$autostart_before\E/$1$autostart_after/g;' \
    "$APP_ASAR"

if grep -aFq "$default_config_before" "$APP_ASAR"; then
    echo "Error: Activity Recorder default config marker was not fully patched" >&2
    exit 1
fi
if ! grep -aFq "$default_config_after" "$APP_ASAR"; then
    echo "Error: patched Activity Recorder default config marker missing" >&2
    exit 1
fi
if [[ "$(count_autostart_marker "$autostart_before")" -ne 0 ]]; then
    echo "Error: Activity Recorder auto-start marker was not fully patched" >&2
    exit 1
fi
if [[ "$(count_autostart_marker "$autostart_after")" -eq 0 ]]; then
    echo "Error: patched Activity Recorder auto-start marker missing" >&2
    exit 1
fi

echo "  ✓ Activity Recorder will stay disabled until the user starts or enables it"
