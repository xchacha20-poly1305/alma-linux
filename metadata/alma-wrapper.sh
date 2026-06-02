#!/bin/bash
set -euo pipefail

APP_ASAR="/usr/lib/alma/resources/app.asar"
ELECTRON_MAJOR="@ELECTRON_MAJOR@"

commands=()
checked_commands=()

if [[ -n "${ALMA_ELECTRON:-}" ]]; then
    commands+=("$ALMA_ELECTRON")
fi

if [[ "$ELECTRON_MAJOR" =~ ^[0-9]+$ ]]; then
    commands+=("electron${ELECTRON_MAJOR}" "electron-${ELECTRON_MAJOR}" "electron" "electronjs")
else
    echo "Error: invalid Electron major version baked into launcher: $ELECTRON_MAJOR" >&2
    exit 127
fi

electron_major() {
    local command_name="$1"
    local version_output=""
    local version_token=""

    version_output=$("$command_name" --version 2>/dev/null || true)
    version_token=$(printf '%s\n' "$version_output" | grep -Eo 'v?[0-9]+(\.[0-9]+){0,2}' | head -n 1 || true)
    version_token="${version_token#v}"

    if [[ "$version_token" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        printf '%s\n' "${version_token%%.*}"
    fi
}

for command_name in "${commands[@]}"; do
    if command -v "$command_name" >/dev/null 2>&1; then
        detected_major=$(electron_major "$command_name")
        checked_commands+=("$command_name (major: ${detected_major:-unknown})")

        if [[ "$detected_major" == "$ELECTRON_MAJOR" ]]; then
            exec "$command_name" "$APP_ASAR" "$@"
        fi
    else
        checked_commands+=("$command_name (not found)")
    fi
done

{
    echo "Error: could not find a matching system Electron executable."
    echo "Required Electron major: $ELECTRON_MAJOR"
    echo "Checked:"
    for command_name in "${checked_commands[@]}"; do
        echo "  - $command_name"
    done
    echo ""
    echo "Set ALMA_ELECTRON to a matching Electron executable path if your distribution uses a different name."
} >&2

exit 127
