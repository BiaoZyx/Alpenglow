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

# --- prepare rootfs ---
mkdir -p "$ROOTFS/etc/apk"
cp config/repositories "$ROOTFS/etc/apk/repositories"

# --- install packages ---
"$APK_STATIC" \
    --root "$ROOTFS" \
    --arch "$ARCH" \
    --keys-dir "$ROOTFS/etc/apk/keys" \
    --initdb \
    --no-cache \
    --allow-untrusted \
    add $(grep -v '^#' config/world | tr '\n' ' ')

# --- overlay ---
echo "== overlay =="
if [ -d overlay ]; then
    cp -a overlay/. "$ROOTFS/"
fi

# --- license/notice ---
mkdir -p "$ROOTFS/usr/share/doc/alpenglow"
cp LICENSE NOTICE "$ROOTFS/usr/share/doc/alpenglow/"

# --- firmware placeholder ---
mkdir -p "$ROOTFS$FIRMWARE_DIR"
if [ -d firmware ] && [ -n "$(ls -A firmware 2>/dev/null)" ]; then
    cp firmware/* "$ROOTFS$FIRMWARE_DIR/" 2>/dev/null || true
fi

# --- cleanup apk cache unless --keep-cache ---
if [ "$KEEP_CACHE" = "0" ]; then
    rm -rf "$ROOTFS/var/cache/apk/"* 2>/dev/null || true
fi

echo "== done =="
echo "rootfs at: $ROOTFS"
