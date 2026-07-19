#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/scripts/patches"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    echo "Error: $*" >&2
    exit 1
}

make_app_dir() {
    local name="$1"
    local app_dir="$TMP_DIR/$name"

    mkdir -p "$app_dir/resources"
    printf '%s\n' "$app_dir"
}

count_marker() {
    local file="$1"
    local marker="$2"

    MARKER="$marker" \
    LC_ALL=C perl -0ne '
        BEGIN {
            $marker = $ENV{MARKER};
        }
        $count += () = /\Q$marker\E/g;
        END {
            print $count || 0;
        }' \
        "$file"
}

assert_count() {
    local file="$1"
    local marker="$2"
    local expected="$3"
    local actual

    actual="$(count_marker "$file" "$marker")"
    [[ "$actual" -eq "$expected" ]] ||
        fail "expected marker count $expected, found $actual: $marker"
}

assert_fails() {
    local description="$1"
    shift

    if "$@" >"$TMP_DIR/expected-failure.log" 2>&1; then
        fail "$description unexpectedly succeeded"
    fi
}

test_activity_recorder_patch() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir activity-recorder)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
const NT={enabled:!0,outputDir:"/tmp/alma-activity"};
class Api{initializeActivityRecorder(){try{const e=Ro.getSettings(),t=e?JSON.parse(e.settingsData):{},n=t?.activityRecorder;n&&!1===n.enabled||(this.ensureActivityServices(),this.activityRecorderService?.start())}catch(e){}}}
EOF

    "$PATCH_DIR/001-disable-activity-recorder-default.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'enabled:!0,outputDir' 0
    assert_count "$app_asar" 'enabled:!1,outputDir' 1
    assert_count "$app_asar" 'n&&!1===n.enabled||(' 0
    assert_count "$app_asar" 'n&&!!n.enabled&&   (' 1

    "$PATCH_DIR/001-disable-activity-recorder-default.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'enabled:!1,outputDir' 1
    assert_count "$app_asar" 'n&&!!n.enabled&&   (' 1
}

test_activity_recorder_duplicate_marker_fails() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir activity-recorder-duplicate)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
const NT={enabled:!0,outputDir:"/tmp/alma-activity"};
const OTHER={enabled:!0,outputDir:"/tmp/alma-activity-other"};
class Api{initializeActivityRecorder(){try{const e=Oo.getSettings(),t=e?JSON.parse(e.settingsData):{},n=t?.activityRecorder;n&&!1===n.enabled||(this.ensureActivityServices(),this.activityRecorderService?.start())}catch(e){}}}
EOF

    assert_fails "duplicate Activity Recorder default config marker" \
        "$PATCH_DIR/001-disable-activity-recorder-default.sh" "$app_dir"
}

test_activity_recorder_linux_autostart_patch() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir activity-recorder-linux-autostart)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
const NT={enabled:!0,outputDir:"/tmp/alma-activity"};
class Api{initializeActivityRecorder(){try{const e=Ro.getSettings(),t=e?JSON.parse(e.settingsData):{},n=t?.activityRecorder;(function(e,t){return"linux"===e?!0===t?.enabled:!(t&&!1===t.enabled)})(process.platform,n)&&(this.ensureActivityServices(),this.activityRecorderService?.start())}catch(e){}}}
EOF

    "$PATCH_DIR/001-disable-activity-recorder-default.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'enabled:!0,outputDir' 0
    assert_count "$app_asar" 'enabled:!1,outputDir' 1
    assert_count "$app_asar" 'return"linux"===e?!0===t?.enabled:!(t&&!1===t.enabled)' 0
    assert_count "$app_asar" 'return"linux"===e?!!t?.enabled   :!(t&&!1===t.enabled)' 1

    "$PATCH_DIR/001-disable-activity-recorder-default.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'enabled:!1,outputDir' 1
    assert_count "$app_asar" 'return"linux"===e?!!t?.enabled   :!(t&&!1===t.enabled)' 1
}

test_auto_update_patch() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir auto-update)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
import{app as n}from"electron";import p,{dirname as q,join as H}from"path";
function ni(){if(!ti){const e=Vr("electron-updater");ti=e.autoUpdater,ti.logger={info:Qr.info,warn:Qr.warn,error:Qr.error,debug:Qr.log},!n.isPackaged&&T(Kr)&&(ti.updateConfigPath=Kr,ti.forceDevUpdateConfig=!0,Qr.info(`Using dev update config: ${Kr}`))}return ti}
function di(){const e=H(process.resourcesPath,"app-update.yml");const t=H(process.resourcesPath,"app-update.yml");return T(e)||T(t)}
const identity=path.join(process.resourcesPath, "package-type");console.info("Checking for beta autoupdate feature for deb/rpm distributions");
EOF

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'H(process.resourcesPath,"app-update.yml")' 0
    assert_count "$app_asar" 'H(q(n.getAppPath()),"app-update.yml")/**/' 2
    assert_count "$app_asar" '!n.isPackaged&&T(Kr)&&(ti.updateConfigPath=Kr,ti.forceDevUpdateConfig=!0,Qr.info(`Using dev update config: ${Kr}`))' 0
    assert_count "$app_asar" '/*alma-linux*/T(H(q(n.getAppPath()),"app-update.yml"))&&(ti.updateConfigPath=H(q(n.getAppPath()),"app-update.yml"))' 1
    assert_count "$app_asar" 'path.join(process.resourcesPath, "package-type")' 0
    assert_count "$app_asar" 'path.join(process.env.APPDIR||process.resourcesPath,"package-type")' 1

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'H(q(n.getAppPath()),"app-update.yml")/**/' 2
    assert_count "$app_asar" '/*alma-linux*/T(H(q(n.getAppPath()),"app-update.yml"))&&(ti.updateConfigPath=H(q(n.getAppPath()),"app-update.yml"))' 1
    assert_count "$app_asar" 'path.join(process.env.APPDIR||process.resourcesPath,"package-type")' 1
}

test_auto_update_patch_renamed_aliases() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir auto-update-renamed-aliases)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
import{app as n}from"electron";import q,{dirname as H,join as X}from"path";
function Qr(){if(!Kr){const e=Hr("electron-updater");Kr=e.autoUpdater,Kr.logger={info:Yr.info,warn:Yr.warn,error:Yr.error,debug:Yr.log},!n.isPackaged&&E(Xr)&&(Kr.updateConfigPath=Xr,Kr.forceDevUpdateConfig=!0,Yr.info(`Using dev update config: ${Xr}`))}return Kr}
function ii(){return Jr.has(process.platform)&&function(){if(n.isPackaged){const e=X(process.resourcesPath,"app-update.yml");return E(e)}return E(Xr)}()}
function prewarm(){const e=n.isPackaged?X(process.resourcesPath,"app-update.yml"):Xr;return E(e)}
const identity=path.join(process.resourcesPath,"package-type");console.info("Checking for beta autoupdate feature for deb/rpm distributions");
EOF

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'X(process.resourcesPath,"app-update.yml")' 0
    assert_count "$app_asar" 'X(H(n.getAppPath()),"app-update.yml")/**/' 2
    assert_count "$app_asar" '!n.isPackaged&&E(Xr)&&(Kr.updateConfigPath=Xr,Kr.forceDevUpdateConfig=!0,Yr.info(`Using dev update config: ${Xr}`))' 0
    assert_count "$app_asar" '/*alma-linux*/E(X(H(n.getAppPath()),"app-update.yml"))&&(Kr.updateConfigPath=X(H(n.getAppPath()),"app-update.yml"))' 1
    assert_count "$app_asar" 'path.join(process.resourcesPath,"package-type")' 0
    assert_count "$app_asar" 'path.join(process.env.APPDIR||process.resourcesPath,"package-type")' 1

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'X(H(n.getAppPath()),"app-update.yml")/**/' 2
    assert_count "$app_asar" '/*alma-linux*/E(X(H(n.getAppPath()),"app-update.yml"))&&(Kr.updateConfigPath=X(H(n.getAppPath()),"app-update.yml"))' 1
    assert_count "$app_asar" 'path.join(process.env.APPDIR||process.resourcesPath,"package-type")' 1
}

test_auto_update_patch_symbol_aliases() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir auto-update-symbol-aliases)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
import{app as a}from"electron";import p,{dirname as _,join as $}from"path";
function uo(){if(!u){const r=R("electron-updater");u=r.autoUpdater,u.logger={info:l.info,warn:l.warn,error:l.error,debug:l.log},!a.isPackaged&&e(c)&&(u.updateConfigPath=c,u.forceDevUpdateConfig=!0,l.info(`Using dev update config: ${c}`))}return u}
function so(){const r=$(process.resourcesPath,"app-update.yml");const t=$(process.resourcesPath,"app-update.yml");return e(r)||e(t)}
const identity=path.join(process.resourcesPath, "package-type");console.info("Checking for beta autoupdate feature for deb/rpm distributions");
EOF

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" '$(process.resourcesPath,"app-update.yml")' 0
    assert_count "$app_asar" '$(_(a.getAppPath()),"app-update.yml")/**/' 2
    assert_count "$app_asar" '!a.isPackaged&&e(c)&&(u.updateConfigPath=c,u.forceDevUpdateConfig=!0,l.info(`Using dev update config: ${c}`))' 0
    assert_count "$app_asar" '/*xxxxx*/e($(_(a.getAppPath()),"app-update.yml"))&&(u.updateConfigPath=$(_(a.getAppPath()),"app-update.yml"))' 1
    assert_count "$app_asar" 'path.join(process.resourcesPath, "package-type")' 0
    assert_count "$app_asar" 'path.join(process.env.APPDIR||process.resourcesPath,"package-type")' 1

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" '$(_(a.getAppPath()),"app-update.yml")/**/' 2
    assert_count "$app_asar" '/*xxxxx*/e($(_(a.getAppPath()),"app-update.yml"))&&(u.updateConfigPath=$(_(a.getAppPath()),"app-update.yml"))' 1
    assert_count "$app_asar" 'path.join(process.env.APPDIR||process.resourcesPath,"package-type")' 1
}

test_auto_update_patch_three_markers() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir auto-update-three-markers)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
import{app as n}from"electron";import p,{dirname as q,join as H}from"path";
function ni(){if(!ti){const e=Vr("electron-updater");ti=e.autoUpdater,ti.logger={info:Qr.info,warn:Qr.warn,error:Qr.error,debug:Qr.log},!n.isPackaged&&T(Kr)&&(ti.updateConfigPath=Kr,ti.forceDevUpdateConfig=!0,Qr.info(`Using dev update config: ${Kr}`))}return ti}
function di(){const e=H(process.resourcesPath,"app-update.yml");const t=H(process.resourcesPath,"app-update.yml");const o=H(process.resourcesPath,"app-update.yml");return T(e)||T(t)||T(o)}
const identity=path.join(process.resourcesPath, "package-type");console.info("Checking for beta autoupdate feature for deb/rpm distributions");
EOF

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'H(process.resourcesPath,"app-update.yml")' 0
    assert_count "$app_asar" 'H(q(n.getAppPath()),"app-update.yml")/**/' 3

    "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir" >/dev/null
    assert_count "$app_asar" 'H(q(n.getAppPath()),"app-update.yml")/**/' 3
}

test_auto_update_duplicate_marker_fails() {
    local app_dir
    local app_asar

    app_dir="$(make_app_dir auto-update-duplicate)"
    app_asar="$app_dir/resources/app.asar"

    cat > "$app_asar" <<'EOF'
import{app as n}from"electron";import p,{dirname as q,join as H}from"path";
function ni(){if(!ti){const e=Vr("electron-updater");ti=e.autoUpdater,ti.logger={info:Qr.info,warn:Qr.warn,error:Qr.error,debug:Qr.log},!n.isPackaged&&T(Kr)&&(ti.updateConfigPath=Kr,ti.forceDevUpdateConfig=!0,Qr.info(`Using dev update config: ${Kr}`))}return ti}
function di(){const e=H(process.resourcesPath,"app-update.yml");const t=H(process.resourcesPath,"app-update.yml");const o=H(process.resourcesPath,"app-update.yml");const r=H(process.resourcesPath,"app-update.yml");return T(e)||T(t)||T(o)||T(r)}
const identity=path.join(process.resourcesPath, "package-type");console.info("Checking for beta autoupdate feature for deb/rpm distributions");
EOF

    assert_fails "duplicate auto-update support marker" \
        "$PATCH_DIR/002-fix-system-auto-update.sh" "$app_dir"
}

test_activity_recorder_patch
test_activity_recorder_duplicate_marker_fails
test_activity_recorder_linux_autostart_patch
test_auto_update_patch
test_auto_update_patch_renamed_aliases
test_auto_update_patch_symbol_aliases
test_auto_update_patch_three_markers
test_auto_update_duplicate_marker_fails

echo "Patch fixture tests passed"
