#!/usr/bin/env bash
# Produce one screenshot-worthy screen at a time.
#   bash 06-shots.sh 1   control plane: everything green
#   bash 06-shots.sh 2   and not a single packet gets through
#   bash 06-shots.sh 3   three captures along the packet's path
#   bash 06-shots.sh 4   the one-line fix, then a working ping
#
# Frames 1-3 only make sense while the fabric is deployed WITHOUT
# forwarding-options tunnel-termination (see 05-deploy-broken.sh).
set -u

clear

h() { nsenter -t "$(docker inspect -f '{{.State.Pid}}' "clab-evpn2-$1")" -n "${@:2}"; }

case "${1:-}" in
1)
  printf 'show bgp summary\nshow mac-vrf forwarding mac-table\nshow evpn database\n' | leaf1
  ;;
2)
  echo '--- h1: пробуем достучаться до h2 через фабрику ---'
  h h1 ping -c 5 -W 2 10.10.10.2
  echo
  echo '--- таблица соседей на h1 ---'
  h h1 ip neigh show 10.10.10.2
  ;;
3)
  echo '=== 1. андерлей со стороны отправителя ==='
  h leaf1 timeout 12 tcpdump -nni eth4 -c 4 'udp port 4789 or arp' > /tmp/s1.txt 2>&1 &
  echo '=== 2. тот же линк со стороны получателя ==='
  h leaf2 timeout 12 tcpdump -nni eth4 -c 4 'udp port 4789' > /tmp/s2.txt 2>&1 &
  echo '=== 3. хост за получателем ==='
  h h2 timeout 12 tcpdump -nni eth1 -c 4 'arp or icmp' > /tmp/s3.txt 2>&1 &
  sleep 2
  h h1 ping -c 8 -i 0.5 -W 1 10.10.10.2 > /dev/null 2>&1
  wait
  echo; echo '--- 1. отправитель: пакет уходит ---';   cat /tmp/s1.txt
  echo; echo '--- 2. получатель: пакет доезжает ---';  cat /tmp/s2.txt
  echo; echo '--- 3. хост за получателем: тишина ---'; cat /tmp/s3.txt
  ;;
4)
  for n in 1 2; do
    echo "--- leaf$n ---"
    printf 'configure\nset forwarding-options tunnel-termination\ncommit\nexit\n' | "leaf$n"
  done
  echo
  echo '--- h1 -> h2 ---'
  h h1 ping -c 6 -W 2 10.10.10.2
  h h1 ip neigh show 10.10.10.2
  ;;
*)
  echo "usage: $0 {1|2|3|4}" >&2
  exit 1
  ;;
esac
