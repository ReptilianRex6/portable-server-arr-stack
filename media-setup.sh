```bash
#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$USER}"
SERVER_IP="$(hostname -I | awk '{print $1}')"

HOTSPOT_IFACE="wlxbcec23c3620d"
HOTSPOT_SSID="EthanMedia"
HOTSPOT_PASSWORD="dragonballz"
HOTSPOT_IP="192.168.50.1"

echo "=== Portable Media Server Setup ==="

sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget ca-certificates gnupg ufw htop nano \
  qbittorrent-nox hostapd dnsmasq tcpdump

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

echo "Configuring offline hotspot..."
sudo systemctl unmask hostapd || true

sudo tee /etc/hostapd/hostapd.conf >/dev/null <<EOF
interface=$HOTSPOT_IFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=6
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=$HOTSPOT_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sudo tee /etc/dnsmasq.d/hotspot.conf >/dev/null <<EOF
interface=$HOTSPOT_IFACE
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,12h
dhcp-option=3,$HOTSPOT_IP
dhcp-option=6,8.8.8.8,1.1.1.1
port=0
EOF

sudo tee /etc/systemd/system/hotspot-ip.service >/dev/null <<EOF
[Unit]
Description=Assign static IP to hotspot interface
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip addr add $HOTSPOT_IP/24 dev $HOTSPOT_IFACE
ExecStart=/usr/sbin/ip link set $HOTSPOT_IFACE up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p /etc/systemd/system/hostapd.service.d
sudo tee /etc/systemd/system/hostapd.service.d/override.conf >/dev/null <<EOF
[Unit]
Requires=hotspot-ip.service
After=hotspot-ip.service
EOF

sudo mkdir -p /etc/systemd/system/dnsmasq.service.d
sudo tee /etc/systemd/system/dnsmasq.service.d/override.conf >/dev/null <<EOF
[Unit]
Requires=hotspot-ip.service
After=hotspot-ip.service
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now hotspot-ip.service
sudo systemctl enable --now hostapd
sudo systemctl restart dnsmasq

echo "Installing NordVPN..."
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
sudo usermod -aG nordvpn "$USER_NAME" || true

echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp
sudo ufw allow 8096/tcp
sudo ufw allow in on "$HOTSPOT_IFACE"
sudo ufw --force enable

echo "Whitelisting local service ports in NordVPN..."
nordvpn whitelist add port 22 || true
nordvpn whitelist add port 8080 || true
nordvpn whitelist add port 8096 || true
nordvpn set lan-discovery on || true

echo ""
echo "=== DONE ==="
echo "Home/network access:"
echo "qBittorrent: http://$SERVER_IP:8080"
echo "Jellyfin:     http://$SERVER_IP:8096"
echo ""
echo "Offline hotspot:"
echo "SSID:         $HOTSPOT_SSID"
echo "Password:     $HOTSPOT_PASSWORD"
echo "Jellyfin:     http://$HOTSPOT_IP:8096"
echo "qBittorrent:  http://$HOTSPOT_IP:8080"
echo ""
echo "Next:"
echo "1. sudo reboot"
echo "2. nordvpn login"
echo "3. nordvpn connect"
echo "4. sudo tailscale up"
echo ""
echo "qBittorrent temporary password:"
echo 'sudo journalctl -u qbittorrent-nox -n 50 | grep "temporary password"'
```
