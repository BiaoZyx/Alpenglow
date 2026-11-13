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
ALPENGLOW_VERSION=$(grep '^VERSION_ID=' overlay/usr/lib/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
[ -n "$ALPENGLOW_VERSION" ] || ALPENGLOW_VERSION="1.0.0"

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

# --- host build dependencies ---
REQUIRED="dd mke2fs truncate mkfs.vfat mcopy xz sha256sum chroot sfdisk"
MISSING=""
for t in $REQUIRED; do
    command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
    echo "error: missing host tools: $MISSING" >&2
    exit 1
fi

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

# --- setup qemu ---

# fix binfmt
if [ -e ./tools/fix-binfmt.sh ]; then
    doas ./tools/fix-binfmt.sh
else
    echo "error: tools/fix-binfmt.sh not found"
fi

# qemu for cross-arch chroot
if [ "$ARCH" != "$(uname -m)" ]; then
    [ -e /proc/sys/fs/binfmt_misc/qemu-${ARCH} ] || {
        echo "error: qemu-${ARCH} binfmt not registered" >&2
        echo "  doas apk add qemu-${ARCH} qemu-openrc" >&2
        echo "  doas sh -c 'cat /usr/lib/binfmt.d/qemu-${ARCH}.conf > /proc/sys/fs/binfmt_misc/register'" >&2
        exit 1
    }
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
    for d in etc usr mnt dev proc sys var run; do
        if [ -e "$ROOTFS/$d" ]; then
            $PRIV chown -R root:root "$ROOTFS/$d"
        fi
    done
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
if [ -d firmware/aic8800 ]; then
    $PRIV mkdir -p "$ROOTFS/mnt/system/firmware/aic8800"
    $PRIV cp firmware/aic8800/* "$ROOTFS/mnt/system/firmware/aic8800/"
fi

# --- kernel modules (all .ko + loadsystemko.sh) ---
if [ -d firmware/ko ]; then
    $PRIV mkdir -p "$ROOTFS/mnt/system/ko"
    $PRIV cp -a firmware/ko/. "$ROOTFS/mnt/system/ko/"
fi

# --- cleanup apk cache unless --keep-cache ---
if [ "$KEEP_CACHE" = "0" ]; then
    $PRIV rm -rf "$ROOTFS/var/cache/apk/"* 2>/dev/null || true
fi

# --- packaging ---
echo "== packaging =="

IMG="out/alpenglow-${BOARD_NAME}-${ALPENGLOW_VERSION}.img"
BOOT_IMG="out/boot.vfat"
ROOTFS_IMG="out/rootfs.ext4"

# boot partition
$PRIV dd if=/dev/zero of="$BOOT_IMG" bs=1M count="$BOOT_SIZE_MB" status=none
$PRIV mkfs.vfat -F 32 -n boot "$BOOT_IMG" >/dev/null
$PRIV env MTOOLS_SKIP_CHECK=1 mcopy -i "$BOOT_IMG" firmware/boot/fip.bin ::fip.bin
$PRIV env MTOOLS_SKIP_CHECK=1 mcopy -i "$BOOT_IMG" firmware/boot/boot.sd ::boot.sd

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

echo "image:  $IMG"
echo "xz:     $IMG.xz"
echo "size:   $(du -h "$IMG.xz" 2>/dev/null | cut -f1)"

# --- the end ---
echo "== done =="
echo "rootfs at: $ROOTFS"
