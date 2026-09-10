# Portable media server and ARR stack

Set up an Ubuntu media server with Prowlarr, Radarr, and Sonarr in Docker, plus qBittorrent and optionally Jellyfin as host services. An optional dedicated Wi-Fi adapter provides offline access to local media.

This is a starting point for a fresh Ubuntu machine, not a migration tool. The setup changes packages, writes systemd units, creates data directories, and restarts qBittorrent. Test on a disposable machine before using it over an existing installation. The script has syntax/configuration checks; a complete Ubuntu installation and physical hotspot test are still needed.

## What runs where?

| Application | Runs as | Web port | Persistent state |
|---|---|---:|---|
| Prowlarr | Docker Compose service | 9696 | `./prowlarr` |
| Radarr | Docker Compose service | 7878 | `./radarr` |
| Sonarr | Docker Compose service | 8989 | `./sonarr` |
| qBittorrent | Ubuntu systemd service | 8080 | Under the selected Linux user's profile; inspect the installed application |
| Jellyfin | Optional Ubuntu service | 8096 | Distribution package state, usually `/var/lib/jellyfin` and `/etc/jellyfin` |

qBittorrent and Jellyfin will not appear in `docker ps` in this deployment. Media and download directories are under `/srv`.

## Prerequisites

- A fresh, supported Ubuntu Server installation using systemd, an existing non-root user with sudo, and internet access for installation.
- [Docker Engine and the Compose plugin](https://docs.docker.com/engine/install/ubuntu/) installed and a running Docker daemon. The script checks for these instead of replacing an existing Docker installation.
- Enough storage under `/srv` and the repository directory. No data disks are formatted or mounted for you.
- For the optional hotspot: a dedicated Linux-compatible Wi-Fi adapter with AP support. A plain VM without suitable hardware passthrough cannot test this feature.

## Configure and install

Follow these steps on the Ubuntu host.

### 1. Clone and prepare the repository

Clone into a permanent directory: relative application config mounts depend on this location.

```bash
git clone https://github.com/ReptilianRex6/portable-server-arr-stack.git
cd portable-server-arr-stack
cp .env.example .env
cp setup.conf.example setup.conf
chmod 600 .env setup.conf
id -u
id -g
```

### 2. Configure Compose

Edit the Compose environment file:

```bash
nano .env
```

In `.env`, set `PUID` and `PGID` to the numbers for the account that will run the media service, and choose a timezone. The defaults are `1000`, `1000`, and `Etc/UTC`.
```yaml
PUID=1000
PGID=1000
TZ=Etc/UTC
```

### 3. Configure host setup

```bash
nano setup.conf
```

`setup.conf` uses plain `KEY=value` lines: **no quotes, inline comments, or shell expansions**. Values are parsed as data rather than executed. By default the script uses the account that invoked sudo, installs Jellyfin, and starts the Compose stack. Set `MEDIA_USER` only to use another existing non-root account. It determines the real primary group instead of assuming the group matches the username.

Hotspot, NordVPN, and Tailscale installation are disabled by default. No passwords are supplied by the repository.

```yaml
# Copy to setup.conf, chmod 600 setup.conf, then edit.
# Plain KEY=value only: no quotes, inline comments, or shell expansion.
# Omit MEDIA_USER to use the account that invoked sudo.
# MEDIA_USER=mediauser
INSTALL_JELLYFIN=true
START_CONTAINERS=true
INSTALL_NORDVPN=false
INSTALL_TAILSCALE=false

# Optional offline-only hotspot on a dedicated AP-capable Wi-Fi adapter.
ENABLE_HOTSPOT=false
HOTSPOT_IFACE=
HOTSPOT_SSID=PortableMedia
# Required only when hotspot is enabled; choose a unique 8–63 character value.
HOTSPOT_PASSWORD=
# All three addresses must be in the same /24. Keep the gateway outside the pool.
HOTSPOT_IP=192.168.50.1
HOTSPOT_DHCP_START=192.168.50.10
HOTSPOT_DHCP_END=192.168.50.100
```

### 4. Validate and install

```bash
sudo bash media-setup.sh --check
sudo bash media-setup.sh
```

`--check` validates config, OS/systemd prerequisites, and Compose syntax without changing the system. It does not verify credentials, free space, AP capability, or end-to-end service operation. A successful check is not a successful deployment.

The installer explicitly passes the selected user's IDs to Compose, so the initial containers match the directory ownership. Keep `.env` consistent for later manual Compose commands. It does not overwrite your `.env`.

## Configuration files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Three ARR application containers; defaults can be overridden with `.env`. |
| `.env.example` | Non-personal Compose defaults to copy locally. |
| `setup.conf.example` | Host installer options to copy locally. |
| `media-setup.sh` | Host packages, folders, qBittorrent unit, optional Jellyfin/hotspot/VPN tools, Compose startup. |
| `.gitignore` | Excludes local secrets/configuration and generated application folders. |

The two configuration files have separate jobs: `.env` is for Compose, while `setup.conf` configures host setup. Existing installed features are not removed by changing an option to `false`; it skips that step on subsequent runs.

## Finish application configuration

Find the host's actual address using `ip -br addr`, then open `http://HOST-IP:PORT`. Complete each application's initial setup and authentication. For qBittorrent, inspect its journal locally for any temporary password:

```bash
sudo journalctl -u qbittorrent-nox -n 50 --no-pager
```

Do not publish logs containing credentials. The script does not configure application accounts, indexers, API keys, download clients, library paths, or automatic imports.

### Storage paths

| Host path | Sonarr/Radarr container path | Purpose |
|---|---|---|
| `/srv/downloads/complete` | `/data/downloads/complete` | Finished downloads |
| `/srv/downloads/incomplete` | `/data/downloads/incomplete` | In-progress downloads |
| `/srv/media/movies` | `/data/media/movies` | Movie library |
| `/srv/media/shows` | `/data/media/shows` | Series library |

Configure host qBittorrent with the host paths, and configure container applications with container paths. If qBittorrent reports `/srv/downloads/...`, Sonarr/Radarr need a matching download-client remote path mapping from `/srv/downloads/` to `/data/downloads/`, or another deliberately consistent path arrangement. The script does not configure this through their APIs.

Inside Sonarr/Radarr, `localhost:8080` refers to that container, not the host qBittorrent service. Configure and test a reachable host address and port. Prowlarr can reach the other Compose services by their service names on the project network, once configured in its UI.

The script sets ownership and setgid permissions on the listed directories without recursively rewriting existing files. It gives qBittorrent a group-writable umask and adds Jellyfin to the media user's primary group when installing it. Existing files and app-specific creation permissions may still need attention. Validate with a small test file; do not assume directory creation proves import or playback works.

## Optional offline hotspot

Set `ENABLE_HOTSPOT=true` in `setup.conf`, choose the real `HOTSPOT_IFACE`, and supply a unique password. Never reuse the historical password that was committed in earlier revisions.

The default SSID is `PortableMedia`. The default gateway is `192.168.50.1`, with a DHCP range of `.10`–`.100`. This helper supports a single `/24`; the gateway must be outside the DHCP pool. Check that this range does not overlap your existing networks.

The adapter must be dedicated to this use and not configured concurrently by NetworkManager/netplan or another DHCP/AP service. The installer does not change those managers for you. It writes hostapd configuration, a dnsmasq drop-in, and a systemd address unit; it does not merge arbitrary existing hotspot configurations.

This is **offline access only**. No default gateway or DNS service is advertised, and no internet forwarding/NAT is configured. Access Jellyfin using `http://192.168.50.1:8096` if using the default address. The machine needs internet for the initial package downloads even when later playback is offline.

## Firewall and VPNs

The script does not enable UFW, add firewall rules, or change VPN routing. If you already have a firewall, permit only the intended clients and services. For an enabled hotspot, that includes DHCP requests on the dedicated interface. Docker publishes the declared ports on host interfaces by default; [Docker's firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/) means ordinary UFW rules are not a complete container-port access policy.

Optional Jellyfin and VPN installation uses vendor-provided scripts downloaded over HTTPS. Review upstream instructions for your OS before enabling them:

- [Jellyfin Linux installation](https://jellyfin.org/docs/general/installation/linux/)
- [Tailscale Linux installation](https://tailscale.com/download/linux)
- [NordVPN Linux downloads](https://nordvpn.com/download/linux/)

VPN installation does not log in or connect. Complete vendor setup separately and test LAN/hotspot access afterward. This project does not configure a qBittorrent VPN binding or guarantee VPN-only traffic.

## Status and troubleshooting

```bash
# From this repository directory
sudo docker compose ps -a
sudo docker compose logs --tail 50 sonarr
systemctl status qbittorrent-nox jellyfin --no-pager
ip -br addr
ls -ldn /srv/downloads /srv/media
```

If using another account via `MEDIA_USER`, `.env` must match its numeric IDs. For a missing file, distinguish host paths from container paths. For a missing app in Docker, first check whether it is a host service. A NAS deployment using a custom Compose filename is a different setup from this repository.

## Backups, updates, and testing

Back up the Compose/config files, each application's state, and any irreplaceable media. Keep credentials private and store a backup away from the source disk. Application-consistent backups may require stopping services or using their supported backup functions. A container image or this repository alone cannot restore application databases.

Images currently use `latest`; external installers and packages also change over time. This repository is not a version-pinned snapshot. Record installed versions and test upgrades before applying them to important data.

The installer is not transactional and has no automatic rollback. Failed runs may leave completed steps in place. It can restart services and rewrite its unit/config files on rerun; changing a media user, hotspot interface, or directory layout on an existing installation requires a migration plan. Review service logs before retrying.

Validation targets: clean Ubuntu installation, successful application login, client connectivity, path mapping, test-file import/playback, and restart persistence. Test the physical hotspot separately from the VM. No full runtime validation is claimed yet.
