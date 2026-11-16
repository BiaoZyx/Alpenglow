#!/bin/sh
set -eu

# colors (same palette as all / alpenglow-prompt.sh)
P=$(printf '\033[38;5;135m')
D=$(printf '\033[2m')
ERRC=$(printf '\033[38;5;204m')
R=$(printf '\033[0m')

err() { printf '%serror:%s %s\n' "$ERRC" "$R" "$*" >&2; }
hdr() { printf '%s== %s ==%s\n' "$P" "$*" "$R"; }

usage() {
    printf '%susage:%s %s [options]\n\n' "$P" "$R" "$0"
    cat <<EOF
  --board NAME        board profile in config/boards/ (default: duos, prompted with --interactive)
  --rootfs DIR        output rootfs directory (default: ./out/rootfs)
  --interactive       prompt for hostname/timezone/wifi/root-password
  --hostname NAME     set /etc/hostname (default: alpenglow)
  --timezone ZONE     set timezone from host /usr/share/zoneinfo/ (default: UTC)
  --wifi-ssid SSID    preconfigure wpa_supplicant network (open if no password)
  --wifi-pass PASS    wpa password (8-63 chars), requires --wifi-ssid
  --root-pass PASS    set root password in /etc/shadow (default: firstboot alpenglow)
  --list-boards       list available board profiles and exit
  --dry-run           print the build plan and exit (no changes; not with --interactive)
  --clean-old         after a successful build, remove other versions' images from out/
  --keep-cache        keep apk cache in rootfs (for debugging)
  -h, --help          show this help

passwords may also come from the environment when the flag is omitted:
ALPENGLOW_ROOT_PASS / ALPENGLOW_WIFI_PASS
EOF
}

BOARD=""                    # empty = default duos (or prompted with --interactive)
ROOTFS="./out/rootfs"
INTERACTIVE=0
KEEP_CACHE=0
DRY_RUN=0
CLEAN_OLD=0
LIST_BOARDS=0
OPT_HOSTNAME=""
OPT_TIMEZONE=""
OPT_WIFI_SSID=""
OPT_WIFI_PASS=""
OPT_ROOT_PASS=""
ALPENGLOW_VERSION=$(grep '^VERSION_ID=' overlay/usr/lib/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
[ -n "$ALPENGLOW_VERSION" ] || ALPENGLOW_VERSION="1.1"

while [ $# -gt 0 ]; do
    case "$1" in
        --board)        [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; BOARD="$2"; shift 2 ;;
        --rootfs)       [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; ROOTFS="$2"; shift 2 ;;
        --interactive)  INTERACTIVE=1; shift ;;
        --hostname)     [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; OPT_HOSTNAME="$2"; shift 2 ;;
        --timezone)     [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; OPT_TIMEZONE="$2"; shift 2 ;;
        --wifi-ssid)    [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; OPT_WIFI_SSID="$2"; shift 2 ;;
        --wifi-pass)    [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; OPT_WIFI_PASS="$2"; shift 2 ;;
        --root-pass)    [ $# -ge 2 ] || { err "$1 requires a value"; exit 1; }; OPT_ROOT_PASS="$2"; shift 2 ;;
        --list-boards)  LIST_BOARDS=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --clean-old)    CLEAN_OLD=1; shift ;;
        --keep-cache)   KEEP_CACHE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) err "unknown: $1"; usage; exit 1 ;;
    esac
done

# --- trap: say something useful on Ctrl-C instead of dying silently ---
trap 'printf "\n" >&2; err "Interrupted — out/ may contain partial files"; exit 130' INT

# --- --list-boards: informational, exits before anything else ---
if [ "$LIST_BOARDS" = "1" ]; then
    FOUND=0
    for f in config/boards/*.conf; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .conf)
        [ "$b" = "TEMPLATE" ] && continue
        FOUND=1
        nm=$(grep '^BOARD_NAME=' "$f" | cut -d= -f2- | tr -d '"')
        ar=$(grep '^ARCH=' "$f" | cut -d= -f2- | tr -d '"')
        printf '%s%s%s  %s (%s)\n' "$P" "$b" "$R" "${nm:-?}" "${ar:-?}"
    done
    if [ "$FOUND" = "1" ]; then
        exit 0
    else
        err "no board profiles in config/boards/"
        exit 1
    fi
fi

if [ "$DRY_RUN" = "1" ] && [ "$INTERACTIVE" = "1" ]; then
    err "--dry-run cannot be combined with --interactive"
    exit 1
fi

# --- passwords from environment when the flag is omitted ---
[ -z "$OPT_ROOT_PASS" ] && OPT_ROOT_PASS="${ALPENGLOW_ROOT_PASS:-}"
[ -z "$OPT_WIFI_PASS" ] && OPT_WIFI_PASS="${ALPENGLOW_WIFI_PASS:-}"

[ -z "$OPT_WIFI_PASS" ] || [ -n "$OPT_WIFI_SSID" ] || {
    err "--wifi-pass requires --wifi-ssid"; exit 1; }

# --- rootfs safety: this path is rm -rf'd before the build ---
case "$ROOTFS" in
    ""|.|./|/)
        err "Unsafe --rootfs path: '$ROOTFS'"; exit 1 ;;
    *..*)
        err "--rootfs must not contain '..' (got: $ROOTFS)"; exit 1 ;;
    /etc|/usr|/var|/boot|/home|/root|/bin|/lib|/lib32|/lib64|/opt|/srv|/sbin|/mnt|/media|/run|/dev|/proc|/sys|/tmp)
        err "Unsafe --rootfs path (system directory): $ROOTFS"; exit 1 ;;
esac
if [ -n "${HOME:-}" ] && [ "$ROOTFS" = "$HOME" ]; then
    err "Unsafe --rootfs path (refusing \$HOME)"; exit 1
fi

START_TS=$(date +%s)

# --- prompt helpers (for --interactive) ---

# ask PROMPT DEFAULT -> $ANSWER (empty input takes DEFAULT)
ask() {
    printf '%s%s%s %s[%s]%s: ' "$P" "$1" "$R" "$D" "$2" "$R"
    if ! IFS= read -r ANSWER; then
        echo >&2
        err "aborted"
        exit 1
    fi
    [ -n "$ANSWER" ] || ANSWER="$2"
}

# ask_secret PROMPT -> $ANSWER (input hidden)
ask_secret() {
    printf '%s%s%s: ' "$P" "$1" "$R"
    stty -echo 2>/dev/null || true
    if ! IFS= read -r ANSWER; then
        stty echo 2>/dev/null || true
        echo >&2
        err "aborted"
        exit 1
    fi
    stty echo 2>/dev/null || true
    echo
}

# zone_ok ZONE: safe relative name that exists in host zoneinfo
zone_ok() {
    case "$1" in
        ""|/*|*..*) return 1 ;;
    esac
    [ -f "/usr/share/zoneinfo/$1" ]
}

# --- board selection (prompted with --interactive unless --board given) ---
AVAILABLE=$(ls config/boards/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$||' | grep -v '^TEMPLATE$' | tr '\n' ' ')
if [ -z "$BOARD" ]; then
    if [ "$INTERACTIVE" = "1" ]; then
        [ -t 0 ] || { err "--interactive requires a terminal"; exit 1; }
        [ -n "$AVAILABLE" ] || { err "no board profiles in config/boards/"; exit 1; }
        printf '%s  boards:%s %s\n' "$D" "$R" "$AVAILABLE"
        while :; do
            ask "Board" "duos"
            BOARD="$ANSWER"
            case " $AVAILABLE " in
                *" $BOARD "*) break ;;
            esac
            printf '%s  %s%s\n' "$D" "Unknown board, available: $AVAILABLE" "$R" >&2
        done
    else
        BOARD="duos"
    fi
fi

BOARD_CONF="config/boards/${BOARD}.conf"
if [ ! -f "$BOARD_CONF" ]; then
    err "board profile not found: $BOARD_CONF"
    [ -n "$AVAILABLE" ] && printf '%s  available:%s %s\n' "$D" "$R" "$AVAILABLE" >&2
    exit 1
fi
. "$BOARD_CONF"

# required profile variables
for v in BOARD_NAME ARCH; do
    eval "val=\${$v:-}"
    [ -n "$val" ] || { err "$BOARD_CONF missing required variable: $v"; exit 1; }
    unset val
done
for v in BOOT_SIZE_MB LOGO_SIZE_MB ROOTFS_SIZE_MB BOOT_LBA LOGO_LBA ROOTFS_LBA; do
    eval "val=\${$v:-}"
    case "$val" in
        ""|*[!0-9]*|0)
            err "$BOARD_CONF: $v must be a positive integer (got: '${val:-unset}')"
            exit 1 ;;
    esac
    unset val
done

# optional profile variables (defaults = Duo S layout)
SERIAL_CONSOLE="${SERIAL_CONSOLE:-ttyS0}"
SERIAL_BAUD="${SERIAL_BAUD:-115200}"
FW_BOOT_DIR="${FW_BOOT_DIR:-firmware/boot}"
FW_BLOB_DIR="${FW_BLOB_DIR:-firmware/aic8800}"
FW_KO_DIR="${FW_KO_DIR:-firmware/ko}"
FW_BIN_DIR="${FW_BIN_DIR:-firmware/bin}"
FW_PINMAP="${FW_PINMAP:-firmware/duos-map.txt}"
FW_WIRINGX_DIR="${FW_WIRINGX_DIR:-firmware/wiringx}"
FIRMWARE_ALT_DIR="${FIRMWARE_ALT_DIR:-/mnt/system/firmware/aic8800}"

case "$FIRMWARE_ALT_DIR" in
    /*) ;;
    *) err "FIRMWARE_ALT_DIR must be an absolute image path (got: $FIRMWARE_ALT_DIR)"; exit 1 ;;
esac

case "$SERIAL_CONSOLE" in
    ""|*[!A-Za-z0-9]*)
        err "invalid SERIAL_CONSOLE in $BOARD_CONF: $SERIAL_CONSOLE"; exit 1 ;;
esac
case "$SERIAL_BAUD" in
    ""|*[!0-9]*)
        err "invalid SERIAL_BAUD in $BOARD_CONF: $SERIAL_BAUD"; exit 1 ;;
esac

# --- preflight: everything checkable before prompting or touching the system ---
PREFLIGHT_OK=1

check_or_note() {   # $1 = message; hard-fails, except in --dry-run where it is recorded
    if [ "$DRY_RUN" = "1" ]; then
        printf '%s  issue:%s %s\n' "$ERRC" "$R" "$1"
        PREFLIGHT_OK=0
    else
        err "$1"
        exit 1
    fi
}

APK_STATIC="tools/apk.static"
[ -x "$APK_STATIC" ] || check_or_note "Missing $APK_STATIC (download it first)"

REQUIRED="dd mke2fs truncate mkfs.vfat mcopy xz sha256sum sfdisk"
MISSING=""
for t in $REQUIRED; do
    command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] || check_or_note "Missing host tools:$MISSING"

for f in "$FW_BOOT_DIR/fip.bin" "$FW_BOOT_DIR/boot.sd"; do
    [ -f "$f" ] || check_or_note "Missing boot file: $f (extract it from the official image, see README)"
done

if [ -n "$OPT_ROOT_PASS" ] && ! command -v openssl >/dev/null 2>&1; then
    check_or_note "openssl is required to set a root password"
fi

IMG="out/alpenglow-${BOARD_NAME}-${ALPENGLOW_VERSION}.img"
printf '%sboard%s   : %s\n' "$P" "$R" "$BOARD_NAME"
printf '%sarch%s    : %s\n' "$P" "$R" "$ARCH"
printf '%srootfs%s  : %s\n' "$P" "$R" "$ROOTFS"
printf '%soutput%s  : %s\n' "$P" "$R" "$IMG"
printf '%sworld%s   : %s\n' "$P" "$R" "$(tr '\n' ' ' < config/world)"

# --- customization values (defaults, then CLI, then prompts) ---
NEW_HOSTNAME="${OPT_HOSTNAME:-alpenglow}"
NEW_TIMEZONE="$OPT_TIMEZONE"
NEW_WIFI_SSID="$OPT_WIFI_SSID"
NEW_WIFI_PASS="$OPT_WIFI_PASS"
NEW_ROOT_PASS="$OPT_ROOT_PASS"

# --- dry run: print the plan, touch nothing, exit ---
if [ "$DRY_RUN" = "1" ]; then
    hdr "dry run plan"
    printf '%slayout%s    : boot=%sM logo=%sM rootfs=%sM\n' \
        "$P" "$R" "$BOOT_SIZE_MB" "$LOGO_SIZE_MB" "$ROOTFS_SIZE_MB"
    printf '%spartitions%s: boot@LBA%s logo@LBA%s rootfs@LBA%s\n' \
        "$P" "$R" "$BOOT_LBA" "$LOGO_LBA" "$ROOTFS_LBA"

    PRESENT=""
    ABSENT=""
    for d in "$FW_BOOT_DIR" "$FW_BLOB_DIR" "$FW_KO_DIR" "$FW_BIN_DIR" "$FW_WIRINGX_DIR"; do
        if [ -d "$d" ]; then
            PRESENT="$PRESENT ${d#firmware/}"
        else
            ABSENT="$ABSENT ${d#firmware/}"
        fi
    done
    if [ -f "$FW_PINMAP" ]; then
        PRESENT="$PRESENT map"
    else
        ABSENT="$ABSENT map"
    fi
    printf '%ssources%s   : present:%s\n' "$P" "$R" "${PRESENT:- none}"
    [ -n "$ABSENT" ] && printf '            %sabsent (optional):%s%s\n' "$D" "$R" "$ABSENT"

    WIFI_STATUS="not configured"
    if [ -n "$NEW_WIFI_SSID" ]; then
        if [ -n "$NEW_WIFI_PASS" ]; then
            WIFI_STATUS="$NEW_WIFI_SSID (password set)"
        else
            WIFI_STATUS="$NEW_WIFI_SSID (open)"
        fi
    fi
    RP_STATUS="default (alpenglow)"
    [ -n "$NEW_ROOT_PASS" ] && RP_STATUS="set"
    printf '%scustomize%s : hostname=%s timezone=%s\n' \
        "$P" "$R" "$NEW_HOSTNAME" "${NEW_TIMEZONE:-UTC}"
    printf '            %swifi%s=%s\n' "$P" "$R" "$WIFI_STATUS"
    printf '            %srootpass%s=%s\n' "$P" "$R" "$RP_STATUS"

    if [ "$PREFLIGHT_OK" = "1" ]; then
        printf '%schecks%s    : %s\n' "$P" "$R" "ok"
        printf '%sdry run%s   : no changes made\n' "$P" "$R"
        exit 0
    fi
    err "dry run found issues (see above)"
    exit 1
fi

if [ "$INTERACTIVE" = "1" ]; then
    [ -t 0 ] || { err "--interactive requires a terminal"; exit 1; }

    if [ -z "$OPT_HOSTNAME" ]; then
        while :; do
            ask "Hostname" "alpenglow"
            NEW_HOSTNAME="$ANSWER"
            printf '%s' "$NEW_HOSTNAME" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$' && break
            printf '%s  %s%s\n' "$D" "Invalid hostname (letters, digits, '-'; must start with a letter or digit)" "$R" >&2
        done
    fi

    if [ -z "$OPT_TIMEZONE" ]; then
        COMMON=""
        for z in UTC Asia/Shanghai Asia/Tokyo Asia/Hong_Kong Asia/Singapore \
                 Europe/London Europe/Berlin Europe/Moscow \
                 America/New_York America/Chicago America/Los_Angeles \
                 Australia/Sydney; do
            zone_ok "$z" && COMMON="$COMMON $z"
        done
        COMMON="${COMMON# }"
        [ -n "$COMMON" ] && printf '%s  common:%s %s\n' "$D" "$R" "$COMMON"
        while :; do
            ask "Timezone (empty = UTC)" ""
            NEW_TIMEZONE="$ANSWER"
            [ -z "$NEW_TIMEZONE" ] && break
            zone_ok "$NEW_TIMEZONE" && break
            printf '%s  %s%s\n' "$D" "Not found in /usr/share/zoneinfo on this host" "$R" >&2
            SUG=$(find /usr/share/zoneinfo -type f -path "*${NEW_TIMEZONE}*" 2>/dev/null \
                | sed 's|^/usr/share/zoneinfo/||' | head -3 | tr '\n' ' ')
            [ -n "$SUG" ] && printf '%s  %s:%s %s\n' "$D" "Did you mean" "$R" "$SUG" >&2
        done
    fi

    if [ -z "$OPT_WIFI_SSID" ]; then
        ask "Wi-Fi SSID (empty = do not configure)" ""
        NEW_WIFI_SSID="$ANSWER"
    fi
    if [ -n "$NEW_WIFI_SSID" ] && [ -z "$OPT_WIFI_PASS" ]; then
        while :; do
            ask_secret "Wi-Fi password (empty = open network)"
            NEW_WIFI_PASS="$ANSWER"
            [ -z "$NEW_WIFI_PASS" ] && break
            if [ "${#NEW_WIFI_PASS}" -lt 8 ] || [ "${#NEW_WIFI_PASS}" -gt 63 ]; then
                printf '%s  %s%s\n' "$D" "Invalid: WPA passphrase must be 8-63 characters" "$R" >&2
                continue
            fi
            ask_secret "Wi-Fi password (repeat)"
            if [ "$ANSWER" = "$NEW_WIFI_PASS" ]; then
                break
            fi
            printf '%s  %s%s\n' "$D" "Passwords do not match" "$R" >&2
            NEW_WIFI_PASS=""
        done
    fi

    if [ -z "$OPT_ROOT_PASS" ]; then
        while :; do
            ask_secret "Root password (empty = default 'alpenglow')"
            NEW_ROOT_PASS="$ANSWER"
            [ -z "$NEW_ROOT_PASS" ] && break
            if [ "${#NEW_ROOT_PASS}" -lt 6 ]; then
                printf '%s  %s%s\n' "$D" "Too short: minimum 6 characters" "$R" >&2
                continue
            fi
            ask_secret "Root password (repeat)"
            if [ "$ANSWER" = "$NEW_ROOT_PASS" ]; then
                break
            fi
            printf '%s  %s%s\n' "$D" "Passwords do not match" "$R" >&2
            NEW_ROOT_PASS=""
        done
    fi

    printf '%scustomize%s : hostname=%s timezone=%s\n' \
        "$P" "$R" "$NEW_HOSTNAME" "${NEW_TIMEZONE:-UTC}"
    if [ -n "$NEW_WIFI_SSID" ]; then
        if [ -n "$NEW_WIFI_PASS" ]; then
            printf '            %swifi%s=%s (password set)\n' "$P" "$R" "$NEW_WIFI_SSID"
        else
            printf '            %swifi%s=%s (open)\n' "$P" "$R" "$NEW_WIFI_SSID"
        fi
    else
        printf '            %swifi%s=not configured\n' "$P" "$R"
    fi
    if [ -n "$NEW_ROOT_PASS" ]; then
        printf '            %sroot password%s=set\n' "$P" "$R"
    else
        printf '            %sroot password%s=default (alpenglow)\n' "$P" "$R"
    fi
fi

# --- validate final values (CLI and interactive alike) ---
printf '%s' "$NEW_HOSTNAME" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$' || {
    err "invalid hostname: $NEW_HOSTNAME"; exit 1; }
if [ -n "$NEW_TIMEZONE" ] && ! zone_ok "$NEW_TIMEZONE"; then
    err "timezone not found on host: $NEW_TIMEZONE"; exit 1
fi
if [ -n "$NEW_WIFI_PASS" ]; then
    [ -n "$NEW_WIFI_SSID" ] || { err "--wifi-pass requires an SSID"; exit 1; }
    if [ "${#NEW_WIFI_PASS}" -lt 8 ] || [ "${#NEW_WIFI_PASS}" -gt 63 ]; then
        err "Wi-Fi passphrase must be 8-63 characters"; exit 1
    fi
fi
if [ -n "$NEW_ROOT_PASS" ] && [ "${#NEW_ROOT_PASS}" -lt 6 ]; then
    err "root password must be at least 6 characters"; exit 1
fi
if [ -n "$NEW_ROOT_PASS" ] && ! command -v openssl >/dev/null 2>&1; then
    err "openssl is required to set a root password"
    exit 1
fi

# --- confirm before touching the system (interactive only) ---
if [ "$INTERACTIVE" = "1" ]; then
    printf '%sProceed%s with build? %s[Y/n]%s: ' "$P" "$R" "$D" "$R"
    if ! IFS= read -r ANSWER; then
        echo >&2
        err "aborted"
        exit 1
    fi
    case "${ANSWER:-Y}" in
        [Yy]*) ;;
        *) err "aborted by user"; exit 1 ;;
    esac
fi

# --- doas/sudo discovering ---
if [ "$(id -u)" -eq 0 ]; then
    PRIV=""
elif command -v doas >/dev/null 2>&1; then
    PRIV="doas"
elif command -v sudo >/dev/null 2>&1; then
    PRIV="sudo"
else
    err "need root, sudo, or doas"
    exit 1
fi

# --- setup qemu ---

# fix binfmt
if [ -e ./tools/fix-binfmt.sh ]; then
    $PRIV ./tools/fix-binfmt.sh --arch "$ARCH"
elif [ "$ARCH" != "$(uname -m)" ]; then
    err "tools/fix-binfmt.sh not found (required for cross-arch builds)"
    exit 1
else
    printf '%s  %s%s\n' "$D" "Warning: tools/fix-binfmt.sh not found (not needed for this arch)" "$R" >&2
fi

# qemu for cross-arch chroot
if [ "$ARCH" != "$(uname -m)" ]; then
    [ -e /proc/sys/fs/binfmt_misc/qemu-${ARCH} ] || {
        err "qemu-${ARCH} binfmt not registered"
        printf '%s  %s%s\n' "$D" "doas apk add qemu-${ARCH} qemu-openrc" "$R" >&2
        printf '%s  %s%s\n' "$D" "doas sh -c 'cat /usr/lib/binfmt.d/qemu-${ARCH}.conf > /proc/sys/fs/binfmt_misc/register'" "$R" >&2
        exit 1
    }
fi

# --- check before ---
if [ -d "$ROOTFS" ]; then
    $PRIV rm -rf "$ROOTFS" || { err "cannot clean $ROOTFS"; exit 1; }
fi


# --- prepare rootfs ---
$PRIV mkdir -p "$ROOTFS/etc/apk"
$PRIV cp config/repositories "$ROOTFS/etc/apk/repositories"

# --- install packages ---
$PRIV "$APK_STATIC" \
    --root "$ROOTFS" \
    --arch "$ARCH" \
    --initdb \
    --no-cache \
    --allow-untrusted \
    add $(grep -v '^#' config/world | tr '\n' ' ')

# --- overlay ---
hdr overlay
if [ -d overlay ]; then
    $PRIV cp -a overlay/. "$ROOTFS/"
    for d in etc usr mnt dev proc sys var run; do
        if [ -e "$ROOTFS/$d" ]; then
            $PRIV chown -R root:root "$ROOTFS/$d"
        fi
    done
fi

# --- board profile into image ---
hdr board profile
$PRIV mkdir -p "$ROOTFS/etc/alpenglow"
$PRIV cp "$BOARD_CONF" "$ROOTFS/etc/alpenglow/board.conf"
printf '%sbaked%s     : %s\n' "$P" "$R" "/etc/alpenglow/board.conf ($BOARD)"

# --- serial console from profile (getty line is byte-identical for defaults) ---
if [ -f "$ROOTFS/etc/inittab" ]; then
    $PRIV sed -i \
        -e "s|^# Serial console.*|# Serial console ($SERIAL_CONSOLE @ $SERIAL_BAUD)|" \
        -e "s|^[^#]*::respawn:.*|${SERIAL_CONSOLE}::respawn:/sbin/getty -L ${SERIAL_BAUD} ${SERIAL_CONSOLE} vt100|" \
        "$ROOTFS/etc/inittab"
fi
if [ -f "$ROOTFS/etc/conf.d/agetty.ttyS0" ]; then
    if [ "$SERIAL_CONSOLE" != "ttyS0" ]; then
        $PRIV mv "$ROOTFS/etc/conf.d/agetty.ttyS0" "$ROOTFS/etc/conf.d/agetty.${SERIAL_CONSOLE}"
    fi
    $PRIV sed -i "s/^baud=.*/baud=\"${SERIAL_BAUD}\"/" "$ROOTFS/etc/conf.d/agetty.${SERIAL_CONSOLE}"
fi
printf '%sserial%s    : %s\n' "$P" "$R" "$SERIAL_CONSOLE @ $SERIAL_BAUD"

# --- customize: hostname / timezone / wifi / root password ---
hdr customize

echo "$NEW_HOSTNAME" | $PRIV tee "$ROOTFS/etc/hostname" >/dev/null
printf '%shostname%s  : %s\n' "$P" "$R" "$NEW_HOSTNAME"

if [ -n "$NEW_TIMEZONE" ]; then
    $PRIV mkdir -p "$ROOTFS/etc/zoneinfo/$(dirname "$NEW_TIMEZONE")"
    $PRIV cp "/usr/share/zoneinfo/$NEW_TIMEZONE" "$ROOTFS/etc/zoneinfo/$NEW_TIMEZONE"
    $PRIV ln -sf "/etc/zoneinfo/$NEW_TIMEZONE" "$ROOTFS/etc/localtime"
    printf '%stimezone%s  : %s\n' "$P" "$R" "$NEW_TIMEZONE"
else
    printf '%stimezone%s  : %s\n' "$P" "$R" "UTC (default)"
fi

if [ -n "$NEW_WIFI_SSID" ]; then
    ESC_SSID=$(printf '%s' "$NEW_WIFI_SSID" | sed 's/\\/\\\\/g; s/"/\\"/g')
    ESC_PASS=$(printf '%s' "$NEW_WIFI_PASS" | sed 's/\\/\\\\/g; s/"/\\"/g')
    {
        printf '\nnetwork={\n    ssid="%s"\n' "$ESC_SSID"
        if [ -n "$NEW_WIFI_PASS" ]; then
            printf '    psk="%s"\n' "$ESC_PASS"
        else
            printf '    key_mgmt NONE\n'
        fi
        printf '}\n'
    } | $PRIV tee -a "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" >/dev/null
    printf '%swifi%s      : %s\n' "$P" "$R" "$NEW_WIFI_SSID"
fi

if [ -n "$NEW_ROOT_PASS" ]; then
    command -v openssl >/dev/null 2>&1 || {
        err "openssl is required to set a root password"; exit 1; }
    ROOT_HASH=$(printf '%s\n' "$NEW_ROOT_PASS" | openssl passwd -6 -stdin)
    [ -n "$ROOT_HASH" ] || { err "openssl passwd failed"; exit 1; }
    $PRIV sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"
    $PRIV grep -q "^root:${ROOT_HASH}:" "$ROOTFS/etc/shadow" || {
        err "failed to write root password into /etc/shadow"; exit 1; }
    printf '%srootpass%s  : %s\n' "$P" "$R" "set (sha-512, firstboot keeps it)"
fi

# --- build date into os-release ---
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
$PRIV sed -i '/^BUILD_DATE=/d' "$ROOTFS/usr/lib/os-release" 2>/dev/null || true
$PRIV sh -c "echo 'BUILD_DATE=\"$BUILD_DATE\"' >> '$ROOTFS/usr/lib/os-release'"

# --- openrc-init ---
# use openrc-init instead of busybox init (busybox on this build lacks init applet)
$PRIV rm -f "$ROOTFS/sbin/init"
$PRIV ln -sf /sbin/openrc-init "$ROOTFS/sbin/init"

$PRIV ln -sf /sbin/init "$ROOTFS/linuxrc"
$PRIV ln -sf /sbin/init "$ROOTFS/init"

# --- temporary: skip rootfs expand on first boot ---
$PRIV touch "$ROOTFS/etc/alpenglow-skip-expand"

# --- runlevels (apk post-install skips rc-update in chroot) ---
if grep -q '^#\?rc_parallel=' "$ROOTFS/etc/rc.conf"; then
    $PRIV sed -i 's/^#\?rc_parallel=.*/rc_parallel="NO"/' "$ROOTFS/etc/rc.conf"
else
    $PRIV sh -c "echo 'rc_parallel=\"NO\"' >> '$ROOTFS/etc/rc.conf'"
fi

$PRIV mkdir -p "$ROOTFS/etc/runlevels/sysinit" \
    "$ROOTFS/etc/runlevels/boot" \
    "$ROOTFS/etc/runlevels/shutdown" \
    "$ROOTFS/etc/runlevels/default"

for s in devfs dmesg hwdrivers mdev procfs root swap sysfs cgroups; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "/etc/init.d/$s" "$ROOTFS/etc/runlevels/sysinit/$s"
    fi
done

for s in alpenglow-modules wpa_cli bootmisc hostname hwclock klogd localmount loopback modules seedrng sysctl syslog; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "/etc/init.d/$s" "$ROOTFS/etc/runlevels/boot/$s"
    fi
done

for s in killprocs mount-ro savecache; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "/etc/init.d/$s" "$ROOTFS/etc/runlevels/shutdown/$s"
    fi
done

for s in agetty alpenglow-firstboot alpenglow-led dhcpcd dnsmasq dropbear wpa_supplicant local usb-gadget; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "/etc/init.d/$s" "$ROOTFS/etc/runlevels/default/$s"
    fi
done

# --- license/notice ---
$PRIV mkdir -p "$ROOTFS/usr/share/doc/alpenglow"
$PRIV cp LICENSE NOTICE "$ROOTFS/usr/share/doc/alpenglow/"

# --- firmware placeholder ---
# --- AIC8800 firmware ---
if [ -d "$FW_BLOB_DIR" ]; then
    $PRIV mkdir -p "$ROOTFS$FIRMWARE_ALT_DIR"
    $PRIV cp "$FW_BLOB_DIR"/* "$ROOTFS$FIRMWARE_ALT_DIR/"
fi

# --- kernel modules (all .ko + loadsystemko.sh) ---
if [ -d "$FW_KO_DIR" ]; then
    $PRIV mkdir -p "$ROOTFS/mnt/system/ko"
    $PRIV cp -a "$FW_KO_DIR"/. "$ROOTFS/mnt/system/ko/"
fi

# --- duo-pinmux ---
if [ -d "$FW_BIN_DIR" ]; then
    $PRIV mkdir -p "$ROOTFS/usr/local/bin"
    $PRIV cp "$FW_BIN_DIR"/* "$ROOTFS/usr/local/bin/"
    $PRIV chmod 755 "$ROOTFS/usr/local/bin/"*
fi

# --- board pin map (device-side name stays duos-map.txt) ---
if [ -f "$FW_PINMAP" ]; then
    $PRIV mkdir -p "$ROOTFS/usr/local/share/alpenglow"
    $PRIV cp "$FW_PINMAP" "$ROOTFS/usr/local/share/alpenglow/duos-map.txt"
fi

# --- wiringX ---
if [ -d "$FW_WIRINGX_DIR/lib" ]; then
    $PRIV mkdir -p "$ROOTFS/usr/local/lib" "$ROOTFS/usr/local/include"
    $PRIV cp "$FW_WIRINGX_DIR"/lib/* "$ROOTFS/usr/local/lib/"
    $PRIV cp "$FW_WIRINGX_DIR"/include/* "$ROOTFS/usr/local/include/"
    $PRIV chmod 755 "$ROOTFS/usr/local/lib/libwiringx.so"
    $PRIV chmod 644 "$ROOTFS/usr/local/lib/libwiringx.a"
fi

# --- cleanup apk cache unless --keep-cache ---
if [ "$KEEP_CACHE" = "0" ]; then
    $PRIV rm -rf "$ROOTFS/var/cache/apk/"* 2>/dev/null || true
fi

# --- packaging ---
hdr packaging

BOOT_IMG="out/boot.vfat"
ROOTFS_IMG="out/rootfs.ext4"

# boot partition
$PRIV dd if=/dev/zero of="$BOOT_IMG" bs=1M count="$BOOT_SIZE_MB" status=none
$PRIV mkfs.vfat -F 32 -n boot "$BOOT_IMG" >/dev/null
$PRIV env MTOOLS_SKIP_CHECK=1 mcopy -i "$BOOT_IMG" "$FW_BOOT_DIR/fip.bin" ::fip.bin
$PRIV env MTOOLS_SKIP_CHECK=1 mcopy -i "$BOOT_IMG" "$FW_BOOT_DIR/boot.sd" ::boot.sd

# rootfs partition
$PRIV truncate -s "${ROOTFS_SIZE_MB}M" "$ROOTFS_IMG"
$PRIV mke2fs -t ext4 -L rootfs \
    -O ^orphan_file,^metadata_csum_seed \
    -d "$ROOTFS" -F "$ROOTFS_IMG" >/dev/null

# assemble image (+1 MB for MBR and tail sector)
TOTAL_MB=$((BOOT_SIZE_MB + LOGO_SIZE_MB + ROOTFS_SIZE_MB + 1))
$PRIV dd if=/dev/zero of="$IMG" bs=1M count="$TOTAL_MB" status=none
$PRIV dd if="$BOOT_IMG" of="$IMG" bs=512 seek="$BOOT_LBA" conv=notrunc status=none
$PRIV dd if="$ROOTFS_IMG" of="$IMG" bs=512 seek="$ROOTFS_LBA" conv=notrunc status=none

# partition table (MBR), must match official layout
$PRIV sfdisk "$IMG" <<EOF
label: dos
start=${BOOT_LBA}, size=$((BOOT_SIZE_MB * 2048)), type=c, bootable
start=${LOGO_LBA}, size=$((LOGO_SIZE_MB * 2048)), type=0
start=${ROOTFS_LBA}, size=$((ROOTFS_SIZE_MB * 2048)), type=83
EOF
sync

# verify
$PRIV sfdisk -l "$IMG"

# compress
echo "compressing $IMG (this may take several minutes)"
$PRIV xz -9 -T0 --block-size=64MiB -k -f "$IMG"
$PRIV sh -c "cd out && sha256sum '$(basename "$IMG").xz' > '$(basename "$IMG").xz.sha256'"

printf '%simage%s:  %s\n' "$P" "$R" "$IMG"
printf '%sxz%s:     %s\n' "$P" "$R" "$IMG.xz"
printf '%ssize%s:   %s\n' "$P" "$R" "$(du -h "$IMG.xz" 2>/dev/null | cut -f1)"

# --- old images from other versions ---
OLD_COUNT=0
REMOVED=0
for f in out/alpenglow-*.img out/alpenglow-*.img.xz out/alpenglow-*.img.xz.sha256; do
    [ -e "$f" ] || continue
    case "$f" in
        "$IMG"|"$IMG.xz"|"$IMG.xz.sha256") continue ;;
    esac
    OLD_COUNT=$((OLD_COUNT + 1))
    if [ "$CLEAN_OLD" = "1" ]; then
        if $PRIV rm -f "$f"; then
            REMOVED=$((REMOVED + 1))
        fi
    fi
done
if [ "$CLEAN_OLD" = "1" ]; then
    if [ "$REMOVED" -gt 0 ]; then
        printf '  %sRemoved %s old image file(s) from out/.%s\n' "$D" "$REMOVED" "$R"
    fi
elif [ "$OLD_COUNT" -gt 0 ]; then
    printf '  %s%s old image file(s) in out/ — rerun with --clean-old to remove them.%s\n' \
        "$D" "$OLD_COUNT" "$R"
fi

ELAPSED=$(( $(date +%s) - START_TS ))
printf '%stook%s:   %dm%02ds\n' "$P" "$R" $((ELAPSED / 60)) $((ELAPSED % 60))

# --- the end ---
hdr done
printf '%srootfs at%s: %s\n' "$P" "$R" "$ROOTFS"
