# Alpenglow

Alpine Linux on Milk-V Duo S. Buildroot 5.10 kernel + Alpine aarch64 (musl) user space.

Alpenglow keeps the official Milk-V kernel, device tree and bootloader, and replaces the user space with Alpine Linux. You get `apk`, OpenRC, wpa_supplicant, Dropbear, and a small `all` control center on top of the hardware support Milk-V already ships.

## Hardware

- Milk-V Duo S (SG2000, ARM Cortex-A53)
- microSD card, 8 GB or larger
- USB-C cable for power and USB networking
- optional: USB-TTL serial adapter (CP2102 recommended) for early boot logs

## Download

Grab the latest release from the GitHub Releases page:

- `alpenglow-milkv-duos-1.1.img.xz`
- `alpenglow-milkv-duos-1.1.img.xz.sha256`

Verify:

```sh
sha256sum -c alpenglow-milkv-duos-1.1.img.xz.sha256
```

## Flash

Linux:

```sh
xz -dc alpenglow-milkv-duos-1.1.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

macOS:

```sh
xz -dc alpenglow-milkv-duos-1.1.img.xz | sudo dd of=/dev/rdiskN bs=4m
```

Windows: use Rufus or balenaEtcher, select the `.img.xz` file directly.

Replace `/dev/sdX` or `/dev/rdiskN` with your SD card device. Double-check before writing.

## First boot

1. Insert the SD card into the Duo S.
2. Connect the USB-C port to your host with a **data** cable (not a charge-only cable).
3. Power on.
4. Wait about 40 seconds. The blue LED goes from steady to a slow blink when the system is up.

The host should see a new USB network interface:

- Linux: `usb0` or `enp0s20u1`
- macOS: "USB 10/100/1000 LAN"
- Windows: "Remote NDIS Compatible Device"

Assign an address on the host:

```sh
sudo ip addr add 192.168.42.2/24 dev usb0
sudo ip link set usb0 up
```

Then:

```sh
ssh root@192.168.42.1
# password: alpenglow
```

Change the password immediately:

```sh
passwd
```

The image boots with a 768 MB rootfs and **does not auto-expand**. Expansion is a manual step (see below), so the first boot is fast and predictable. This is deliberate: online `parted` on a mounted rootfs is fragile and can stall OpenRC.

### Timezone

The image boots in UTC. To set your local timezone after the board is online:

```sh
setup-timezone
# enter Asia/Shanghai or your zone
```

`setup-timezone` temporarily installs `tzdata`, copies the zone file to `/etc/zoneinfo/`, then removes `tzdata`. **Network is required for the first run.** After that, `/etc/zoneinfo/` is self-contained and survives reboots.

You can also bake the timezone in at build time — no network needed on the board:

```sh
./build.sh --timezone Asia/Shanghai
```

## Expand the root filesystem

```sh
all growfs
```

Online resize, no reboot needed. 768 MB becomes the full SD card capacity.

`all growfs` uses `growpart` and `resize2fs` on the mounted root device. It reads the real block device, not a hardcoded `/dev/mmcblk0p3`, so it works regardless of where the image landed.

## `all` control center

`all` is a small shell front end for the things you actually do on a headless board.

```
all info        system overview
all net         interfaces, routes, DNS
all ports       listening TCP ports (exposed vs loopback)
all ssh         SSH address and fingerprint
all logs        kernel log, or service status + log tail
all hostname    show or set the hostname
all doctor      service and tool self-check (non-zero on issues)
all temp        thermal and CPU frequency
all growfs      expand rootfs to fill the SD card
all backup      back up /home and /etc

all wifi        Wi-Fi control (wpa_supplicant)
  all wifi scan
  all wifi list
  all wifi status
  all wifi connect <SSID> [password] [priority]
  all wifi select <id>
  all wifi enable <id>
  all wifi disable <id>
  all wifi forget <id>
  all wifi disconnect
  all wifi reassociate
  all wifi save

all usb         USB RNDIS gadget status
  all usb restart

all gpio        list | func | set | get | put | wiringx
```

`all` with no arguments prints a two-level usage tree. Every subcommand accepts `--help` (`all wifi` alone prints the Wi-Fi subcommand help), unknown commands print a `Did you mean:` hint and exit 1, and `all doctor` exits non-zero when it finds issues. Destructive commands (`growfs`, `usb restart`, `gpio set`/`put`) ask `Proceed? [Y/n]` on a terminal and run unattended when piped for automation.

## Networking

### USB (default)

The Duo S exposes an RNDIS gadget on `usb0` with `192.168.42.1/24`. A dnsmasq instance on the board hands out `192.168.42.2` to the host. USB is the fastest path to a shell and works without a serial console.

### Wi-Fi

`wpa_supplicant` manages `wlan0`. `wpa_cli` runs an action script on `CONNECTED` that starts `udhcpc` and syncs time with `ntpd -q`.

```sh
all wifi scan
all wifi connect "MyNetwork" "MyPassword" 10
all wifi save
```

Saved networks persist in `/etc/wpa_supplicant/wpa_supplicant.conf`. Priority is optional; higher numbers are preferred. After `connect` or `select`, all saved networks are left enabled and written to disk, so a reboot or a move to a new location re-picks automatically: the highest-priority network in range wins (without this, `select_network` disables every other saved network and a reboot would only ever try the last one). `wifi disable` is therefore undone by the next `connect` — use `forget` for networks you never want joined.

### Ethernet

`eth0` is managed by `dhcpcd` with a lower metric than Wi-Fi, so a plugged cable takes over automatically.

## GPIO

Two tools are bundled:

- `duo-pinmux` — pin mux. `duo-pinmux -p` lists pins, `-l` shows functions, `-r <pin>` reads, `-w <pin>/<func>` switches.
- `wiringX` — C API. `libwiringx.so` in `/usr/local/lib`, `wiringx.h` in `/usr/local/include`.

```c
#include <wiringx.h>
int main(void) {
    wiringXSetup("milkv_duos", NULL);
    pinMode(0, PINMODE_OUTPUT);
    digitalWrite(0, HIGH);
    wiringXGC();
    return 0;
}
```

Compile: `gcc -o test test.c -I/usr/local/include -L/usr/local/lib -lwiringx`
Run: `LD_LIBRARY_PATH=/usr/local/lib ./test`

Pin numbers are indices into `map[]` in `src/platform/milkv/duos.c` (from the milkv-duo/duo-wiringx repo), not physical pin numbers. Index 0 is XGPIOA[29], 3 is XGPIOB[20].

`digitalRead` only works on pins set to `PINMODE_INPUT`. Reading an output pin returns `-1` with an error.

## Known limitations

- **Wi-Fi via `iwd` is not supported.** The Buildroot 5.10 kernel does not enable the crypto user-space API (`CONFIG_CRYPTO_USER_API_HASH` and friends) that `iwd` requires. Alpenglow uses `wpa_supplicant`, which implements crypto in user space.
- **No zram.** The kernel lacks `CONFIG_ZRAM` and `CONFIG_CRYPTO_LZ4`.
- **Serial console is optional but recommended.** `ttyS0` at 115200 8N1 works out of the box. USB RNDIS + SSH is the primary access path.
- **No firewall by default.** Alpenglow ships without nftables or iptables rules. If you expose the board to an untrusted network, add your own.

## Upgrading packages

`apk upgrade` works for user-space packages but **does not upgrade the kernel**. The kernel and bootloader live in the boot partition and are updated only by re-flashing.

## Build from source

### Host prerequisites

- Alpine Linux, or any host with `doas` or `sudo`
- `apk-tools-static` at `tools/apk.static`
- For cross-arch chroot on x86_64: `qemu-aarch64` and `qemu-openrc`
- `mtools`, `dosfstools`, `e2fsprogs`, `xz`, `util-linux` (for `sfdisk`)

### Pre-populate `firmware/`

`build.sh` expects the following under `firmware/`, extracted from the official Milk-V image (`milkv-duos-glibc-arm64-sd_v2.0.1.img`) and built on the board:

```
firmware/
├── boot/
│   ├── fip.bin
│   └── boot.sd
├── aic8800/
│   └── (7 AIC8800 firmware files)
├── ko/
│   ├── (kernel .ko files)
│   └── 3rd/
├── bin/
│   └── duo-pinmux
└── wiringx/
    ├── lib/
    │   ├── libwiringx.so
    │   └── libwiringx.a
    └── include/
        ├── wiringx.h
        └── platform.h
```

These are tracked in git. Without `boot/`, `aic8800/`, `ko/` the image boots but has no Wi-Fi or USB gadget support. Without `bin/` and `wiringx/` the GPIO tooling is missing.

### Board profiles

Boards live in `config/boards/<name>.conf` and are selected with `--board` (default `duos`; with `--interactive` the board is the first prompt, and `--board` skips it; `--list-boards` prints them and exits). The profile is validated at build start: an unknown `--board` lists the available profiles, and a missing or invalid variable fails immediately with its name instead of a cryptic error deep in the build.

`config/boards/TEMPLATE.conf` documents every variable — copy it to add a board:

- **required** — `BOARD_NAME`, `ARCH`, partition sizes and LBAs (`BOOT_SIZE_MB`, `LOGO_SIZE_MB`, `ROOTFS_SIZE_MB`, `BOOT_LBA`, `LOGO_LBA`, `ROOTFS_LBA`); they must match the board's official partition layout
- **optional** — `SERIAL_CONSOLE` / `SERIAL_BAUD` rewrite the inittab getty line; `FW_*` points at the host-side firmware sources (`firmware/boot`, `firmware/aic8800`, `firmware/ko`, `firmware/bin`, `firmware/duos-map.txt`, `firmware/wiringx`); missing ones are skipped
- **runtime** — everything else is baked verbatim into `/etc/alpenglow/board.conf` on the device, where `alpenglow-led` reads `LED_GPIO` (and any future on-device tooling can read the rest)

### Build

```sh
doas rm -rf out
./build.sh --board duos
```

`build.sh` calls `tools/fix-binfmt.sh` automatically when cross-arch chroot is needed, so you do not have to run it separately.

#### Customizing the image

```sh
./build.sh --interactive
# or non-interactive, e.g. for scripts:
./build.sh --hostname myboard --timezone Asia/Shanghai \
    --wifi-ssid MyNetwork --wifi-pass secret123 --root-pass secret99
```

| flag | effect |
|---|---|
| `--interactive` | prompt for board, hostname, timezone, Wi-Fi, root password (requires a terminal; flags already given skip their prompt) |
| `--hostname NAME` | writes `/etc/hostname` (default `alpenglow`) |
| `--timezone ZONE` | copies zone data from the host's `/usr/share/zoneinfo/` and links `/etc/localtime` (default: UTC) |
| `--wifi-ssid SSID` | appends a `network={}` block to `/etc/wpa_supplicant/wpa_supplicant.conf` |
| `--wifi-pass PASS` | WPA passphrase, 8–63 chars; omit for an open network (requires `--wifi-ssid`) |
| `--root-pass PASS` | sha-512 hash written to `/etc/shadow`; firstboot keeps it instead of resetting to `alpenglow` (needs `openssl`) |
| `--list-boards` | list available board profiles (`NAME  description (arch)`) and exit |
| `--dry-run` | print the build plan (layout, firmware sources, customizations, host checks) and exit without touching anything; not combinable with `--interactive` |
| `--clean-old` | after a successful build, remove other versions' images from `out/` |

Without these flags the build stays fully non-interactive and uses the defaults. Prompts show their choices up front (available boards before `Board`, common timezones before `Timezone`, `Did you mean:` suggestions on a bad timezone), Enter accepts the `[default]`, and the output uses the same purple palette as `all`.

Interactive mode is guarded: host tools, boot files, and `openssl` are checked **before** any prompt; passwords are entered twice (mismatch retries); and a final `Proceed with build? [Y/n]` runs before anything destructive happens. Ctrl-C prints `Interrupted — out/ may contain partial files` instead of dying silently. Passwords can also be supplied via `ALPENGLOW_ROOT_PASS` / `ALPENGLOW_WIFI_PASS` when the flag is omitted (useful for scripts — keeps them out of `ps`). Every build ends with a `took:` line; if older images sit in `out/`, rerun with `--clean-old`.

`--rootfs` refuses dangerous paths (`/`, `.`, `$HOME`, paths with `..`, system directories) because the directory is removed before the build.

Output:

- `out/rootfs/` — the Alpine user space tree
- `out/alpenglow-milkv-duos-1.1.img` — flashable image
- `out/alpenglow-milkv-duos-1.1.img.xz` — compressed image (xz, 64 MiB block size, multi-threaded)
- `out/alpenglow-milkv-duos-1.1.img.xz.sha256`

### Cross-arch tests

```sh
./tools/test-chroot.sh --rootfs out/rootfs --mode qemu
```

Runs `tools/test-cases.sh` inside a chroot: PS1, aliases, `all` script, service files, runlevel links, config files, board profile, build customizations (timezone/Wi-Fi/root password — skipped when not configured at build time), ext4 mounts. Hardware-dependent checks are marked SKIP.

## License

Alpenglow original parts (`build.sh`, `all`, `overlay/`, `tools/`, docs) are licensed under the Apache License 2.0. See `LICENSE`.

Upstream components retain their own licenses:

- Linux kernel, U-Boot, device tree, AIC8800 firmware: from Milk-V `duo-buildroot-sdk-v2`, GPL-2.0 and vendor terms
- Alpine Linux packages: various, see each package
- `duo-pinmux`, `wiringX`: from milkv-duo, MPL-2.0

This distribution does not alter the license status of any upstream component. See `NOTICE` for attribution.

"Alpenglow" is a project name. The Apache 2.0 license does not grant trademark rights to use it for derivative distributions.
