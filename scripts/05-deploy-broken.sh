#!/usr/bin/env bash
# Deploy the two-leaf fabric WITHOUT 'forwarding-options tunnel-termination',
# i.e. in the state where the control plane is perfect and nothing forwards.
#
# This exists to reproduce the failure on demand - for screenshots, and for
# anyone who wants to see the symptom before reading the explanation.
# Apply the one-line fix afterwards to bring the fabric up.
set -u
REPO=/mnt/c/claude/vjunos-evpn-lab
LAB=/root/lab/evpn2

mkdir -p "$LAB"
sed 's/\r$//' "$REPO/topology/evpn-2leaf.clab.yml" > "$LAB/evpn-2leaf.clab.yml"
for n in 1 2; do
  # strip the whole forwarding-options stanza
  sed 's/\r$//' "$REPO/configs/leaf$n.conf" | sed '/^forwarding-options {/,/^}/d' > "$LAB/leaf$n.conf"
  if grep -q tunnel-termination "$LAB/leaf$n.conf"; then
    echo "ERROR: tunnel-termination still present in leaf$n.conf" >&2
    exit 1
  fi
done
echo "configs staged without tunnel-termination"

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
  for i in $(seq 1 90); do
    if ask "$ip" "show version" | grep -q Junos; then
      echo "--- leaf$n answered after $(( $(date +%s) - start ))s ---"
      break
    fi
    sleep 15
  done
done

# nudge both hosts so the leaves learn their MACs and the control plane fills in
for h in 1 2; do
  pid=$(docker inspect -f '{{.State.Pid}}' "clab-evpn2-h$h")
  nsenter -t "$pid" -n ping -c 2 -W 1 10.10.10.$(( 3 - h )) >/dev/null 2>&1 || true
done
sleep 20

echo
echo "=== состояние: контрол-плейн ==="
ask "$ip1" "show bgp summary" | tail -12
ask "$ip1" "show mac-vrf forwarding mac-table" | tail -6
echo
echo "=== состояние: трафик ==="
nsenter -t "$(docker inspect -f '{{.State.Pid}}' clab-evpn2-h1)" -n ping -c 3 -W 2 10.10.10.2 2>&1 | tail -3
echo
echo "READY FOR SCREENSHOTS - leaf1=$ip1 leaf2=$ip2"
