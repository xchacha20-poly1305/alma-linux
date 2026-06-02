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
autostart_before='initializeActivityRecorder(){try{const e=Oo.getSettings(),t=e?JSON.parse(e.settingsData):{},n=t?.activityRecorder;n&&!1===n.enabled||('
autostart_after='initializeActivityRecorder(){try{const e=Oo.getSettings(),t=e?JSON.parse(e.settingsData):{},n=t?.activityRecorder;n&&!!n.enabled&&   ('

if ! grep -aFq "$default_config_before" "$APP_ASAR"; then
    echo "Error: could not find Activity Recorder default config marker in app.asar" >&2
    exit 1
fi
if ! grep -aFq "$autostart_before" "$APP_ASAR"; then
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
        s/\Q$autostart_before\E/$autostart_after/g;' \
    "$APP_ASAR"

if grep -aFq "$default_config_before" "$APP_ASAR"; then
    echo "Error: Activity Recorder default config marker was not fully patched" >&2
    exit 1
fi
if grep -aFq "$autostart_before" "$APP_ASAR"; then
    echo "Error: Activity Recorder auto-start marker was not fully patched" >&2
    exit 1
fi

echo "  ✓ Activity Recorder will stay disabled until the user starts or enables it"
