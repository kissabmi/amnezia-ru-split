#!/bin/bash
# Sandbox test for amnezia-ru-split. Runs in a throw-away user+net+mount namespace
# (dummy interfaces, its own iptables, tmpfs over /etc): nothing on the host is touched.
#   tests/sandbox.sh [path/to/amnezia-ru-split]
set -u
if [ -z "${IN_NS:-}" ]; then
  IN_NS=1 exec unshare --user --map-root-user --net --mount "$0" "$@"
fi

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${1:-$HERE/../amnezia-ru-split}
WORK=$(mktemp -d)
STATE=$WORK/state
ENDPOINT=9.9.9.9   # any public address; only used for a host route inside the namespace
FAILS=0

# Test prefix list: the example routes plus two /32 (ip prints /32 routes without the mask)
python3 - "$HERE/../examples/routes.example.json" "$WORK/routes.json" <<'EOF'
import json, sys
routes = json.load(open(sys.argv[1]))
routes += [{"hostname": "52.57.8.173/32", "ip": ""}, {"hostname": "3.69.86.174/32", "ip": ""}]
json.dump(routes, open(sys.argv[2], "w"))
EOF
PREFIXES=$(python3 -c "import json;print(len(json.load(open('$WORK/routes.json'))))")

mount -t tmpfs tmpfs /etc && mkdir /etc/amnezia-ru-split || exit 2
echo "$ENDPOINT" > /etc/amnezia-ru-split/vpn-endpoints

ip link set lo up
ip link add eth0 type dummy; ip addr add 10.99.0.2/24 dev eth0; ip link set eth0 up
ip route add default via 10.99.0.1 dev eth0 metric 600
ip link add amn0 type dummy; ip addr add 10.8.1.2/32 dev amn0; ip link set amn0 up
ip route add 0.0.0.0/1 dev amn0 metric 1; ip route add 128.0.0.0/1 dev amn0 metric 1

run() { python3 "$SCRIPT" "$1" --routes "$WORK/routes.json" --state "$STATE" >"$WORK/out" 2>&1; }
n186() { ip -4 route show proto 186 | wc -l; }
endpoint_route() { ip -4 route show "$ENDPOINT/32"; }
rules() { iptables -w 3 -S amnvpn.110.allowNets | grep -c ryoku-ru-split; }
events() { # route change events while running a sync
  ip -4 monitor route >"$WORK/ev" & local mp=$!; sleep 0.4
  run sync; sleep 0.4; kill "$mp" 2>/dev/null; wait "$mp" 2>/dev/null
  grep -c . "$WORK/ev"
}
check() { # check "description" "actual" "expected"
  if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (got '$2', want '$3')"; FAILS=$((FAILS + 1)); fi
}

echo "== VPN off (no Amnezia firewall chain)"
run sync; check "sync succeeds without the firewall chain" "$?" 0
check "direct routes + server route installed" "$(n186)" "$((PREFIXES + 1))"
check "server route goes through the physical gateway" "$(endpoint_route | grep -c 'via 10.99.0.1 dev eth0')" 1
check "second sync changes nothing" "$(events)" 0

echo "== VPN on (chain present)"
iptables -w 3 -N amnvpn.110.allowNets
run sync; check "sync succeeds with the chain" "$?" 0
check "firewall rules (tcp+udp per prefix, none for the server)" "$(rules)" "$((PREFIXES * 2))"
check "second sync changes nothing" "$(events)" 0

echo "== gateway changes"
ip route replace default via 10.99.0.9 dev eth0 metric 600
run sync
check "server route follows the new gateway" "$(endpoint_route | grep -c 'via 10.99.0.9')" 1
check "direct routes follow the new gateway" "$(ip -4 route show 77.88.0.0/18 | grep -c 'via 10.99.0.9')" 1

echo "== no physical default route"
ip route del default
run sync; check "sync does not fail" "$?" 0
check "server route is kept" "$(endpoint_route | grep -c 'via 10.99.0.9')" 1
ip route add default via 10.99.0.9 dev eth0 metric 600

echo "== hand-made route to the server is adopted"
ip route del "$ENDPOINT/32"; ip route add "$ENDPOINT/32" via 10.99.0.9 dev eth0
run sync; check "route is now tagged proto 186" "$(ip -4 route show "$ENDPOINT/32" proto 186 | wc -l)" 1

echo "== clear"
run clear; check "clear succeeds" "$?" 0
check "nothing of ours is left" "$(n186)" 0

rm -rf "$WORK"
[ "$FAILS" = 0 ] && { echo "ALL PASSED"; exit 0; }
echo "$FAILS FAILED"; exit 1
