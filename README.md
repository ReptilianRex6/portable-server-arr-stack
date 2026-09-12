# Portable media server and ARR stack

Ubuntu media server with Prowlarr, Radarr, and Sonarr in Docker, plus qBittorrent and optionally Jellyfin as host services. An optional dedicated Wi-Fi adapter gives offline access to local media.

This is a starting point for a fresh Ubuntu machine. `media-setup.sh` changes packages, writes systemd units, creates data directories, and restarts qBittorrent. It has been syntax/config-checked; a full install and physical hotspot test are still recommended before relying on it.

## Setup steps

1. [Install Ubuntu Server](#1-install-ubuntu-server) — skip if you already have Ubuntu Server running
2. [Install Docker](#2-install-docker) — skip if `docker compose version` already works
3. [Clone and configure the repo](#3-clone-and-configure-the-repo)
4. [Validate and install](#4-validate-and-install)
5. [Finish application configuration](#finish-application-configuration)

## What runs where?

| Application | Runs as | Web port | Persistent state |
|---|---|---:|---|
| Prowlarr | Docker Compose service | 9696 | `./prowlarr` |
| Radarr | Docker Compose service | 7878 | `./radarr` |
| Sonarr | Docker Compose service | 8989 | `./sonarr` |
| qBittorrent | Ubuntu systemd service | 8080 | Under the selected Linux user's profile |
| Jellyfin | Optional Ubuntu service | 8096 | Usually `/var/lib/jellyfin` and `/etc/jellyfin` |

qBittorrent and Jellyfin won't show up in `docker ps` — they're host services, not containers. Media and download directories live under `/srv`.

## 1. Install Ubuntu Server

Skip this section if you already have a fresh Ubuntu Server install with sudo access.

1. Download the latest Ubuntu Server LTS ISO: https://ubuntu.com/download/server
2. Write it to a USB drive with Ventoy (recommended), [Rufus](https://rufus.ie/) (Windows) or [balenaEtcher](https://etcher.balena.io/) (Windows/Mac/Linux).
3. Boot the target machine from the USB and run the installer. Defaults are fine for most cases; two choices matter here:
   - Enable **OpenSSH server** when asked, so you can manage the box remotely.
   - Create a non-root user — this becomes your `MEDIA_USER` later.
4. Reboot into the new install, log in, and update it:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
5. Note the machine's IP address for remote access:
   ```bash
   ip -br addr
   ```

## 2. Install Docker

Skip this section if `docker compose version` already works on the host.

```bash
# Remove any old/conflicting packages
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official apt repository
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker Engine, CLI, and the Compose plugin
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Let your user run docker without sudo (log out/in afterward)
sudo usermod -aG docker "$USER"
```

Verify:

```bash
docker compose version
```

Full reference: [Docker Engine install docs for Ubuntu](https://docs.docker.com/engine/install/ubuntu/).

## 3. Clone and configure the repo

Clone into a permanent directory — relative config mounts depend on this location staying put.

```bash
git clone https://github.com/ReptilianRex6/portable-server-arr-stack.git
cd portable-server-arr-stack
cp .env.example .env
cp setup.conf.example setup.conf
chmod 600 .env setup.conf
id -u
id -g
```

### Configure Compose (`.env`)

```bash
nano .env
```

Set `PUID` and `PGID` to the numeric IDs from `id -u`/`id -g` above for the account that will run the media service, and pick a timezone. Defaults are `1000`, `1000`, `Etc/UTC`.

```yaml
PUID=1000
PGID=1000
TZ=Etc/UTC
```

### Configure host setup (`setup.conf`)

```bash
nano setup.conf
```

By default the script uses the account that invoked `sudo`, installs Jellyfin, and starts the Compose stack. Set `MEDIA_USER` only to use a different existing non-root account. Hotspot, NordVPN, and Tailscale installation are disabled by default, and no passwords ship with the repo.

```yaml
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
# Required only when hotspot is enabled; choose a unique 8-63 character value.
HOTSPOT_PASSWORD=
# All three addresses must be in the same /24. Keep the gateway outside the pool.
HOTSPOT_IP=192.168.50.1
HOTSPOT_DHCP_START=192.168.50.10
HOTSPOT_DHCP_END=192.168.50.100
```

See [Optional offline hotspot](#optional-offline-hotspot) below before enabling it.

## 4. Validate and install

```bash
sudo bash media-setup.sh --check
sudo bash media-setup.sh
```

`--check` validates config, OS/systemd prerequisites, and Compose syntax without changing the system — it does not check credentials, free space, AP capability, or that services actually work end to end.

The installer passes the selected user's IDs to Compose explicitly, so the containers match directory ownership. Keep `.env` consistent for later manual Compose commands; the installer won't overwrite it.

## Configuration files

| File | Purpose |
|---|---|
| `docker-compose.yml` | The three ARR containers; defaults can be overridden with `.env`. |
| `.env.example` | Non-personal Compose defaults to copy locally. |
| `setup.conf.example` | Host installer options to copy locally. |
| `media-setup.sh` | Host packages, folders, qBittorrent unit, optional Jellyfin/hotspot/VPN, Compose startup. |
| `.gitignore` | Excludes local secrets/config and generated application folders. |

`.env` configures Compose; `setup.conf` configures the host installer. Flipping a `setup.conf` option to `false` does not remove an already-installed feature — it just skips that step on the next run.

## Finish application configuration

Find the host's address with `ip -br addr`, then open `http://HOST-IP:PORT` for each app and complete its initial setup and authentication. For qBittorrent, check its journal for a temporary password:

```bash
sudo journalctl -u qbittorrent-nox -n 50 --no-pager
```

Don't publish logs containing credentials. The script does not configure accounts, indexers, API keys, download clients, library paths, or automatic imports — that's done through each app's UI.

### Storage paths

| Host path | Sonarr/Radarr container path | Purpose |
|---|---|---|
| `/srv/downloads/complete` | `/data/downloads/complete` | Finished downloads |
| `/srv/downloads/incomplete` | `/data/downloads/incomplete` | In-progress downloads |
| `/srv/media/movies` | `/data/media/movies` | Movie library |
| `/srv/media/shows` | `/data/media/shows` | Series library |

Configure qBittorrent with the host paths and the container apps with container paths. If qBittorrent reports `/srv/downloads/...`, Sonarr/Radarr need a download-client remote path mapping from `/srv/downloads/` to `/data/downloads/` (or another consistent arrangement) — the script doesn't set this up via their APIs.

Inside Sonarr/Radarr, `localhost:8080` refers to the container itself, not the host qBittorrent service — point them at a reachable host address and port instead. Prowlarr can reach the other Compose services by their service names on the project network once configured in its UI.

The script sets ownership and setgid permissions on the directories above without recursively rewriting existing files, gives qBittorrent a group-writable umask, and adds Jellyfin to the media user's group when installing it. Validate with a small test file rather than assuming directory creation alone proves import or playback works.

## Optional offline hotspot

Set `ENABLE_HOTSPOT=true` in `setup.conf`, choose the real `HOTSPOT_IFACE`, and supply a unique password — never reuse the historical password that was committed in earlier revisions of this repo.

Default SSID is `PortableMedia`, default gateway `192.168.50.1`, DHCP range `.10`–`.100`. Only a single `/24` is supported, the gateway must sit outside the DHCP pool, and the range shouldn't overlap your existing networks.

The adapter must be dedicated to this use — not managed concurrently by NetworkManager/netplan or another DHCP/AP service. The installer writes hostapd config, a dnsmasq drop-in, and a systemd address unit, but won't touch other network managers or merge existing hotspot configs for you.

This is **offline access only**: no default gateway or DNS is advertised, and no internet forwarding/NAT is configured. With the default address, reach Jellyfin at `http://192.168.50.1:8096`. The machine still needs internet for the initial package downloads even though later playback is offline.

## Firewall and VPNs

The script does not enable UFW, add firewall rules, or change VPN routing. If you run a firewall, permit only the intended clients/services (including DHCP on the hotspot interface, if enabled). Docker publishes declared ports on host interfaces by default, so ordinary UFW rules alone are not a complete container-port access policy — see [Docker's firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/).

Optional Jellyfin and VPN installation uses vendor-provided scripts downloaded over HTTPS. Review upstream instructions before enabling them:

- [Jellyfin Linux installation](https://jellyfin.org/docs/general/installation/linux/)
- [Tailscale Linux installation](https://tailscale.com/download/linux)
- [NordVPN Linux downloads](https://nordvpn.com/download/linux/)

VPN installation does not log in or connect — do that separately and test LAN/hotspot access afterward. This project doesn't configure a qBittorrent VPN binding or guarantee VPN-only traffic.

## Status and troubleshooting

```bash
# From this repository directory
sudo docker compose ps -a
sudo docker compose logs --tail 50 sonarr
systemctl status qbittorrent-nox jellyfin --no-pager
ip -br addr
ls -ldn /srv/downloads /srv/media
```

If using another account via `MEDIA_USER`, make sure `.env` matches its numeric IDs. For a missing file, check whether you're looking at a host path or container path. For an app missing from `docker ps`, check whether it's a host service instead.

## Backups, updates, and testing

Back up the Compose/config files, each application's state, and any irreplaceable media. Keep credentials private and store backups off the source disk — application-consistent backups may require stopping services or using their supported backup functions; the repo and container images alone can't restore application databases.

Images use the `latest` tag and external installers/packages change over time, so this repo isn't a version-pinned snapshot — record installed versions and test upgrades before applying them to important data.

The installer isn't transactional and has no automatic rollback; a failed run can leave completed steps in place. Reruns restart services and rewrite unit/config files, but changing the media user, hotspot interface, or directory layout on an existing install needs a migration plan — review service logs before retrying.

Before trusting a deployment, validate: clean Ubuntu install, successful application login, client connectivity, path mapping, test-file import/playback, and restart persistence. Test the physical hotspot separately from a VM.
