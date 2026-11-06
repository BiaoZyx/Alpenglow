# Alpenglow TODO

> Target: Buildroot 5.10 kernel + Alpine aarch64 (musl) user space
> Platform: Milk-V Duo S (SG2000, ARM Cortex-A53)
> License: Apache 2.0 (original parts)
> Version: 1.0.0

---

## P0 · 官方脚本与内核摸底

- [x] P0-1 官方 USB gadget：`rndis.usb0`、`192.168.42.1`、dnsmasq、GPIO 453/510/449/450/451
- [x] P0-2 Buildroot 其他启动脚本：`uhubon.sh`、`run_usb.sh`、`blink.sh`、`duo-init.sh`、`usb-rndis.sh`、`usb-ncm.sh`、`usb-host.sh`
- [x] P0-3 内核配置：`CONFIG_USB_CONFIGFS=m`、`CONFIG_USB_CONFIGFS_RNDIS=y`、`CONFIG_USB_GADGET=y`、无 `CONFIG_ZRAM`/`CONFIG_CRYPTO_LZ4`
- [x] P0-4 AIC8800 固件：`/mnt/system/firmware/aic8800/` 下 7 个文件，名字全部确认
- [x] P0-5 LED/RTC：`LED_GPIO=509`（sysfs，非 `/sys/class/leds/`）、`cvitek,rtc` 存在
- [x] P0-6 `duo-pinmux`/`wiringX`：不在 SDK，推迟到 v1.1

---

## P1 · 构建底座

- [x] P1-7 仓库结构：`Alpenglow/` + `build.sh` / `config/` / `overlay/` / `firmware/` / `tools/` / `LICENSE` / `NOTICE`
- [x] P1-8 `apk.static --root --arch aarch64 --initdb add` 流程跑通（87 包，35.2 MiB）
- [ ] P1-8a `build.sh --interactive` 模式：参数已解析，提示逻辑未实现
- [x] P1-8b 非交互模式使用默认值
- [x] P1-8c `build.sh` 复制 `LICENSE` / `NOTICE` 到 `/usr/share/doc/alpenglow/`
- [x] P1-9 `world` 定稿：`alpine-base dhcpcd dnsmasq dropbear e2fsprogs-extra iwd libgpiod parted util-linux`
- [x] P1-10 分区：`duos.conf` 改为 `BOOT_SIZE_MB=128`、`ROOTFS_SIZE_MB=768`、`LOGO_SIZE_MB=2`
- [x] P1-11 `alpenglow-firstboot` 服务：扩容 + machine-id + host key + 标记 + 自我禁用
- [x] P1-11a `depend`：`need localmount`、`after root`、`before dropbear`；`/dev/root` fallback 已加
- [ ] P1-12 `build.sh` 复制固件到 `$FIRMWARE_DIR` 和 `$FIRMWARE_ALT_DIR`（`firmware/` 目录待填文件）

---

## P2 · 系统配置

- [x] P2-13 品牌：`os-release`（符号链接 `etc/os-release -> ../usr/lib/os-release`）、`hostname=alpenglow`、`motd`、紫色 banner
- [ ] P2-14 串口 `inittab`：`ttyS0` 115200，注释 `tty1`–`tty6`
- [x] P2-15 密码策略：Dropbear 默认禁空密码，`DROPBEAR_OPTS=""`（`-w` 是禁 root 登录，不加）
- [x] P2-16 网络：`iwd`（`EnableNetworkConfiguration=false`）+ `dhcpcd`（`denyinterfaces usb0`、`eth0` metric 100、`wlan0` metric 300）+ `usb0` 静态 `192.168.42.1/24`
- [x] P2-16a `eth0` 优先级高于 Wi-Fi
- [x] P2-17 `usb-gadget` 服务 + `dnsmasq.conf`（`dhcp-range=192.168.42.2,192.168.42.242,1h`、`interface=usb0`）
- [x] P2-18 `alpenglow-led` 守护脚本 + 服务（热 > USB > 在线 `.-` > 就绪慢闪）
- [x] P2-19 NTP：`/etc/local.d/ntp-sync.start` 一次性 `ntpd -q`，`hwclock` `clock="UTC"` 已确认
- [x] P2-19a locale：`alpenglow-prompt.sh` 里 `LANG=C.UTF-8`、`LC_ALL=C.UTF-8`
- [x] P2-20 GPIO：`libgpiod` 已装，`duo-pinmux` v1.1
- [ ] P2-21 zram：内核无 `CONFIG_ZRAM`，推迟到 v1.1

---

## P3 · `all` 脚本与 Shell 配置

- [x] P3-21 `all` 骨架：`info` / `wifi` / `usb` / `net` / `ssh` / `pkg` / `doctor` / `temp` / `backup` / `reboot` / `poweroff` / `version`
- [x] P3-21a `all backup [dir]`：带时间戳 `tar.gz`，失败提示不创建部分文件
- [x] P3-22 `all gpio`：`list` / `func` / `set` / `get` / `put`，缺失工具优雅降级
- [x] P3-23 `all pkg sync` / `search` / `add` / `del`，不含 `upgrade`
- [x] P3-24 `all ssh` 后端自适应：`dropbear` / `openssh` / `none`
- [x] P3-25 `all` 优雅回退：工具缺失时英文提示 + 修复命令，不崩溃不静默
- [x] P3-26 PS1 紫色 `38;5;135`、路径折叠、git 状态实时
- [x] P3-26a 退出码 `[$?]` 总显示、`set -o pipefail`
- [x] P3-26b git 状态解析、报错静默、不在仓库不显示
- [x] P3-27 ASCII 别名：`cls`/`..`/`...`/`....`、`ls --color=auto`、`grep --color=auto`、`g`/`gst`/`gp`/`gpu`/`gc`/`gd`/`gl`
- [x] P3-28 函数：`mkcd` / `extract` / `backup` / `cd` 包装
- [x] P3-29 Shell 特性：`HISTFILE`、`PS2`、`set -o emacs`
- [x] P3-30 `tools/test-chroot.sh`：`--mode qemu|native`、自动挂载、`trap EXIT` 卸载
- [x] P3-30a `tools/test-cases.sh`：40 用例
- [x] P3-30b 硬件相关项 SKIP
- [x] P3-30c 实测：`PASS=40 FAIL=0 SKIP=5`

---

## P4 · 构建前优化

- [x] P4-31 `/etc/profile` 精简：`HISTFILE`、`PS1`、`set -o pipefail`
- [ ] P4-32 BusyBox applet 裁剪：推迟到 v1.1
- [x] P4-33 locale 确认 `C.UTF-8` 生效
- [ ] P4-34 tmpfs：`/tmp` 64M、`/var/log` 16M，写 `overlay/etc/fstab`
- [ ] P4-35 挂载：rootfs `noatime`、boot `ro`
- [x] P4-36 `/etc/rc.conf` 加 `rc_parallel="YES"`
- [ ] P4-36a getty 只留 `ttyS0`（同 P2-14）
- [ ] P4-37 sysctl：`vm.swappiness=10`、`net.ipv4.ip_forward=1`，写 `overlay/etc/sysctl.d/99-alpenglow.conf`
- [x] P4-38 Dropbear：`DROPBEAR_OPTS=""` 保持原样
- [x] P4-39 banner 走 `profile.d`，`motd` 一行兜底
- [x] P4-40 镜像瘦身：`build.sh` 清 `apk cache`
- [ ] P4-41 验证：镜像体积 ≤ 250MB、启动时间、`mount | grep tmpfs`

---

## P5 · 实机验证

- [ ] P5-1 烧录 `.img.xz`，串口观察 U-Boot → 内核 → Alpine
- [ ] P5-2 banner 出现，`all version` 输出 `1.0.0`
- [ ] P5-3 启动时间记录
- [ ] P5-4 串口 root 空密码登录，触发强制 `passwd`
- [ ] P5-5 `all ssh` 显示密码登录状态与 ed25519 指纹
- [ ] P5-6 `df -h /` 扩到 SD 卡容量
- [ ] P5-7 `alpenglow-firstboot` 自我禁用、`/etc/machine-id` 生成
- [ ] P5-8 第二次启动不重复扩容
- [ ] P5-9 USB 插线主机识别网卡，拿到 `192.168.42.x`
- [ ] P5-10 主机 `ping` / `ssh root@192.168.42.1` 成功
- [ ] P5-11 `all usb` 输出正确，`all usb restart` 后恢复
- [ ] P5-12 `all wifi` 扫描并连接
- [ ] P5-13 `ip -4` / `ip -6` 拿到 v4 与全局 v6
- [ ] P5-14 插网线后默认路由走 `eth0`
- [ ] P5-15 LED 灯语：启动灭 → 就绪慢闪 → USB 未配置双闪 → 联网 `.-`
- [ ] P5-16 过热快闪（`stress-ng` 触发）
- [ ] P5-17 `all gpio list` / `get` / `put` 可用
- [ ] P5-18 `all temp` 显示真实温度
- [ ] P5-19 `all pkg sync` / `add` / `del` 正常
- [ ] P5-20 持久化：`apk add` 重启保留、`/home` / `/etc` 保留、`/tmp` 清空、`HISTFILE` 保留
- [ ] P5-21 `mount | grep tmpfs` 确认
- [ ] P5-22 断电重启正常
- [ ] P5-23 连续 3 次重启，USB / Wi-Fi / eth0 / LED 均恢复
- [ ] P5-24 `tools/test-hardware.sh` 编写与运行
- [ ] P5-25 `--headless` 模式

---

## P6 · 发布

- [ ] P6-1 打包 `.img.xz` + `.sha256`
- [ ] P6-2 `README.md`：烧录、首登、`all` 用法、已知限制、防火墙示例、`apk upgrade` 不升级内核
- [ ] P6-3 `os-release` 写 `VERSION_ID` 与 `BUILD_DATE`
- [ ] P6-4 版本号 `1.0.0` 语义化
- [ ] P6-5 附 `tools/test-chroot.sh` / `test-hardware.sh`
- [x] P6-6 `LICENSE` Apache 2.0 全文
- [x] P6-7 `NOTICE` 归功 Milk-V 与 Alpine
- [ ] P6-8 README 的 License 一节

---

## v1.1 推迟项

- [ ] `duo-pinmux` / `wiringX` 的 musl 编译
- [ ] zram（依赖内核重编 `CONFIG_ZRAM` + `CONFIG_CRYPTO_LZ4`）
- [ ] BusyBox applet 裁剪（需重编 busybox）
- [ ] `build.sh --interactive`
- [ ] board profile 抽象（多板子支持）
- [ ] `rc_parallel` 用 `sed` 替换原行，避免重复

---

## 下一步（考试后按顺序）

1. `overlay/etc/fstab` — 加 `/tmp` 64M、`/var/log` 16M 的 tmpfs
2. `overlay/etc/inittab` — 注释 `tty1`–`tty6`，启用 `ttyS0` 115200
3. `overlay/etc/sysctl.d/99-alpenglow.conf` — `vm.swappiness=10`、`net.ipv4.ip_forward=1`
4. `rc_parallel` 改成 `sed` 替换
5. 重新构建 + `test-chroot.sh` — 确认 P4 全部 PASS
6. P5 实机 — 烧录、串口、USB、Wi-Fi、LED、GPIO、扩容、firstboot

---

## 统计

| 阶段 | 完成 | 总数 |
|---|---|---|
| P0 | 6 | 6 |
| P1 | 8 | 10 |
| P2 | 8 | 10 |
| P3 | 15 | 15 |
| P4 | 7 | 12 |
| P5 | 0 | 25 |
| P6 | 2 | 8 |
| **总计** | **46** | **86** |
