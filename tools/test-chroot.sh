#!/bin/sh
set -eu

ROOTFS="./out/rootfs"
MODE="qemu"
KEEP=0

usage() {
    cat <<EOF
usage: $0 [options]

  --rootfs DIR       rootfs to test (default: ./out/rootfs)
  --mode qemu|native qemu for x86_64 host, native for aarch64 (default: qemu)
  --keep             keep mounts for manual debugging
  -h, --help         show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --rootfs) ROOTFS="$2"; shift 2 ;;
        --mode)   MODE="$2"; shift 2 ;;
        --keep)   KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown: $1" >&2; usage; exit 1 ;;
    esac
done

[ -d "$ROOTFS" ] || { echo "rootfs not found: $ROOTFS" >&2; exit 1; }
[ -x "$ROOTFS/bin/sh" ] || { echo "rootfs missing /bin/sh" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    PRIV=""
elif command -v doas >/dev/null 2>&1; then
    PRIV="doas"
elif command -v sudo >/dev/null 2>&1; then
    PRIV="sudo"
else
    echo "error: need root, doas, or sudo" >&2
    exit 1
fi

case "$MODE" in
    qemu)
        [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || {
            echo "binfmt qemu-aarch64 not registered." >&2
            echo "  alpine: doas apk add qemu-aarch64 qemu-openrc" >&2
            echo "  then:   doas sh -c 'cat /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register'" >&2
            exit 1
        }
        ;;
    native)
        [ "$(uname -m)" = "aarch64" ] || {
            echo "native mode requires aarch64 host, got $(uname -m)" >&2
            exit 1
        }
        ;;
    *) echo "invalid mode: $MODE" >&2; exit 1 ;;
esac

cleanup() {
    [ "$KEEP" -eq 1 ] && { echo "keeping mounts (--keep)"; return; }
    for m in dev sys proc; do
        if mountpoint -q "$ROOTFS/$m" 2>/dev/null; then
            $PRIV umount "$ROOTFS/$m" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT INT TERM

# mount pseudo-filesystems
for m in proc sys dev; do
    if ! mountpoint -q "$ROOTFS/$m" 2>/dev/null; then
        case "$m" in
            proc) $PRIV mount -t proc proc "$ROOTFS/proc" ;;
            sys)  $PRIV mount --bind /sys "$ROOTFS/sys" ;;
            dev)  $PRIV mount --bind /dev "$ROOTFS/dev" ;;
        esac
    fi
done

[ -f tools/test-cases.sh ] || { echo "missing tools/test-cases.sh" >&2; exit 1; }
$PRIV cp tools/test-cases.sh "$ROOTFS/tmp/test-cases.sh"
$PRIV chmod 755 "$ROOTFS/tmp/test-cases.sh"

if [ "$KEEP" -eq 1 ]; then
    echo "rootfs mounted at $ROOTFS"
    echo "run: $PRIV chroot $ROOTFS /bin/sh -l /tmp/test-cases.sh"
    echo "press Enter to cleanup"
    read _
    exit 0
fi

echo "== running test cases =="
if $PRIV chroot "$ROOTFS" /bin/sh -l /tmp/test-cases.sh; then
    RC=0
else
    RC=1
fi

$PRIV rm -f "$ROOTFS/tmp/test-cases.sh"
exit $RC
