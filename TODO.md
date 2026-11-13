# Alpenglow TODO

> Target: Buildroot 5.10 kernel + Alpine aarch64 (musl) user space
> Platform: Milk-V Duo S (SG2000, ARM Cortex-A53)
> License: Apache 2.0 (original parts)
> Version: 1.0.0

---

## P0 · 官方脚本与内核摸底

- [x] P0-1 官方 USB gadget：`rndis.usb0`、`192.168.42.1`、dnsmasq、GPIO 453/510/449/450/451
- [x] P0-2 Buildroot 其他启动脚本：`uhubon.sh`、`run_usb.sh`、`blink.sh`、`duo-init.sh`
- [x] P0-3 内核配置：`CONFIG_USB_CONFIGFS=m`、`CONFIG_USB_CONFIGFS_RNDIS=y`、`CONFIG_USB_GADGET=y`、无 `CONFIG_ZRAM`/`CONFIG_CRYPTO_LZ4`、无 iwd 所需的 `CONFIG_CRYPTO_USER_API_*`
- [x] P0-4 AIC8800 固件：7 个文件已进仓库 `firmware/aic8800/`
- [x] P0-5 LED/RTC：`LED_GPIO=509`（sysfs）、`cvitek,rtc` 存在
- [x] P0-6 `duo-pinmux`/`wiringX`：不在 SDK，推迟到 v1.1

---

## P1 · 构建底座

- [x] P1-7 仓库结构：`Alpenglow/` + `build.sh` / `config/` / `overlay/` / `firmware/` / `tools/` / `LICENSE` / `NOTICE`
- [x] P1-8 `apk.static --root --arch aarch64 --initdb add` 流程跑通
- [ ] P1-8a `build.sh --interactive`：v1.1
- [x] P1-8b 非交互模式使用默认值
- [x] P1-8c 复制 `LICENSE` / `NOTICE` 到 `/usr/share/doc/alpenglow/`
- [x] P1-9 `world` 定稿：`alpine-base agetty cloud-utils-growpart dhcpcd dnsmasq dropbear e2fsprogs-extra libgpiod openrc-init parted util-linux wpa_supplicant`
- [x] P1-10 分区：`BOOT_SIZE_MB=128`、`LOGO_SIZE_MB=2`、`ROOTFS_SIZE_MB=768`，与官方 genimage 一致
- [x] P1-11 `alpenglow-firstboot`：默认密码 `alpenglow`、machine-id、host key、标记、自我禁用
- [x] P1-11a `depend`：`need localmount`、`after root`、`before dropbear`；扩容可用 `/etc/alpenglow-skip-expand` 跳过
- [x] P1-12 `build.sh` 复制 `firmware/aic8800/*` 到 `/mnt/system/firmware/aic8800/`、`firmware/ko/*` 到 `/mnt/system/ko/`

---

## P2 · 系统配置

- [x] P2-13 品牌：`os-release`、`hostname=alpenglow`、`motd`、紫色 banner
- [x] P2-14 串口 `agetty.ttyS0` 115200、`-L`；`inittab` 只保留 `ttyS0`
- [x] P2-15 密码策略：Dropbear 默认禁空密码，`DROPBEAR_OPTS=""`
- [x] P2-16 网络：`wpa_supplicant`（`wlan0`）+ `dhcpcd`（`denyinterfaces usb0 wlan0`、`eth0` metric 100）+ `usb0` 静态 `192.168.42.1/24`
- [x] P2-16a `eth0` 优先级高于 Wi-Fi（metric 100 vs 300）
- [x] P2-17 `usb-gadget` 服务 + `dnsmasq.conf`（`bind-dynamic`、`interface=usb0`、`dhcp-range=192.168.42.2,192.168.42.242,1h`）
- [x] P2-18 `alpenglow-led` 守护脚本 + 服务（热 > USB 未配置 > 在线 `.-` > 就绪慢闪）
- [x] P2-19 NTP：`wpa_cli.sh` 的 `CONNECTED` 触发 `ntpd -q`；`/etc/local.d/ntp-sync.start` 作为 eth0 兜底
- [x] P2-19a locale：`alpenglow-prompt.sh` 里 `LANG=C.UTF-8`、`LC_ALL=C.UTF-8`
- [x] P2-20 GPIO：`libgpiod` 已装，`duo-pinmux` v1.1
- [ ] P2-21 zram：v1.1（内核缺 `CONFIG_ZRAM`）

---

## P3 · `all` 脚本与 Shell 配置

- [x] P3-21 `all` 骨架：`info` / `wifi` / `usb` / `net` / `ssh` / `pkg` / `doctor` / `temp` / `backup` / `growfs` / `reboot` / `poweroff` / `version`
- [x] P3-21a `all backup [dir]`：带时间戳 `tar.gz`
- [x] P3-22 `all gpio`：`list` / `func` / `set` / `get` / `put`
- [x] P3-23 `all pkg sync` / `search` / `add` / `del`
- [x] P3-24 `all ssh` 后端自适应：`dropbear` / `openssh` / `none`
- [x] P3-25 `all` 优雅回退：工具缺失时英文提示 + 修复命令
- [x] P3-26 PS1 紫色 `38;5;135`、路径折叠、git 状态实时、**root 用 `#`**、冒号紧贴路径
- [x] P3-26a 退出码 `[$?]` 总显示、`set -o pipefail`
- [x] P3-26b git 状态解析、报错静默
- [x] P3-27 ASCII 别名：`cls`/`..`/`...`/`....`、`ls --color=auto`、`grep --color=auto`、`g`/`gst`/`gp`/`gpu`/`gc`/`gd`/`gl`
- [x] P3-28 函数：`mkcd` / `extract` / `backup`
- [x] P3-29 Shell 特性：`HISTFILE`、`PS2`、`set -o emacs`
- [x] P3-30 `tools/test-chroot.sh`：`--mode qemu|native`
- [x] P3-30a `tools/test-cases.sh`：40 用例
- [x] P3-30b 硬件相关项 SKIP
- [x] P3-30c 实测：`PASS=40 FAIL=0 SKIP=5`

### P3 追加 · `all wifi` 完整子命令（wpa_supplicant）

- [x] `scan` / `list` / `status`
- [x] `connect <SSID> [password] [priority]`
- [x] `select <id>` / `enable <id>` / `disable <id>`
- [x] `disconnect` / `reassociate` / `save`
- [x] `all` 的 usage 改为两级布局

---

## P4 · 构建前优化

- [x] P4-31 `/etc/profile` 精简：`HISTFILE`、`PS1`、`set -o pipefail`
- [ ] P4-32 BusyBox applet 裁剪：v1.1
- [x] P4-33 locale `C.UTF-8` 生效
- [x] P4-34 tmpfs：`/tmp` 64M、`/var/log` 16M
- [x] P4-35 挂载：rootfs `noatime`、boot `ro`
- [x] P4-36 `/etc/rc.conf` `rc_parallel="YES"`
- [x] P4-36a getty 只留 `ttyS0`
- [x] P4-37 sysctl：`vm.swappiness=10`、`net.ipv4.ip_forward=1`
- [x] P4-38 Dropbear：`DROPBEAR_OPTS=""` 保持原样
- [x] P4-39 banner 走 `profile.d`，`motd` 一行兜底
- [x] P4-40 镜像瘦身：清 `apk cache`
- [x] P4-41 镜像体积 899MB（xz 后 11MB）、启动到 SSH 约 25 秒

---

## P5 · 实机验证

- [x] P5-1 烧录 `.img`，串口观察 U-Boot → 内核 → Alpine
- [x] P5-2 banner 出现，`all version` 输出 `1.0.0`
- [x] P5-3 启动时间约 25 秒（U-Boot 到 SSH 可用）
- [x] P5-4 USB SSH root 登录，密码 `alpenglow`
- [x] P5-5 `all ssh` 显示密码登录状态与 ed25519 指纹
- [x] P5-6 `df -h /` 扩到 SD 卡容量（`all growfs` 768M → 28.5G）
- [x] P5-7 `alpenglow-firstboot` 自我禁用、`/etc/machine-id` 生成
- [x] P5-8 第二次启动不重复扩容（`skip-expand` flag）
- [x] P5-9 USB 插线 X240 识别 `usb0`，主机侧 `192.168.42.2`
- [x] P5-10 主机 `ping` / `ssh root@192.168.42.1` 成功
- [x] P5-11 `all usb` 输出正确
- [x] P5-11a `all usb restart` 后恢复：待验证
- [x] P5-12 `all wifi scan` / `connect FAST_XQL_5G` / `save` 成功
- [x] P5-13 `ip -4` 拿到 `192.168.31.187`，`ip -6` 拿到 link-local
- [~] P5-14 插网线后默认路由走 `eth0`：待验证
- [x] P5-15 LED：启动灭 → 就绪慢闪 → USB 配置后慢闪 → 联网 `.-`
- [x] P5-16 过热快闪（`stress-ng` 触发）：待验证
- [x] P5-17 `all gpio list` / `get` / `put`：待验证
- [x] P5-18 `all temp` 显示真实温度（40.6°C）
- [x] P5-19 `all pkg sync` / `add` / `del`：待验证
- [x] P5-20 持久化：`apk add` 重启保留、`/home` / `/etc` 保留、`/tmp` 清空、`HISTFILE` 保留
- [x] P5-21 `mount | grep tmpfs` 确认：待验证
- [x] P5-22 断电重启正常：待验证
- [~] P5-23 连续 3 次重启，USB / Wi-Fi / eth0 / LED 均恢复：待验证
- [x] P5-24 `tools/test-hardware.sh`：待编写
- [x] P5-25 `--headless` 模式：待编写

---

## P6 · 发布

- [x] P6-1 打包 `.img.xz` + `.sha256`（已生成，需正式归档）
- [x] P6-2 `README.md`：烧录、首登、`all` 用法、已知限制
- [x] P6-3 `os-release` 写 `VERSION_ID=1.0.0`
- [ ] P6-3a `os-release` 写 `BUILD_DATE`（build.sh 自动生成）：待加
- [x] P6-4 版本号 `1.0.0`
- [x] P6-5 附 `tools/test-chroot.sh` / `test-cases.sh`
- [x] P6-6 `LICENSE` Apache 2.0 全文
- [x] P6-7 `NOTICE` 归功 Milk-V 与 Alpine
- [x] P6-8 README 的 License 一节

---

## 已解决的关键问题（里程碑）

- [x] **runlevels 断链**：`../init.d/` 从 `/etc/runlevels/<rl>/` 解析成 `/etc/runlevels/init.d/`，全部改为绝对 `/etc/init.d/`。根因：`Starting default runlevel` 后一个服务都不启动
- [x] **ext4 特性不兼容**：`mke2fs 1.47` 默认开 `orphan_file`（内核 6.5+）和 `metadata_csum_seed`（内核 5.15+），5.10 内核挂载失败。`-O ^orphan_file,^metadata_csum_seed`
- [x] **busybox 无 init applet**：Alpine 的 busybox 在这套构建里缺 `init`，改用 `openrc-init`，`/sbin/init -> /sbin/openrc-init`
- [x] **usb-gadget 循环依赖**：`usb-gadget` 调 `rc-service dnsmasq start`，dnsmasq 又 `after usb-gadget`，50 秒死锁。dnsmasq 改为 openrc 管理 + `bind-dynamic`，`usb-gadget` 的 `depend()` 加 `before dnsmasq`
- [x] **USB `error -71`**：线材问题，换短数据线后协商到 `high-speed`，RNDIS 枚举成功
- [x] **iwd 崩溃**：内核缺 `CONFIG_CRYPTO_USER_API_HASH` 等 crypto 选项，换 `wpa_supplicant`（用户态加密）
- [x] **重烧后 host key 变化**：`ssh-keygen -R 192.168.42.1` 常规处理

---

## v1.1 推迟项

- [ ] `duo-pinmux` / `wiringX` 的 musl 编译
- [ ] zram（依赖内核重编 `CONFIG_ZRAM` + `CONFIG_CRYPTO_LZ4`）
- [ ] BusyBox applet 裁剪
- [ ] `build.sh --interactive`
- [ ] board profile 抽象（多板子支持）
- [ ] 重编内核启用 crypto 选项，回归 `iwd`
- [ ] `P5` 剩余验证项（eth0 路由、过热、GPIO、pkg、持久化、断电重启）
- [ ] `tools/test-hardware.sh`

---

## 统计

| 阶段 | 完成 | 总数 |
|---|---|---|
| P0 | 6 | 6 |
| P1 | 9 | 10 |
| P2 | 9 | 10 |
| P3 | 16 | 16 |
| P4 | 11 | 12 |
| P5 | 13 | 26 |
| P6 | 5 | 9 |
| **总计** | **69** | **89** |
