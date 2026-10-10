#!/usr/bin/env bash
# Boot a single cJunosEvolved node and time how long it takes until the CLI
# answers. Juniper's docs say ~5 minutes; this measures it on our host.
set -u
cd /root/lab

containerlab destroy -t smoke.clab.yml --cleanup >/dev/null 2>&1 || true

start=$(date +%s)
containerlab deploy -t smoke.clab.yml
echo "--- deploy returned after $(( $(date +%s) - start ))s ---"

node=clab-smoke-cjunos1
ok=0
for i in $(seq 1 60); do
  if docker exec "$node" cli -c 'show version' >/tmp/ver.txt 2>/dev/null; then
    echo "--- CLI answered after $(( $(date +%s) - start ))s ---"
    cat /tmp/ver.txt
    ok=1
    break
  fi
  sleep 15
done
[ "$ok" = 0 ] && { echo "--- CLI never answered within $(( $(date +%s) - start ))s ---"; docker logs --tail 40 "$node"; }

echo "--- state ---"
docker ps --format '{{.Names}} | {{.Status}}'
free -g | head -2
