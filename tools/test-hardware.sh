#!/bin/sh
# Alpenglow hardware/runtime test — run ON the Duo S
# usage: sh tools/test-hardware.sh [--headless]

PASS=0; FAIL=0; SKIP=0; HEADLESS=0
[ "$1" = "--headless" ] && HEADLESS=1

pass() { printf "  [PASS] %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  [FAIL] %s: %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf "  [SKIP] %s: %s\n" "$1" "$2"; SKIP=$((SKIP+1)); }

echo "== system =="
[ "$(hostname)" = "alpenglow" ] && pass "hostname" || fail "hostname" "$(hostname)"
grep -q '^ID=alpenglow' /etc/os-release 2>/dev/null && pass "os-release" || fail "os-release" "not alpenglow"
[ -f /var/lib/alpenglow/.firstboot-done ] && pass "firstboot done" || fail "firstboot done" "marker missing"

echo "== services =="
for svc in dhcpcd wpa_supplicant dnsmasq usb-gadget alpenglow-led; do
    rc-service "$svc" status >/dev/null 2>&1 \
        && pass "svc: $svc" || fail "svc: $svc" "$(rc-service "$svc" status 2>&1 | head -1)"
done

echo "== network =="
ip addr show usb0 2>/dev/null | grep -q '192.168.42.1' \
    && pass "usb0 192.168.42.1" || fail "usb0" "no address"
ip route 2>/dev/null | grep -q '^default' \
    && pass "default route" || fail "default route" "none"
ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 \
    && pass "outbound ping" || skip "outbound ping" "no upstream or blocked"
all wifi status 2>/dev/null | grep -q 'wpa_state=COMPLETED' \
    && pass "wifi connected" || skip "wifi connected" "not connected"

echo "== storage =="
root_size=$(df -k / | awk 'NR==2{print $2}')
[ "$root_size" -gt 1000000 ] && pass "rootfs expanded ($((root_size/1024))M)" \
    || fail "rootfs expanded" "only $((root_size/1024))M, run 'all growfs'"
mount | grep -q ' /tmp type tmpfs' && pass "/tmp tmpfs" || fail "/tmp tmpfs" "not mounted"
mount | grep -q ' /var/log type tmpfs' && pass "/var/log tmpfs" || fail "/var/log tmpfs" "not mounted"

echo "== hardware =="
gpiodetect >/dev/null 2>&1 && pass "gpiodetect" || fail "gpiodetect" "not found"
temp=$(awk '{printf "%d", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
[ -n "$temp" ] && [ "$temp" -gt 0 ] && [ "$temp" -lt 120 ] \
    && pass "thermal ${temp}C" || fail "thermal" "unreadable"
ls /mnt/system/firmware/aic8800/*.bin >/dev/null 2>&1 \
    && pass "AIC8800 firmware" || fail "AIC8800 firmware" "missing"

echo "== time =="
year=$(date +%Y)
[ "$year" -ge 2025 ] && pass "clock ($(date))" || fail "clock" "year $year, NTP not synced"

if [ "$HEADLESS" -eq 0 ]; then
    echo
    printf "observe: blue LED should blink '.-' when online, slow blink when offline\n"
    printf "observe: USB host should see RNDIS, ping 192.168.42.1\n"
fi

echo
printf "PASS=%d FAIL=%d SKIP=%d\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
