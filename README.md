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

- `alpenglow-milkv-duos-1.0.0.img.xz`
- `alpenglow-milkv-duos-1.0.0.img.xz.sha256`

Verify:

```sh
sha256sum -c alpenglow-milkv-duos-1.0.0.img.xz.sha256
```

## Flash

Linux:

```sh
xz -dc alpenglow-milkv-duos-1.0.0.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

macOS:

```sh
xz -dc alpenglow-milkv-duos-1.0.0.img.xz | sudo dd of=/dev/rdiskN bs=4m
```

Windows: use Rufus or balenaEtcher, select the `.img.xz` file directly.

Replace `/dev/sdX` or `/dev/rdiskN` with your SD card device. Double-check before writing.

## First boot

1. Insert the SD card into the Duo S.
2. Connect the USB-C port to your host with a **data** cable (not a charge-only cable).
3. Power on.
4. Wait about 30 seconds. The blue LED goes from steady to a slow blink when the system is up.

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

## Expand the root filesystem

The image ships with a 768 MB rootfs. Expand it to fill the SD card:

```sh
all growfs
```

Online resize, no reboot needed. 768 MB becomes the full card capacity.

## `all` control center

`all` is a small shell front end for the things you actually do on a headless board.

```
all info        system overview
all net         interfaces, routes, DNS
all ssh         SSH address and fingerprint
all doctor      service and tool self-check
all temp        thermal and CPU frequency
all growfs      expand rootfs to fill the SD card
all backup      back up /home and /etc
all reboot
all poweroff
all version

all wifi        Wi-Fi control (wpa_supplicant)
  all wifi scan
  all wifi list
  all wifi status
  all wifi connect <SSID> [password] [priority]
  all wifi select <id>
  all wifi enable <id>
  all wifi disable <id>
  all wifi disconnect
  all wifi reassociate
  all wifi save

all usb         USB RNDIS gadget status
  all usb restart

all pkg         sync | search | add | del
all gpio        list | func | set | get | put
```

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

Saved networks persist in `/etc/wpa_supplicant/wpa_supplicant.conf`. Priority is optional; higher numbers are preferred.

### Ethernet

`eth0` is managed by `dhcpcd` with a lower metric than Wi-Fi, so a plugged cable takes over automatically.

## Known limitations

- **Wi-Fi via `iwd` is not supported.** The Buildroot 5.10 kernel does not enable the crypto user-space API (`CONFIG_CRYPTO_USER_API_HASH` and friends) that `iwd` requires. Alpenglow uses `wpa_supplicant`, which implements crypto in user space.
- **No zram.** The kernel lacks `CONFIG_ZRAM` and `CONFIG_CRYPTO_LZ4`.
- **`duo-pinmux` and `wiringX` are not packaged.** Use `libgpiod` (`gpiodetect`, `gpioinfo`, `gpioset`) for GPIO.
- **Serial console is optional but recommended.** `ttyS0` at 115200 8N1 works out of the box. USB RNDIS + SSH is the primary access path.
- **No firewall by default.** Alpenglow ships without nftables or iptables rules. If you expose the board to an untrusted network, add your own.

## Upgrading packages

`apk upgrade` works for user-space packages but **does not upgrade the kernel**. The kernel and bootloader live in the boot partition and are updated only by re-flashing.

## Build from source

Prerequisites on the build host:

- Alpine Linux or any glibc/musl host with `doas` or `sudo`
- `apk-tools-static` in `tools/apk.static`
- `qemu-aarch64` binfmt for cross-arch chroot (`tools/fix-binfmt.sh`)

```sh
./tools/fix-binfmt.sh
doas rm -rf out
./build.sh --board duos
```

Output:

- `out/rootfs/` — the Alpine user space tree
- `out/alpenglow-milkv-duos-1.0.0.img` — flashable image
- `out/alpenglow-milkv-duos-1.0.0.img.xz` — compressed image
- `out/alpenglow-milkv-duos-1.0.0.img.xz.sha256`

Cross-arch tests:

```sh
./tools/test-chroot.sh --rootfs out/rootfs --mode qemu
```

## License

Alpenglow original parts (`build.sh`, `all`, `overlay/`, `tools/`, docs) are licensed under the Apache License 2.0. See `LICENSE`.

Upstream components retain their own licenses:

- Linux kernel, U-Boot, device tree, AIC8800 firmware: from Milk-V `duo-buildroot-sdk-v2`, GPL-2.0 and vendor terms
- Alpine Linux packages: various, see each package

This distribution does not alter the license status of any upstream component. See `NOTICE` for attribution.

"Alpenglow" is a project name. The Apache 2.0 license does not grant trademark rights to use it for derivative distributions.
