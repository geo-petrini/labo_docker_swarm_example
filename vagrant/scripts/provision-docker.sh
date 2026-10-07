#!/usr/bin/env bash
# Provisioning: installa Docker Engine (repo ufficiale) + plugin Compose.
# Eseguìto da Vagrant su entrambe le VM (manager e worker).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Aggiorno i pacchetti"
sudo apt-get update -y

echo "==> Dipendenze per il repository Docker"
sudo apt-get install -y ca-certificates curl gnupg

echo "==> Repository ufficiale Docker"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "==> Installo Docker Engine"
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Abilito Docker al boot (dovrebbe già essere abilitato)"
sudo systemctl enable docker --now

echo "==> Aggiungo l'utente 'vagrant' al gruppo docker"
sudo usermod -aG docker vagrant

echo "==> Docker installato:"
docker --version
docker compose version