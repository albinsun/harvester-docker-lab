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

Download the Harvester release artefacts and place them in the named volume **or** a local directory bind-mounted to `/var/www/harvester` inside `pxe-server`.

Minimum files required:

```
/var/www/harvester/
├── boot.ipxe          # iPXE chainload script (see example below)
├── harvester-vmlinuz  # Harvester kernel
├── harvester-initrd   # Harvester initial RAM disk
└── harvester-rootfs.squashfs
```

Example `boot.ipxe`:

```
#!ipxe
kernel http://192.168.200.2/harvester-vmlinuz \
    ip=dhcp \
    rd.neednet=1 \
    console=ttyS0 \
    harvester.install.automatic=true \
    initrd=harvester-initrd
initrd http://192.168.200.2/harvester-initrd
boot
```

Place the iPXE bootloader binary (`undionly.kpxe`, available from https://boot.ipxe.org/undionly.kpxe) in the `tftp-data` volume (mounted at `/tftpboot` inside `pxe-server`).

### 2. Start the lab

```bash
docker compose up --build -d
```

### 3. Watch the installation

Open your browser at **http://localhost:6080** to see the Harvester installer running inside the QEMU VM via the noVNC viewer.

### 4. Stop the lab

```bash
docker compose down
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

