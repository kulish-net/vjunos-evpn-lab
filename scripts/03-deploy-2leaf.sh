#!/usr/bin/env bash
# Deploy the two-leaf EVPN-VXLAN lab and wait for both nodes to answer.
# containerlab returns long before the nodes are usable, so the waiting is
# done here on purpose.
set -u
REPO=/mnt/c/claude/vjunos-evpn-lab
LAB=/root/lab/evpn2

mkdir -p "$LAB"
for f in "$REPO/topology/evpn-2leaf.clab.yml" "$REPO/configs/leaf1.conf" "$REPO/configs/leaf2.conf"; do
  sed 's/\r$//' "$f" > "$LAB/$(basename "$f")"
done

cd "$LAB"
containerlab destroy -t evpn-2leaf.clab.yml --cleanup >/dev/null 2>&1 || true

start=$(date +%s)
containerlab deploy -t evpn-2leaf.clab.yml
echo "--- deploy returned after $(( $(date +%s) - start ))s ---"

ask() { sshpass -p 'admin@123' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -o ConnectTimeout=10 "admin@$1" "$2" 2>/dev/null | tr -d '\r'; }

ip1=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-evpn2-leaf1)
ip2=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-evpn2-leaf2)
echo "leaf1=$ip1  leaf2=$ip2"

for n in 1 2; do
  eval ip=\$ip$n
  for i in $(seq 1 80); do
    if ask "$ip" "show version" | grep -q Junos; then
      echo "--- leaf$n answered after $(( $(date +%s) - start ))s ---"
      break
    fi
    sleep 15
  done
done

echo
echo "=== BGP ==="
ask "$ip1" "show bgp summary"
echo "=== EVPN database ==="
ask "$ip1" "show evpn database"
echo "=== VXLAN tunnel endpoints ==="
ask "$ip1" "show ethernet-switching vxlan-tunnel-end-point remote"
echo "=== hosts ==="
docker exec clab-evpn2-h1 ip -br addr show eth1.10 2>&1
docker exec clab-evpn2-h2 ip -br addr show eth1.10 2>&1
echo "=== h1 -> h2 over VXLAN ==="
docker exec clab-evpn2-h1 ping -c 5 -W 2 10.10.10.2 2>&1
echo "=== memory ==="
free -g | head -2
