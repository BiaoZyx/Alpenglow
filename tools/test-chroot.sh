#!/bin/sh
# Alpenglow chroot test — skeleton
set -eu

usage() {
    cat <<EOF
usage: $0 --rootfs DIR [--mode qemu|native] [--keep] [--verbose]
EOF
}

ROOTFS=""
MODE="qemu"
KEEP=0
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --rootfs)   ROOTFS="$2"; shift 2 ;;
        --mode)     MODE="$2"; shift 2 ;;
        --keep)     KEEP=1; shift ;;
        --verbose)  VERBOSE=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "unknown: $1" >&2; usage; exit 1 ;;
    esac
done

[ -n "$ROOTFS" ] && [ -d "$ROOTFS" ] || { echo "--rootfs required" >&2; exit 1; }

case "$MODE" in
    qemu)
        [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || {
            echo "binfmt qemu-aarch64 not registered." >&2
            echo "install qemu-user-static + binfmt support first." >&2
            exit 1
        }
        ;;
    native)
        [ "$(uname -m)" = "aarch64" ] || { echo "native mode requires aarch64 host" >&2; exit 1; }
        ;;
    *) echo "invalid mode: $MODE" >&2; exit 1 ;;
esac

cleanup() {
    for m in sys dev proc; do
        mountpoint -q "$ROOTFS/$m" && umount "$ROOTFS/$m" || true
    done
}
trap cleanup EXIT INT TERM

for m in proc dev sys; do
    mountpoint -q "$ROOTFS/$m" || mount --bind "/$m" "$ROOTFS/$m"
done

[ -f tools/test-cases.sh ] || { echo "missing tools/test-cases.sh" >&2; exit 1; }
cp tools/test-cases.sh "$ROOTFS/tmp/test-cases.sh"

if [ "$KEEP" = "1" ]; then
    echo "rootfs mounted; run: chroot $ROOTFS /bin/sh -l /tmp/test-cases.sh"
    echo "press Enter to cleanup"
    read _
    exit 0
fi

chroot "$ROOTFS" /bin/sh -l /tmp/test-cases.sh
