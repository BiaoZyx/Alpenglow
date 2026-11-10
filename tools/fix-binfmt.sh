#!/bin/sh
# Register qemu-<ARCH> binfmt for cross-arch chroot on WSL or any x86_64 host.
# Idempotent: safe to run repeatedly. Use --force to remount and re-register.
set -eu

ARCH="aarch64"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --arch)  ARCH="$2"; shift 2 ;;
        -h|--help)
            echo "usage: $0 [--arch aarch64] [--force]"
            exit 0
            ;;
        *) echo "unknown: $1" >&2; exit 1 ;;
    esac
done

CONF="/usr/lib/binfmt.d/qemu-${ARCH}.conf"
MNT="/proc/sys/fs/binfmt_misc"
REG_FILE="${MNT}/register"
REG_ENTRY="${MNT}/qemu-${ARCH}"

# privilege
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

# already registered?
if [ "$FORCE" -eq 0 ] && [ -f "$REG_ENTRY" ] && grep -q '^enabled' "$REG_ENTRY" 2>/dev/null; then
    echo "qemu-${ARCH} binfmt already registered"
    grep '^interpreter' "$REG_ENTRY"
    exit 0
fi

# config file present?
if [ ! -f "$CONF" ]; then
    echo "error: $CONF not found" >&2
    echo "  doas apk add qemu-${ARCH} qemu-openrc" >&2
    exit 1
fi

# force: unmount to reset state (lazy if busy)
if [ "$FORCE" -eq 1 ] && mountpoint -q "$MNT" 2>/dev/null; then
    $PRIV umount "$MNT" 2>/dev/null || $PRIV umount -l "$MNT" 2>/dev/null || true
fi

# mount binfmt_misc if needed
if ! mountpoint -q "$MNT" 2>/dev/null; then
    $PRIV modprobe binfmt_misc 2>/dev/null || true
    $PRIV mount -t binfmt_misc binfmt_misc "$MNT" 2>/dev/null || {
        [ -d "$MNT" ] || { echo "error: cannot mount $MNT" >&2; exit 1; }
    }
fi

# already registered after mount? (covers --force with existing entry)
if [ -f "$REG_ENTRY" ] && grep -q '^enabled' "$REG_ENTRY" 2>/dev/null; then
    echo "qemu-${ARCH} binfmt already registered"
    grep '^interpreter' "$REG_ENTRY"
    exit 0
fi

# register
$PRIV sh -c "cat '$CONF' > '$REG_FILE'" 2>/dev/null || {
    echo "register failed, retrying with force remount" >&2
    $PRIV umount "$MNT" 2>/dev/null || $PRIV umount -l "$MNT" 2>/dev/null || true
    $PRIV mount -t binfmt_misc binfmt_misc "$MNT"
    $PRIV sh -c "cat '$CONF' > '$REG_FILE'"
}

# verify
if [ -f "$REG_ENTRY" ] && grep -q '^enabled' "$REG_ENTRY"; then
    echo "qemu-${ARCH} binfmt registered"
    grep '^interpreter' "$REG_ENTRY"
else
    echo "error: registration failed" >&2
    exit 1
fi
