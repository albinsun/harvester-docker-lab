# harvester-docker-lab

A self-contained, lightweight test laboratory for booting and testing [Harvester](https://harvesterhci.io/) via iPXE — no `libvirt` or `virt-manager` required.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│               Docker bridge: harvester-lab              │
│                   subnet 192.168.200.0/24               │
│                                                         │
│  ┌─────────────────┐     ┌──────────────────────────┐  │
│  │   pxe-server    │     │        qemu-node         │  │
│  │  192.168.200.2  │◄────│  (Harvester VM via KVM)  │  │
│  │                 │     │  VNC → TCP 5900           │  │
│  │  dnsmasq        │     └──────────┬───────────────┘  │
│  │  (DHCP + TFTP)  │               │                   │
│  │  nginx (HTTP)   │     ┌──────────▼───────────────┐  │
│  └─────────────────┘     │      novnc-viewer        │  │
│                           │  host port 6080 → :8080  │  │
│                           └──────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

| Service | Role |
|---|---|
| **pxe-server** | Runs `dnsmasq` (DHCP + TFTP) to assign an IP and serve the iPXE bootloader to the VM; runs `nginx` to serve Harvester's kernel, initrd, and rootfs over HTTP. |
| **qemu-node** | Boots a QEMU/KVM virtual machine using hardware acceleration (`/dev/kvm`), connected to the Docker bridge via a TAP interface so it receives DHCP from `pxe-server`. |
| **novnc-viewer** | Proxies the QEMU VNC display (port 5900) to a browser-accessible noVNC web UI (host port 6080). |

## Prerequisites

* Docker ≥ 20.10 with Docker Compose v2 (`docker compose`) or Compose v1 (`docker-compose`)
* A Linux host with KVM support — verify with:

  ```bash
  ls /dev/kvm
  ```

## Quick Start

### 1. Prepare Harvester boot files

> **Note:** The full Harvester ISO (`harvester-vX.Y.Z-amd64.iso`) is **not** used for PXE boot. Instead, download the individual PXE artefacts from the [Harvester GitHub Releases](https://github.com/harvester/harvester/releases) page.

For example, for **v1.7.1** download these three files:

| Release asset | Save as |
|---|---|
| `harvester-v1.7.1-vmlinuz-amd64` | `harvester-vmlinuz` |
| `harvester-v1.7.1-initrd-amd64` | `harvester-initrd` |
| `harvester-v1.7.1-rootfs-amd64.squashfs` | `harvester-rootfs.squashfs` |

Place all five files (including `boot.ipxe` and `harvester-config.yaml`) in the named volume **or** a local directory bind-mounted to `/var/www/harvester` inside `pxe-server`:

```
/var/www/harvester/
├── boot.ipxe                   # iPXE chainload script (see example below)
├── harvester-config.yaml       # Harvester install configuration (see example below)
├── harvester-vmlinuz           # Harvester kernel (renamed from vmlinuz-amd64)
├── harvester-initrd            # Harvester initial RAM disk (renamed from initrd-amd64)
└── harvester-rootfs.squashfs   # Harvester root filesystem (renamed from rootfs-amd64.squashfs)
```

Example `boot.ipxe` (replace `192.168.200.2` if you change the `pxe-server` IP):

```
#!ipxe
kernel http://192.168.200.2/harvester-vmlinuz \
    ip=dhcp \
    rd.neednet=1 \
    console=ttyS0,115200n8 \
    root=live:http://192.168.200.2/harvester-rootfs.squashfs \
    harvester.install.automatic=true \
    harvester.install.config_url=http://192.168.200.2/harvester-config.yaml \
    harvester.install.skipchecks=true \
    initrd=harvester-initrd
initrd http://192.168.200.2/harvester-initrd
boot
```

> **Important:** The `root=live:http://...` kernel parameter is required. Without it, the Harvester initrd cannot locate the root filesystem and the installer will not start.
>
> **Important:** `harvester.install.config_url` is required for automatic installation. Without it, the Harvester OS boots to a login prompt instead of running the installer.

Example `harvester-config.yaml` (a template is provided at `pxe/harvester-config.yaml.example`):

```yaml
scheme_version: 1
token: harvester-token
os:
  hostname: harvester-node01
  password: CHANGE_ME
  ntp_servers:
    - 0.suse.pool.ntp.org
install:
  mode: create
  device: /dev/vda
  management_interface:
    interfaces:
      - name: eth0
    bond_options:
      mode: active-backup
      miimon: 100
    method: dhcp
```

> **Note:** Inside QEMU the virtio disk is always `/dev/vda`. Do not use `/dev/sda`.

Place the iPXE bootloader binary (`undionly.kpxe`, available from https://boot.ipxe.org/undionly.kpxe) in the `tftp-data` volume (mounted at `/tftpboot` inside `pxe-server`).

> **Tip — using a local directory instead of a named volume:**
> Replace the `harvester-files` and `tftp-data` named volumes in `docker-compose.yml` with bind mounts so you can copy files directly from the host:
> ```yaml
> volumes:
>   - ./harvester-files:/var/www/harvester
>   - ./tftpboot:/tftpboot
> ```

### 2. Start the lab

Docker Compose v2:
```bash
docker compose up --build -d
```

Docker Compose v1:
```bash
docker-compose up --build -d
```

The `qemu-node` service waits until `pxe-server` passes its health check (both `dnsmasq` and `nginx` running) before the VM starts, so there is no race condition on first boot.

### 3. Watch the installation

Open your browser at **http://localhost:6080** to see the Harvester installer running inside the QEMU VM via the noVNC viewer.

> **Security note:** The noVNC console is unauthenticated. It is intended for local lab use only — do not expose port 6080 to untrusted networks.

### 4. Stop the lab

Docker Compose v2:
```bash
docker compose down
```

Docker Compose v1:
```bash
docker-compose down
```

## File Layout

```
harvester-docker-lab/
├── docker-compose.yml       # Orchestrates all three services
├── pxe/
│   ├── Dockerfile           # Alpine + dnsmasq + nginx
│   ├── dnsmasq.conf         # DHCP (192.168.200.100-200) + TFTP config
│   ├── nginx.conf           # HTTP file server for Harvester artefacts
│   └── start-pxe.sh         # Starts nginx then dnsmasq
└── qemu/
    ├── Dockerfile           # Debian + qemu-system-x86
    └── start-vm.sh          # TAP/bridge networking setup + QEMU launch
```

## Networking Details

* Docker bridge subnet: `192.168.200.0/24`, gateway `192.168.200.1`
* `pxe-server` fixed IP: `192.168.200.2`
* DHCP pool for the Harvester VM: `192.168.200.100 – 192.168.200.200`
* The `qemu-node` container creates a TAP device and bridges it with `eth0` so the QEMU guest is directly reachable on the Docker network.
* QEMU capabilities required: `NET_ADMIN`, `NET_RAW` (set in `docker-compose.yml`).

