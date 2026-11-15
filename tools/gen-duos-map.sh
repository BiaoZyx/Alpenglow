#!/bin/sh
# Author: BiaoZyx
# Email:  BiaoZyx@outlook.com
# Date:   2026-11-15 20:33:14
# Description:

# Extract map[] from duos.c to "index name phys" table
# usage: ./tools/gen-duos-map.sh /path/to/duos.c > firmware/duos-map.txt

[ -n "$1" ] && [ -f "$1" ] || { echo "usage: $0 /path/to/duos.c" >&2; exit 1; }

awk '
/static int map\[\]/ { in_map = 1; next }
in_map && /^};/     { exit }
in_map && /\/\*/ {
    # comment line: extract names between /* and */
    line = $0
    sub(/.*\/\*/, "", line)
    sub(/\*\/.*/, "", line)
    # split by tab, keep only non-empty
    n = split(line, a, "\t")
    j = 0
    for (i = 1; i <= n; i++) {
        gsub(/^ +| +$/, "", a[i])
        if (a[i] != "") { names[++j] = a[i] }
    }
    # read next non-empty line: numbers
    while ((getline > 0)) {
        gsub(/^[ \t]+|[ \t]+$/, "", $0)
        if ($0 != "") break
    }
    # split by comma and whitespace
    gsub(/,/, " ", $0)
    m = split($0, b, /[ \t]+/)
    k = 0
    for (i = 1; i <= m; i++) {
        if (b[i] != "") { vals[++k] = b[i] }
    }
    for (i = 1; i <= j && i <= k; i++) {
        printf "%d\t%s\t%s\n", idx, names[i], vals[i]
        idx++
    }
}
' "$1"
