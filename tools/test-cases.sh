#!/bin/sh
# Alpenglow in-chroot test cases

PASS=0; FAIL=0; SKIP=0
pass() { printf "  [PASS] %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  [FAIL] %s: %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
skip() { printf "  [SKIP] %s: %s\n" "$1" "$2"; SKIP=$((SKIP + 1)); }

# 关键：非交互 shell 里 PS1 为空，alpenglow-prompt.sh 会提前 return。
# 显式设置 PS1 后再 source，让 alias/LANG/函数全部生效。
PS1='test$ '
export PS1
[ -f /etc/profile.d/alpenglow-prompt.sh ] && . /etc/profile.d/alpenglow-prompt.sh 2>/dev/null || true

echo "== shell config =="

# PS1 是否由 alpenglow-prompt.sh 设置
case "$PS1" in
    *'__ag_prompt'*) pass "PS1 loaded" ;;
    *)               fail "PS1 loaded" "got: $PS1" ;;
esac

# 紫色色号：__AG_P 应为 38;5;135
case "$__AG_P" in
    *'38;5;135'*) pass "purple color 135" ;;
    *)            fail "purple color 135" "got: $(printf '%s' "${__AG_P:-unset}" | cat -v)" ;;
esac

case "$LANG" in
    C.UTF-8) pass "LANG" ;;
    *)       fail "LANG" "expected C.UTF-8, got: $LANG" ;;
esac

sh -c 'set -o pipefail; false | true' 2>/dev/null
[ $? -eq 1 ] && pass "pipefail" || fail "pipefail" "false|true should be 1"

case "$HISTFILE" in
    *.ash_history) pass "HISTFILE" ;;
    *)             fail "HISTFILE" "got: ${HISTFILE:-unset}" ;;
esac

echo "== aliases =="
alias ..  >/dev/null 2>&1 && pass "alias .."  || fail "alias .."  "not defined"
alias gst >/dev/null 2>&1 && pass "alias gst" || fail "alias gst" "not defined"
alias ls  >/dev/null 2>&1 && pass "alias ls"  || fail "alias ls"  "not defined"

echo "== functions =="
command -v mkcd    >/dev/null && pass "mkcd"    || fail "mkcd"    "not defined"
command -v extract >/dev/null && pass "extract" || fail "extract" "not defined"
command -v backup  >/dev/null && pass "backup"  || fail "backup"  "not defined"

echo "== os-release =="
grep -q '^NAME="Alpenglow"' /etc/os-release 2>/dev/null \
    && pass "os-release NAME" || fail "os-release NAME" "not Alpenglow"
grep -q '^ID=alpenglow' /etc/os-release 2>/dev/null \
    && pass "os-release ID" || fail "os-release ID" "not alpenglow"

echo "== hostname =="
[ "$(cat /etc/hostname 2>/dev/null)" = "alpenglow" ] \
    && pass "hostname file" || fail "hostname file" "got: $(cat /etc/hostname 2>/dev/null)"
skip "hostname (runtime)" "chroot inherits host kernel hostname"

echo "== binaries =="
for cmd in busybox apk dropbear dhcpcd iwctl dnsmasq parted resize2fs; do
    command -v "$cmd" >/dev/null 2>&1 \
        && pass "bin: $cmd" || fail "bin: $cmd" "not found"
done

echo "== all script =="
[ -x /usr/local/bin/all ] && pass "all executable" || fail "all executable" "missing"
/usr/local/bin/all version 2>/dev/null | grep -q '^Alpenglow 1.0.0' \
    && pass "all version" || fail "all version" "unexpected output"
/usr/local/bin/all info 2>/dev/null | grep -q 'kernel' \
    && pass "all info" || fail "all info" "no kernel field"

echo "== services =="
for svc in usb-gadget alpenglow-led alpenglow-firstboot dhcpcd iwd; do
    [ -x "/etc/init.d/$svc" ] \
        && pass "service: $svc" || fail "service: $svc" "missing"
done

echo "== runlevel =="
for svc in usb-gadget alpenglow-led alpenglow-firstboot dhcpcd iwd; do
    [ -L "/etc/runlevels/default/$svc" ] \
        && pass "runlevel: $svc" || fail "runlevel: $svc" "not linked"
done

echo "== configs =="
for f in /etc/dhcpcd.conf /etc/iwd/main.conf /etc/dnsmasq.conf; do
    [ -e "$f" ] && pass "config: $f" || fail "config: $f" "missing"
done

grep -q 'denyinterfaces usb0' /etc/dhcpcd.conf 2>/dev/null \
    && pass "dhcpcd denies usb0" || fail "dhcpcd denies usb0" "not set"
grep -q 'EnableNetworkConfiguration=false' /etc/iwd/main.conf 2>/dev/null \
    && pass "iwd no IP config" || fail "iwd no IP config" "not set"
grep -q 'dhcp-range=192.168.42.2,192.168.42.242' /etc/dnsmasq.conf 2>/dev/null \
    && pass "dnsmasq range" || fail "dnsmasq range" "unexpected range"

echo "== P4 configs =="
grep -q 'tmpfs.*\/tmp.*size=64M' /etc/fstab 2>/dev/null \
    && pass "fstab /tmp 64M" || fail "fstab /tmp 64M" "missing"
grep -q 'tmpfs.*\/var\/log.*size=16M' /etc/fstab 2>/dev/null \
    && pass "fstab /var/log 16M" || fail "fstab /var/log 16M" "missing"
grep -q '^ttyS0::respawn' /etc/inittab 2>/dev/null \
    && pass "inittab ttyS0" || fail "inittab ttyS0" "missing"
grep -q '^tty1::' /etc/inittab 2>/dev/null \
    && fail "inittab tty1 removed" "still present" || pass "inittab tty1 removed"
grep -q '^vm.swappiness = 10' /etc/sysctl.d/99-alpenglow.conf 2>/dev/null \
    && pass "sysctl swappiness" || fail "sysctl swappiness" "missing"
grep -q '^rc_parallel="YES"' /etc/rc.conf 2>/dev/null \
    && pass "rc_parallel YES" || fail "rc_parallel YES" "missing"

echo "== hardware (skipped in chroot) =="
skip "thermal" "chroot /sys is host"
skip "led"     "requires real GPIO 509"
skip "usb0"    "requires real configfs + UDC"
skip "iwd"     "requires real wireless hardware"

echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
