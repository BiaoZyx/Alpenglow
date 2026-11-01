#!/bin/sh
set -eu

usage() {
    cat <<EOF
usage: $0 [options]

  --board NAME        board profile in config/boards/ (default: duos)
  --rootfs DIR        output rootfs directory (default: ./out/rootfs)
  --interactive       prompt for hostname/timezone/ssh/zram
  --keep-cache        keep apk cache in rootfs (for debugging)
  -h, --help          show this help
EOF
}

BOARD="duos"
ROOTFS="./out/rootfs"
INTERACTIVE=0
KEEP_CACHE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --board)        BOARD="$2"; shift 2 ;;
        --rootfs)       ROOTFS="$2"; shift 2 ;;
        --interactive)  INTERACTIVE=1; shift ;;
        --keep-cache)   KEEP_CACHE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "unknown: $1" >&2; usage; exit 1 ;;
    esac
done

BOARD_CONF="config/boards/${BOARD}.conf"
[ -f "$BOARD_CONF" ] || { echo "board profile not found: $BOARD_CONF" >&2; exit 1; }
. "$BOARD_CONF"

APK_STATIC="tools/apk.static"
[ -x "$APK_STATIC" ] || { echo "missing $APK_STATIC (download it first)" >&2; exit 1; }

echo "board   : $BOARD_NAME"
echo "arch    : $ARCH"
echo "rootfs  : $ROOTFS"
echo "world   : $(tr '\n' ' ' < config/world)"

# --- doas/sudo discovering ---
if [ "$(id -u)" -eq 0 ]; then
    PRIV=""
elif command -v doas >/dev/null 2>&1; then
    PRIV="doas"
elif command -v sudo >/dev/null 2>&1; then
    PRIV="sudo"
else
    echo "error: need root, sudo, or doas" >&2
    exit 1
fi

# --- check before ---
if [ -d "$ROOTFS" ]; then
    $PRIV rm -rf "$ROOTFS" || { echo "error: cannot clean $ROOTFS" >&2; exit 1; }
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
echo "== overlay =="
if [ -d overlay ]; then
    $PRIV cp -a overlay/. "$ROOTFS/"
    for d in etc usr/lib/os-release usr/local mnt; do
        if [ -e "$ROOTFS/$d" ]; then
            $PRIV chown -R root:root "$ROOTFS/$d"
        fi
    done
fi

# --- runlevels (apk post-install skips rc-update in chroot) ---
$PRIV sh -c "echo 'rc_parallel=\"YES\"' >> '$ROOTFS/etc/rc.conf'"

$PRIV mkdir -p "$ROOTFS/etc/runlevels/sysinit" \
    "$ROOTFS/etc/runlevels/boot" \
    "$ROOTFS/etc/runlevels/shutdown" \
    "$ROOTFS/etc/runlevels/default"

for s in devfs dmesg hwdrivers mdev procfs root swap sysfs cgroups; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "../init.d/$s" "$ROOTFS/etc/runlevels/sysinit/$s"
    fi
done

for s in bootmisc hostname hwclock klogd localmount loopback modules seedrng sysctl syslog; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "../init.d/$s" "$ROOTFS/etc/runlevels/boot/$s"
    fi
done

for s in killprocs mount-ro savecache; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "../init.d/$s" "$ROOTFS/etc/runlevels/shutdown/$s"
    fi
done

for s in dropbear local; do
    if [ -x "$ROOTFS/etc/init.d/$s" ]; then
        $PRIV ln -sf "../init.d/$s" "$ROOTFS/etc/runlevels/default/$s"
    fi
done

# --- license/notice ---
$PRIV mkdir -p "$ROOTFS/usr/share/doc/alpenglow"
$PRIV cp LICENSE NOTICE "$ROOTFS/usr/share/doc/alpenglow/"

# --- firmware placeholder ---
$PRIV mkdir -p "$ROOTFS$FIRMWARE_DIR" "$ROOTFS$FIRMWARE_ALT_DIR"
if [ -d firmware ] && [ -n "$(ls -A firmware 2>/dev/null)" ]; then
    $PRIV cp firmware/* "$ROOTFS$FIRMWARE_DIR/" 2>/dev/null || true
    $PRIV cp firmware/* "$ROOTFS$FIRMWARE_ALT_DIR/" 2>/dev/null || true
fi

# --- cleanup apk cache unless --keep-cache ---
if [ "$KEEP_CACHE" = "0" ]; then
    $PRIV rm -rf "$ROOTFS/var/cache/apk/"* 2>/dev/null || true
fi

echo "== done =="
echo "rootfs at: $ROOTFS"
