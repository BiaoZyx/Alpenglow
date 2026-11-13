#!/bin/sh
IFNAME="$1"
CMD="$2"

case "$CMD" in
    CONNECTED)
        if [ -f /var/run/udhcpc.$IFNAME.pid ] && kill -0 "$(cat /var/run/udhcpc.$IFNAME.pid)" 2>/dev/null; then
            :
        else
            udhcpc -i "$IFNAME" -q -n -b -p /var/run/udhcpc.$IFNAME.pid >/dev/null 2>&1 &
        fi
        ;;
    DISCONNECTED)
        [ -f /var/run/udhcpc.$IFNAME.pid ] && kill "$(cat /var/run/udhcpc.$IFNAME.pid)" 2>/dev/null
        ;;
esac
