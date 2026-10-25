#!/bin/sh
# Alpenglow build script — skeleton
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

echo "board   : $BOARD_NAME"
echo "arch    : $ARCH"
echo "rootfs  : $ROOTFS"
echo "world   : $(tr '\n' ' ' < config/world)"

# TODO P1-8: apk.static --root "$ROOTFS" --arch "$ARCH" --initdb add $(cat config/world)
# TODO P1-8a: --interactive prompts
# TODO P1-8c: copy LICENSE + NOTICE to $ROOTFS/usr/share/doc/alpenglow/
# TODO P1-12: copy firmware from SDK to $ROOTFS$FIRMWARE_DIR
# TODO P1-10: build .img with GPT, boot + rootfs partitions

echo "TODO: build pipeline not yet implemented"
