# Alpenglow TODO

> Target: Buildroot 5.10 kernel + Alpine aarch64 (musl) user space
> Platform: Milk-V Duo S (SG2000, ARM Cortex-A53)
> License: Apache 2.0 (original parts)
> Version: 1.0.3
> Published: v1.0.0, v1.0.1, v1.0.2, v1.0.3

---

## P0 · 官方脚本与内核摸底

- [x] P0-1 官方 USB gadget：`rndis.usb0`、`192.168.42.1`、dnsmasq、GPIO 453/510/449/450/451
- [x] P0-2 Buildroot 其他启动脚本：`uhubon.sh`、`run_usb.sh`、`blink.sh`、`duo-init.sh`
- [x] P0-3 内核配置：`CONFIG_USB_CONFIGFS=m`、`CONFIG_USB_CONFIGFS_RNDIS=y`、`CONFIG_USB_GADGET=y`
- [x] P0-4 AIC8800 固件：7 个文件已进仓库 `firmware/aic8800/`
- [x] P0-5 LED/RTC：`LED_GPIO=509`（sysfs）、`cvitek,rtc` 存在
- [x] P0-6 `duo-pinmux`/`wiringX`：从 milkv-duo 源码在 Duo S 上 musl 编译，已集成

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
- [x] P1-12 `build.sh` 复制 `firmware/aic8800/*`、`firmware/ko/*`、`firmware/bin/*`、`firmware/wiringx/*`

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
- [x] P2-20 GPIO：`libgpiod` + `duo-pinmux` + `wiringX` 全部集成

---

## P3 · `all` 脚本与 Shell 配置

- [x] P3-21 `all` 骨架：`info` / `wifi` / `usb` / `net` / `ssh` / `pkg` / `doctor` / `temp` / `backup` / `growfs` / `reboot` / `poweroff` / `version`
- [x] P3-21a `all backup [dir]`：带时间戳 `tar.gz`
- [x] P3-22 `all gpio`：`list` / `func` / `set` / `get` / `put` / `wiringx`
- [x] P3-23 `all pkg sync` / `search` / `add` / `del`
- [x] P3-24 `all ssh` 后端自适应：`dropbear` / `openssh` / `none`
- [x] P3-25 `all` 优雅回退：工具缺失时英文提示 + 修复命令
- [x] P3-26 PS1 紫色 `38;5;135`、路径折叠、git 状态实时、root `#`、冒号紧贴路径
- [x] P3-26a 退出码 `[$?]` 总显示、`set -o pipefail`
- [x] P3-26b git 状态 p10k 语义：`+` staged added、`!` staged modified、`-` staged deleted、`~` unstaged、`?` untracked，`AD/MD/DM/DD` 覆盖
- [x] P3-26c SOH/STX 包裹颜色 escape，长行正常 wrap
- [x] P3-27 ASCII 别名：`cls`/`..`/`...`/`....`、`ls --color=auto`、`grep --color=auto`、`g`/`gst`/`gp`/`gpu`/`gc`/`gd`/`gl`
- [x] P3-28 函数：`mkcd` / `extract` / `backup`
- [x] P3-29 Shell 特性：`HISTFILE`、`HISTSIZE=2000`、`PS2`、`set -o emacs`
- [x] P3-30 `tools/test-chroot.sh`：`--mode qemu|native`
- [x] P3-30a `tools/test-cases.sh`：40 用例
- [x] P3-30b 硬件相关项 SKIP
- [x] P3-30c 实测：`PASS=40 FAIL=0 SKIP=5`

### `all wifi` 完整子命令（wpa_supplicant）

- [x] `scan` / `list` / `status`
- [x] `connect <SSID> [password] [priority]`
- [x] `select <id>` / `enable <id>` / `disable <id>`
- [x] `disconnect` / `reassociate` / `save`
- [x] `all` usage 两级布局
- [x] `format_table()` 动态列宽，busybox awk 兼容
- [x] `_wpa()` 静默 OK

---

## P4 · 构建前优化

- [x] P4-31 `/etc/profile` 精简：`HISTFILE`、`PS1`、`set -o pipefail`
- [ ] P4-32 BusyBox applet 裁剪：v1.1
- [x] P4-33 locale `C.UTF-8` 生效
- [x] P4-34 tmpfs：`/tmp` 64M、`/var/log` 16M
- [x] P4-35 挂载：rootfs `noatime`、boot `ro`
- [x] P4-36 `/etc/rc.conf` `rc_parallel="NO"`
- [x] P4-36a getty 只留 `ttyS0`
- [x] P4-37 sysctl：`vm.swappiness=10`、`net.ipv4.ip_forward=1`
- [x] P4-38 Dropbear：`DROPBEAR_OPTS=""` 保持原样
- [x] P4-39 banner 走 `profile.d`，`motd` 一行兜底
- [x] P4-40 镜像瘦身：清 `apk cache`
- [x] P4-41 镜像 899MB（xz 后 12–13MB）、启动到 SSH 约 25 秒

---

## P5 · 实机验证

- [x] P5-1 烧录 `.img`，串口观察 U-Boot → 内核 → Alpine
- [x] P5-2 banner 出现，`all version` 输出正确
- [x] P5-3 启动时间约 25 秒（U-Boot 到 SSH 可用）
- [x] P5-4 USB SSH root 登录，密码 `alpenglow`
- [x] P5-5 `all ssh` 显示密码登录状态与 ed25519 指纹
- [x] P5-6 `df -h /` 扩到 SD 卡容量（`all growfs` 768M → 28.5G）
- [x] P5-7 `alpenglow-firstboot` 自我禁用、`/etc/machine-id` 生成
- [x] P5-8 第二次启动不重复扩容（`skip-expand` flag）
- [x] P5-9 USB 插线 X240 识别 `usb0`，主机侧 `192.168.42.2`
- [x] P5-10 主机 `ping` / `ssh root@192.168.42.1` 成功
- [x] P5-11 `all usb` 输出正确
- [x] P5-11a `all usb restart` 后 ping 恢复，SSH 重连可用
- [x] P5-12 `all wifi scan` / `connect FAST_XQL_5G` / `save` 成功
- [x] P5-13 `ip -4` 拿到 `192.168.31.x`，`ip -6` 拿到 link-local
- [~] P5-14 插网线后默认路由走 `eth0`：无网线环境，SKIP
- [x] P5-15 LED：启动灭 → 就绪慢闪 → USB 配置后慢闪 → 联网 `.-`
- [x] P5-16 过热快闪（`HEAT_C` 阈值触发验证）
- [x] P5-17 `all gpio list` / `get` / `put` / `func` / `set` 可用
- [x] P5-18 `all temp` 显示真实温度（40–46°C）
- [x] P5-19 `all pkg sync` / `add` / `del` 正常
- [x] P5-20 持久化：`/home` 保留、`/tmp` 清空、`/etc` 保留、`HISTFILE` 保留
- [x] P5-21 `mount | grep tmpfs` 确认
- [x] P5-22 断电重启正常，Wi-Fi/NTP/USB 自动恢复
- [~] P5-23 连续 3 次重启：无网线环境，SKIP
- [x] P5-24 `tools/test-hardware.sh`：19 断言，PASS=19 FAIL=0 SKIP=0
- [x] P5-25 `--headless` 模式
- [x] P5-26 `duo-pinmux -p` / `-l` / `-r` / `-w` 实机可用
- [x] P5-27 `wiringX` C 程序编译、链接、运行，`digitalRead` 返回 0/1，`digitalWrite` HIGH/LOW

---

## P6 · 发布

- [x] P6-1 打包 `.img.xz` + `.sha256`，四个版本 `dist/` 齐全
- [x] P6-2 `README.md`：烧录、首登、`all` 用法、GPIO、已知限制、build from source
- [x] P6-3 `os-release` 写 `VERSION_ID` 与 `BUILD_DATE`
- [x] P6-4 版本号语义化：1.0.0 → 1.0.1 → 1.0.2 → 1.0.3
- [x] P6-5 附 `tools/test-chroot.sh` / `test-cases.sh` / `test-hardware.sh`
- [x] P6-6 `LICENSE` Apache 2.0 全文
- [x] P6-7 `NOTICE` 归功 Milk-V、Alpine、milkv-duo
- [x] P6-8 README 的 License 一节

---

## 已解决的关键问题（里程碑）

- [x] **runlevels 断链**：`../init.d/` 从 `/etc/runlevels/<rl>/` 解析成 `/etc/runlevels/init.d/`，全部改为绝对 `/etc/init.d/`
- [x] **ext4 特性不兼容**：`mke2fs 1.47` 默认开 `orphan_file`（内核 6.5+）和 `metadata_csum_seed`（内核 5.15+），5.10 内核挂载失败。`-O ^orphan_file,^metadata_csum_seed`
- [x] **busybox 无 init applet**：Alpine 的 busybox 在这套构建里缺 `init`，改用 `openrc-init`
- [x] **usb-gadget 循环依赖**：dnsmasq 改 openrc 管理 + `bind-dynamic`，`usb-gadget` 的 `depend()` 加 `before dnsmasq`
- [x] **USB `error -71`**：线材问题，换短数据线后协商到 `high-speed`
- [x] **iwd 崩溃**：内核缺 `CONFIG_CRYPTO_USER_API_HASH`，换 `wpa_supplicant`
- [x] **重烧后 host key 变化**：`ssh-keygen -R 192.168.42.1` 常规处理
- [x] **长行断屏**：PS1 的 ESC 序列用 SOH/STX 包裹，终端视为零宽度
- [x] **wiringX segfault**：`wiringx.c` 初始化调用未编译的 `rock4Init()`/`rock5bInit()`，删除后只保留 sophgo/milkv
- [x] **wiringX `i2c_smbus_*` 未定义**：`INLINE` 宏从 `static inline` 改为空，函数成为普通外部函数
- [x] **wiringX `uintptr_t` / `void *` 类型**：`mmap` 返回值转 `uintptr_t`，`gpio[i]` 保持 `void *`，`NULL` 比较改 `0`
- [x] **wiringX `== NULL` 运算符优先级**：`if((x = f() == NULL))` 改 `if((x = f()) == NULL)`

---

## v1.1 推迟项

- [ ] BusyBox applet 裁剪（需重编 busybox）
- [ ] `build.sh --interactive`（hostname / timezone / Wi-Fi / 交互）
- [ ] board profile 抽象（多板子支持）
- [ ] P5-14 eth0 路由验证（需网线环境）
- [ ] P5-23 连续 3 次重启（需网线环境）
- [ ] `all gpio wiringx` 输出完整 `map[]` 索引表（从 `duos.c` 提取到 `/usr/local/share/alpenglow/`）
- [ ] `tools/test-hardware.sh` 加 GPIO 自动化测试（`duo-pinmux -p`、`wiringXSetup`）

---

## 明确不做

- ~~zram~~：内核缺 `CONFIG_ZRAM`，且 304MB 内存下收益有限
- ~~回归 iwd~~：`wpa_supplicant` 已完全替代，不为 iwd 重编内核
- ~~CHANGELOG.md~~：git log + Release notes 已覆盖
- ~~社区分享~~：不主动推广

---

## 统计

| 阶段 | 完成 | 总数 |
|---|---|---|
| P0 | 6 | 6 |
| P1 | 9 | 10 |
| P2 | 9 | 9 |
| P3 | 19 | 19 |
| P4 | 11 | 12 |
| P5 | 25 | 27 |
| P6 | 8 | 8 |
| **总计** | **87** | **91** |

**v1.0 系列完成度：95.6%**（P1-8a `--interactive` 和 P4-32 BusyBox 裁剪是唯一未完成的非 SKIP 项，都推迟到 v1.1）
