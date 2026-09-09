#!/usr/bin/env bash
# Ubuntu/systemd host setup. See README.md before running.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

if [[ ${1:-} == --help ]]; then
    echo 'Usage: sudo bash media-setup.sh [--check]'
    echo 'Reads setup.conf beside the script. --check validates settings without changes.'
    exit 0
fi
[[ $# -eq 0 || ( $# -eq 1 && $1 == --check ) ]] || die 'Unknown argument; use --help.'

# Plain KEY=value parsing: config is data, never sourced as shell code.
MEDIA_USER="${SUDO_USER:-${USER:-}}"
ENABLE_HOTSPOT=false
INSTALL_JELLYFIN=true
INSTALL_NORDVPN=false
INSTALL_TAILSCALE=false
START_CONTAINERS=true
HOTSPOT_IFACE=
HOTSPOT_SSID=PortableMedia
HOTSPOT_PASSWORD=
HOTSPOT_IP=192.168.50.1
HOTSPOT_DHCP_START=192.168.50.10
HOTSPOT_DHCP_END=192.168.50.100
if [[ -f "$SCRIPT_DIR/setup.conf" ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
        line="${line%$'\r'}"
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || die 'setup.conf must contain KEY=value lines.'
        key=${line%%=*}; value=${line#*=}
        case "$key" in
            MEDIA_USER|ENABLE_HOTSPOT|INSTALL_JELLYFIN|INSTALL_NORDVPN|INSTALL_TAILSCALE|START_CONTAINERS|HOTSPOT_IFACE|HOTSPOT_SSID|HOTSPOT_PASSWORD|HOTSPOT_IP|HOTSPOT_DHCP_START|HOTSPOT_DHCP_END)
                printf -v "$key" '%s' "$value" ;;
            *) die "Unknown setup.conf key: $key" ;;
        esac
    done < "$SCRIPT_DIR/setup.conf"
fi
for key in ENABLE_HOTSPOT INSTALL_JELLYFIN INSTALL_NORDVPN INSTALL_TAILSCALE START_CONTAINERS; do
    [[ ${!key} == true || ${!key} == false ]] || die "$key must be true or false."
done
[[ $MEDIA_USER =~ ^[a-z_][a-z0-9_-]*[$]?$ && $MEDIA_USER != root ]] || die 'Set MEDIA_USER to an existing non-root Linux user.'
id "$MEDIA_USER" >/dev/null 2>&1 || die "User does not exist: $MEDIA_USER"
MEDIA_UID=$(id -u "$MEDIA_USER")
MEDIA_GID=$(id -g "$MEDIA_USER")
MEDIA_GROUP=$(id -gn "$MEDIA_USER")
[[ $MEDIA_UID -ne 0 ]] || die 'The media user must not have UID 0.'

if [[ $ENABLE_HOTSPOT == true ]]; then
    [[ $HOTSPOT_IFACE =~ ^[a-zA-Z0-9_-]{1,15}$ ]] || die 'Set HOTSPOT_IFACE to your dedicated Wi-Fi adapter.'
    ip link show dev "$HOTSPOT_IFACE" >/dev/null 2>&1 || die 'Hotspot interface does not exist.'
    [[ ${#HOTSPOT_SSID} -ge 1 && ${#HOTSPOT_SSID} -le 32 ]] || die 'SSID must be 1–32 characters.'
    [[ $HOTSPOT_PASSWORD =~ ^[[:print:]]{8,63}$ ]] || die 'Set a printable 8–63 character hotspot password.'
    # This helper deliberately supports only a /24 hotspot subnet.
    for key in HOTSPOT_IP HOTSPOT_DHCP_START HOTSPOT_DHCP_END; do
        [[ ${!key} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "$key must be IPv4."
        IFS=. read -r -a octets <<< "${!key}"
        for octet in "${octets[@]}"; do
            [[ $octet == 0 || $octet != 0* ]] || die 'Do not use leading zeros in IP addresses.'
            (( 10#$octet <= 255 )) || die 'Invalid IP octet.'
        done
        (( 10#${octets[3]} >= 1 && 10#${octets[3]} <= 254 )) || die 'Use host addresses .1 through .254.'
    done
    [[ ${HOTSPOT_IP%.*} == "${HOTSPOT_DHCP_START%.*}" && ${HOTSPOT_IP%.*} == "${HOTSPOT_DHCP_END%.*}" ]] || die 'Hotspot addresses must share one /24 subnet.'
    start=${HOTSPOT_DHCP_START##*.}; end=${HOTSPOT_DHCP_END##*.}; gateway=${HOTSPOT_IP##*.}
    (( start <= end && (gateway < start || gateway > end) )) || die 'Invalid DHCP range or overlap with hotspot IP.'
fi

[[ -f /etc/os-release ]] || die 'This installer requires Ubuntu.'
. /etc/os-release
[[ $ID == ubuntu ]] || die 'This installer targets Ubuntu; see README.'
[[ -d /run/systemd/system ]] || die 'Run on an Ubuntu system booted with systemd.'
command -v docker >/dev/null || die 'Install Docker Engine and the Compose plugin first; see README.'
docker compose version >/dev/null || die 'Docker Compose plugin is required.'
# Explicit identity overrides keep Compose consistent with the host-service user.
compose() { PUID="$MEDIA_UID" PGID="$MEDIA_GID" docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker-compose.yml" "$@"; }
compose config --quiet
if [[ ${1:-} == --check ]]; then
    echo 'Configuration and prerequisites passed. No changes made; Wi-Fi AP support and runtime behavior are not tested.'
    exit 0
fi
[[ $EUID -eq 0 ]] || die 'Run with sudo bash media-setup.sh.'
docker info >/dev/null || die 'Docker daemon is not available.'

apt-get update
apt-get install -y curl ca-certificates qbittorrent-nox
# Only create/adjust these directory entries, never recursively rewrite existing data.
for folder in /srv/downloads /srv/downloads/complete /srv/downloads/incomplete /srv/media /srv/media/movies /srv/media/shows; do
    install -d -o "$MEDIA_UID" -g "$MEDIA_GID" -m 2775 "$folder"
done
for service in prowlarr radarr sonarr; do
    install -d -o "$MEDIA_UID" -g "$MEDIA_GID" -m 0750 "$SCRIPT_DIR/$service"
done

cat > /etc/systemd/system/qbittorrent-nox.service <<EOF
[Unit]
Description=qBittorrent-nox
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$MEDIA_USER
Group=$MEDIA_GROUP
UMask=0002
ExecStart=/usr/bin/qbittorrent-nox --webui-port=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable qbittorrent-nox
systemctl restart qbittorrent-nox

# Download to private temporary storage and propagate installer errors.
download_dir=$(mktemp -d)
trap 'rm -f -- "$download_dir/jellyfin.sh" "$download_dir/nordvpn.sh" "$download_dir/tailscale.sh"; rmdir -- "$download_dir"' EXIT
if [[ $INSTALL_JELLYFIN == true ]]; then
    curl -fsSL https://repo.jellyfin.org/install-debuntu.sh -o "$download_dir/jellyfin.sh"
    bash "$download_dir/jellyfin.sh"
    usermod -aG "$MEDIA_GROUP" jellyfin
    systemctl enable jellyfin
    systemctl restart jellyfin
fi
if [[ $ENABLE_HOTSPOT == true ]]; then
    apt-get install -y hostapd dnsmasq
    install -d -m 0755 /etc/hostapd /etc/dnsmasq.d
    # Restrict the config containing the password, and never print it.
    install -m 0600 /dev/null /etc/hostapd/hostapd.conf
    cat > /etc/hostapd/hostapd.conf <<EOF
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
    cat > /etc/dnsmasq.d/hotspot.conf <<EOF
interface=$HOTSPOT_IFACE
bind-interfaces
dhcp-range=$HOTSPOT_DHCP_START,$HOTSPOT_DHCP_END,255.255.255.0,12h
# Offline-only: do not advertise a default route or DNS server.
dhcp-option=3
dhcp-option=6
port=0
EOF
    cat > /etc/systemd/system/hotspot-ip.service <<EOF
[Unit]
Description=Assign static IP to dedicated hotspot adapter
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip addr replace $HOTSPOT_IP/24 dev $HOTSPOT_IFACE
ExecStart=/usr/sbin/ip link set $HOTSPOT_IFACE up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    for service in hostapd dnsmasq; do
        install -d "/etc/systemd/system/$service.service.d"
        cat > "/etc/systemd/system/$service.service.d/portable-media.conf" <<EOF
[Unit]
Requires=hotspot-ip.service
After=hotspot-ip.service
EOF
    done
    systemctl unmask hostapd
    systemctl daemon-reload
    systemctl enable hotspot-ip hostapd dnsmasq
    systemctl restart hotspot-ip hostapd dnsmasq
fi
if [[ $INSTALL_NORDVPN == true ]]; then
    curl -fsSL https://downloads.nordcdn.com/apps/linux/install.sh -o "$download_dir/nordvpn.sh"
    sh "$download_dir/nordvpn.sh"
    usermod -aG nordvpn "$MEDIA_USER"
fi
if [[ $INSTALL_TAILSCALE == true ]]; then
    curl -fsSL https://tailscale.com/install.sh -o "$download_dir/tailscale.sh"
    sh "$download_dir/tailscale.sh"
fi
if [[ $START_CONTAINERS == true ]]; then compose up -d; fi
echo 'Setup steps completed. Configure application paths/authentication and test connectivity; see README.'
echo "Use PUID=$MEDIA_UID and PGID=$MEDIA_GID in .env for future Compose commands."
echo 'Inspect host addresses with: ip -br addr'
echo 'Host services: qBittorrent :8080, Jellyfin :8096 (if installed).'
echo 'Containers: Prowlarr :9696, Radarr :7878, Sonarr :8989.'
echo 'No firewall rules, VPN login, or VPN routing were changed by this script.'
