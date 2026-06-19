#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$USER}"
SERVER_IP="$(hostname -I | awk '{print $1}')"

echo "=== Portable Media Server Setup ==="

sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget ca-certificates gnupg ufw htop nano qbittorrent-nox

echo "Creating folders..."
sudo mkdir -p /srv/downloads/complete
sudo mkdir -p /srv/downloads/incomplete
sudo mkdir -p /srv/media/movies
sudo mkdir -p /srv/media/shows

echo "Creating qBittorrent user..."
sudo useradd -r -m -s /usr/sbin/nologin qbittorrent 2>/dev/null || true

echo "Setting permissions..."
sudo chown -R qbittorrent:qbittorrent /srv/downloads
sudo chmod -R 775 /srv/downloads
sudo chown -R "$USER_NAME:$USER_NAME" /srv/media
sudo chmod -R 775 /srv/media

echo "Creating qBittorrent service..."
sudo tee /etc/systemd/system/qbittorrent-nox.service >/dev/null <<'EOF'
[Unit]
Description=qBittorrent-nox
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=qbittorrent
Group=qbittorrent
ExecStart=/usr/bin/qbittorrent-nox --webui-port=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now qbittorrent-nox

echo "Installing Jellyfin..."
sudo mount -o remount,size=2500M /tmp || true
curl -fsSL https://repo.jellyfin.org/install-debuntu.sh -o /tmp/install-jellyfin.sh
sudo bash /tmp/install-jellyfin.sh
sudo systemctl enable --now jellyfin

echo "Installing NordVPN..."
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
sudo usermod -aG nordvpn "$USER_NAME" || true

echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp
sudo ufw allow 8096/tcp
sudo ufw --force enable

echo "Whitelisting local service ports in NordVPN..."
nordvpn whitelist add port 22 || true
nordvpn whitelist add port 8080 || true
nordvpn whitelist add port 8096 || true
nordvpn set lan-discovery on || true

echo ""
echo "=== DONE ==="
echo "qBittorrent: http://$SERVER_IP:8080"
echo "Jellyfin:     http://$SERVER_IP:8096"
echo ""
echo "Next:"
echo "1. sudo reboot"
echo "2. nordvpn login"
echo "3. nordvpn connect"
echo "4. sudo tailscale up"
echo ""
echo "qBittorrent temporary password:"
echo "sudo journalctl -u qbittorrent-nox -n 50"
