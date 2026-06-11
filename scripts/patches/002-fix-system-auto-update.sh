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
# offsets remain valid. Repacking would lose unpacked-file metadata. Alma's
# minifier regularly renames import aliases, so discover those aliases from the
# current bundle instead of pinning a single release's variable names.

detect_app_var() {
    LC_ALL=C perl -0ne '
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        while (/import\{([^}]*)\}from"electron"/g) {
            my $named = $1;
            if ($named =~ /(?:^|,)\s*app as ($name)(?:,|$)/) {
                print $1;
                exit;
            }
        }' \
        "$APP_ASAR"
}

list_support_join_vars() {
    LC_ALL=C perl -0ne '
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        while (/($name)\(process\.resourcesPath,"app-update\.yml"\)/g) {
            $seen{$1} = 1;
        }
        END {
            print "$_\n" for sort keys %seen;
        }' \
        "$APP_ASAR"
}

detect_dirname_var() {
    local join_var="$1"

    JOIN_VAR="$join_var" \
    LC_ALL=C perl -0ne '
        BEGIN {
            $join = $ENV{JOIN_VAR};
        }
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        while (/import[^;]*\{([^}]*)\}from"(?:node:)?path"/g) {
            my $named = $1;
            next unless $named =~ /(?:^|,)\s*join as \Q$join\E(?:,|$)/;
            if ($named =~ /(?:^|,)\s*dirname as ($name)(?:,|$)/) {
                print $1;
                exit;
            }
        }' \
        "$APP_ASAR"
}

count_support_before_marker() {
    LC_ALL=C perl -0ne '
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        while (/$name\(process\.resourcesPath,"app-update\.yml"\)/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

count_support_after_marker() {
    LC_ALL=C perl -0ne '
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        my $patched = qr/$name\($name\($name\.getAppPath\(\)\),"app-update\.yml"\)(?:\/\*\*\/|[ ]+)/;
        while (/$patched/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

count_ti_before_marker() {
    local app_var="$1"

    APP_VAR="$app_var" \
    LC_ALL=C perl -0ne '
        BEGIN {
            $app = quotemeta($ENV{APP_VAR});
        }
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        my $marker = qr/!$app\.isPackaged&&($name)\(($name)\)&&\(($name)\.updateConfigPath=\2,\3\.forceDevUpdateConfig=!0,($name)\.info\(`Using dev update config: \$\{\2\}`\)\)/;
        while (/$marker/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

count_ti_after_marker() {
    LC_ALL=C perl -0ne '
        my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
        my $path = qr/$name\($name\($name\.getAppPath\(\)\),"app-update\.yml"\)/;
        my $prefix = qr/(?:\/\*[^*]*\*\/[ ]*|[ ]*)/;
        while (/$prefix$name\($path\)&&\($name\.updateConfigPath=$path\)/g) {
            $count++;
        }
        END {
            print $count || 0;
        }' \
        "$APP_ASAR"
}

app_var="$(detect_app_var)"
li_before_count="$(count_support_before_marker)"
li_after_count="$(count_support_after_marker)"
ti_before_count="0"
if [[ -n "$app_var" ]]; then
    ti_before_count="$(count_ti_before_marker "$app_var")"
fi
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
if [[ -z "$app_var" ]]; then
    echo "Error: could not detect Electron app alias for auto-update patch" >&2
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

mapfile -t support_join_vars < <(list_support_join_vars)
if [[ "${#support_join_vars[@]}" -ne 1 ]]; then
    echo "Error: expected 1 auto-update path.join alias, found ${#support_join_vars[@]}" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi

join_var="${support_join_vars[0]}"
dirname_var="$(detect_dirname_var "$join_var")"
if [[ -z "$dirname_var" ]]; then
    echo "Error: could not detect path.dirname alias for auto-update patch" >&2
    echo "This may indicate the Alma version has changed or the patch is partially applied." >&2
    exit 1
fi

APP_VAR="$app_var" \
JOIN_VAR="$join_var" \
DIRNAME_VAR="$dirname_var" \
LC_ALL=C perl -0ne '
    BEGIN {
        $app = $ENV{APP_VAR};
        $join = $ENV{JOIN_VAR};
        $dirname = $ENV{DIRNAME_VAR};
    }

    sub support_padding {
        my ($bytes) = @_;
        die "Error: auto-update support replacement is longer than the original marker\n"
            if $bytes < 1;
        return "/**/" if $bytes == 4;
        return " " x $bytes;
    }

    sub prefix_padding {
        my ($bytes) = @_;
        die "Error: updater-config replacement is longer than the original marker\n"
            if $bytes < 0;
        return "" if $bytes == 0;
        return " " x $bytes if $bytes < 4;
        return "/*alma-linux*/" . (" " x ($bytes - 14)) if $bytes >= 14;
        return "/*" . ("x" x ($bytes - 4)) . "*/";
    }

    my $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
    my $support = qr/\Q$join\E\(process\.resourcesPath,"app-update\.yml"\)/;
    while (/$support/g) {
        my $after = $join . "(" . $dirname . "(" . $app . ".getAppPath()),\"app-update.yml\")";
        $after .= support_padding(length($&) - length($after));
        die "Error: auto-update support replacement is not byte-for-byte equal in length\n"
            if length($after) != length($&);
    }

    my $app_pattern = quotemeta($app);
    my $marker = qr/!$app_pattern\.isPackaged&&($name)\(($name)\)&&\(($name)\.updateConfigPath=\2,\3\.forceDevUpdateConfig=!0,($name)\.info\(`Using dev update config: \$\{\2\}`\)\)/;
    while (/$marker/g) {
        my $exists_var = $1;
        my $updater_var = $3;
        my $path = $join . "(" . $dirname . "(" . $app . ".getAppPath()),\"app-update.yml\")";
        my $tail = $exists_var . "(" . $path . ")&&(" . $updater_var . ".updateConfigPath=" . $path . ")";
        my $after = prefix_padding(length($&) - length($tail)) . $tail;
        die "Error: updater-config replacement is not byte-for-byte equal in length\n"
            if length($after) != length($&);
    }' \
    "$APP_ASAR"

APP_VAR="$app_var" \
JOIN_VAR="$join_var" \
DIRNAME_VAR="$dirname_var" \
LC_ALL=C perl -0pi \
    -e 'BEGIN {
            $app = $ENV{APP_VAR};
            $join = $ENV{JOIN_VAR};
            $dirname = $ENV{DIRNAME_VAR};
            $name = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
            $support_before = qr/\Q$join\E\(process\.resourcesPath,"app-update\.yml"\)/;
            $app_pattern = quotemeta($app);
            $ti_before = qr/!$app_pattern\.isPackaged&&($name)\(($name)\)&&\(($name)\.updateConfigPath=\2,\3\.forceDevUpdateConfig=!0,($name)\.info\(`Using dev update config: \$\{\2\}`\)\)/;
        }
        sub support_padding {
            my ($bytes) = @_;
            die "Error: auto-update support replacement is longer than the original marker\n"
                if $bytes < 1;
            return "/**/" if $bytes == 4;
            return " " x $bytes;
        }
        sub prefix_padding {
            my ($bytes) = @_;
            die "Error: updater-config replacement is longer than the original marker\n"
                if $bytes < 0;
            return "" if $bytes == 0;
            return " " x $bytes if $bytes < 4;
            return "/*alma-linux*/" . (" " x ($bytes - 14)) if $bytes >= 14;
            return "/*" . ("x" x ($bytes - 4)) . "*/";
        }
        s#$support_before#
            my $after = $join . "(" . $dirname . "(" . $app . ".getAppPath()),\"app-update.yml\")";
            $after .= support_padding(length($&) - length($after));
            $after;
        #eg;
        s#$ti_before#
            my $exists_var = $1;
            my $updater_var = $3;
            my $path = $join . "(" . $dirname . "(" . $app . ".getAppPath()),\"app-update.yml\")";
            my $tail = $exists_var . "(" . $path . ")&&(" . $updater_var . ".updateConfigPath=" . $path . ")";
            my $after = prefix_padding(length($&) - length($tail)) . $tail;
            $after;
        #eg;' \
    "$APP_ASAR"

li_before_count="$(count_support_before_marker)"
li_after_count="$(count_support_after_marker)"
ti_before_count="$(count_ti_before_marker "$app_var")"
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
