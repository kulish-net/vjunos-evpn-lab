#!/usr/bin/env bash
# First numbers from the two-leaf lab:
#   A. baseline - loss and jitter on an undisturbed fabric
#   B. restoration - how long after the underlay link comes back does traffic
#      actually resume (BGP re-establish + EVPN re-advertise + VTEP reprogram)
#
# A node-failure measurement needs a redundant path, which this two-node
# topology does not have. That is the next topology, not this one.
set -u
PROBE=/root/lab/udp_probe.py
L1=172.20.20.4
PPS=1000

ns() { nsenter -t "$(docker inspect -f '{{.State.Pid}}' "clab-evpn2-$1")" -n "${@:2}"; }
jcmd() { sshpass -p 'admin@123' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o LogLevel=ERROR "admin@$1" 2>/dev/null | tr -d '\r'; }

echo "=== A. baseline, ${PPS} pps, 10s ==="
ns h2 python3 "$PROBE" recv --bind 10.10.10.2 --pps $PPS --secs 13 > /tmp/base.json &
sleep 1
ns h1 python3 "$PROBE" send --dst 10.10.10.2 --pps $PPS --secs 10
wait
cat /tmp/base.json

echo
echo "=== B. underlay link down 15s, then back ==="
ns h2 python3 "$PROBE" recv --bind 10.10.10.2 --pps $PPS --secs 70 > /tmp/restore.json &
sleep 1
T0=$(date +%s.%N)
ns h1 python3 "$PROBE" send --dst 10.10.10.2 --pps $PPS --secs 65 &
SENDER=$!

sleep 8
printf 'configure\ndeactivate interfaces et-0/0/0\ncommit\nexit\n' | jcmd $L1 >/dev/null
TDOWN=$(echo "$(date +%s.%N) - $T0" | bc)
echo "-- link down, commit returned at ${TDOWN}s into the stream --"

sleep 15
printf 'configure\nactivate interfaces et-0/0/0\ncommit\nexit\n' | jcmd $L1 >/dev/null
TUP=$(echo "$(date +%s.%N) - $T0" | bc)
echo "-- link restored, commit returned at ${TUP}s into the stream --"

wait $SENDER
wait
echo
cat /tmp/restore.json
echo
echo "last_seq/${PPS} and first_seq/${PPS} give seconds since stream start;"
echo "compare the first packet after the gap with the restore timestamp above."
