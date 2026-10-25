#!/bin/sh
# Alpenglow chroot test cases — skeleton
PASS=0; FAIL=0; SKIP=0
pass() { printf "  [PASS] %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  [FAIL] %s: %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf "  [SKIP] %s: %s\n" "$1" "$2"; SKIP=$((SKIP+1)); }

echo "== shell config =="
case "$PS1" in
    *'38;5;135'*) pass "PS1 color" ;;
    *)            fail "PS1 color" "missing 38;5;135" ;;
esac

case "$LANG" in
    C.UTF-8) pass "LANG" ;;
    *)       fail "LANG" "expected C.UTF-8, got: $LANG" ;;
esac

sh -c 'set -o pipefail; false | true' 2>/dev/null
[ $? -eq 1 ] && pass "pipefail" || fail "pipefail" "false|true should be 1"

echo "== aliases =="
alias ..  >/dev/null 2>&1 && pass "alias .."  || fail "alias .."  "not defined"
alias gst >/dev/null 2>&1 && pass "alias gst" || fail "alias gst" "not defined"

echo "== functions =="
command -v mkcd >/dev/null && pass "mkcd" || fail "mkcd" "not defined"

echo "== hardware (skipped in chroot) =="
skip "thermal"  "chroot /sys is host"
skip "led"      "chroot /sys is host"
skip "usb0"     "chroot has no gadget"
skip "iwd"      "chroot has no wireless"

echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
