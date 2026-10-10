#!/usr/bin/env bash
# Prepare a WSL2 Ubuntu 24.04 distro for running cJunosEvolved under containerlab.
# Run as root inside the distro:  wsl -d clab -u root -e bash /mnt/.../01-wsl-setup.sh
#
# Docker Engine must be 28.0.0 or newer: Juniper's own guide warns that earlier
# versions attach interfaces out of order, which silently breaks traffic between
# connected containers.
set -euo pipefail

echo "=== 0. environment ==="
grep PRETTY /etc/os-release
echo "cpus: $(nproc)   mem: $(free -g | awk '/^Mem:/{print $2}') GB"
ls -l /dev/kvm
echo "systemd: $(ps -p 1 -o comm= || true)"

echo "=== 1. base packages ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg cpu-checker iproute2 jq tcpdump

echo "=== 2. kvm-ok ==="
kvm-ok || echo "WARNING: kvm-ok reported a problem"

echo "=== 3. docker engine from the official repo ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== 4. start docker ==="
if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  systemctl enable --now docker
else
  # no systemd in this distro - start the daemon directly
  pgrep dockerd >/dev/null || (dockerd >/var/log/dockerd.log 2>&1 &)
  sleep 5
fi

echo "=== 5. containerlab ==="
bash -c "$(curl -sL https://get.containerlab.dev)"

echo "=== 6. versions ==="
docker version --format 'docker engine: {{.Server.Version}}' || docker --version
docker compose version || true
containerlab version || true

echo
echo "Docker Engine must be >= 28.0.0 for cJunosEvolved - check the line above."
