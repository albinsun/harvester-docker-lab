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

### 1. Configure settings

Edit **`settings.yml`** to set your Harvester version, credentials, and the local paths to your downloaded artefacts:

```yaml
harvester_version: v1.7.1

# Local paths — generate-config.sh will copy these into data/harvester/ automatically
harvester_kernel_path:  /downloads/harvester-v1.7.1-vmlinuz-amd64
harvester_ramdisk_path: /downloads/harvester-v1.7.1-initrd-amd64
harvester_rootfs_path:  /downloads/harvester-v1.7.1-rootfs-amd64.squashfs
harvester_iso_path:     /downloads/harvester-v1.7.1-amd64.iso
undionly_kpxe_path:     /downloads/undionly.kpxe

harvester_config:
  hostname: harvester-node-0
  password: password1234
  token: password1234

install:
  device: /dev/vda           # virtio disk inside QEMU
  management_interface: ens3 # virtio-net NIC name (check boot console)
```

> **Note:** The full ISO is **not** used for PXE-booting (that uses the separate vmlinuz/initrd/squashfs files), but **it is required** by the installer as the `iso_url` source to write the OS to disk.

Download all five artefacts from the [Harvester GitHub Releases](https://github.com/harvester/harvester/releases) page and `undionly.kpxe` from https://boot.ipxe.org/undionly.kpxe, then set their paths in `settings.yml`.

See the [Settings Reference](#settings-reference) section below for all available options.

### 2. Generate boot files and copy artefacts

```bash
./generate-config.sh
```

This reads `settings.yml` and:
- Copies each artefact from its configured path into `data/harvester/` or `data/tftpboot/`
- Generates `data/harvester/boot.ipxe` (iPXE chainload script)
- Generates `data/harvester/harvester-config.yaml` (automated-install config)
- Reports any still-missing files so you know exactly what's left to add

The expected directory layout after running the script:

```
data/
├── harvester/
│   ├── boot.ipxe                    # ← generated
│   ├── harvester-config.yaml        # ← generated
│   ├── harvester-vmlinuz            # ← copied from harvester_kernel_path
│   ├── harvester-initrd             # ← copied from harvester_ramdisk_path
│   ├── harvester-rootfs.squashfs    # ← copied from harvester_rootfs_path
│   └── harvester-v1.7.1-amd64.iso  # ← copied from harvester_iso_path
└── tftpboot/
    └── undionly.kpxe                # ← copied from undionly_kpxe_path
```

### 3. Start the lab

Docker Compose v2:
```bash
docker compose up --build -d
```

Docker Compose v1:
```bash
docker-compose up --build -d
```

The `qemu-node` service waits until `pxe-server` passes its health check (both `dnsmasq` and `nginx` running) before the VM starts, so there is no race condition on first boot.

### 4. Watch the installation

Open your browser at **http://localhost:6080** to see the Harvester installer running inside the QEMU VM via the noVNC viewer.

> **Security note:** The noVNC console is unauthenticated. It is intended for local lab use only — do not expose port 6080 to untrusted networks.

### 5. Stop the lab

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
├── settings.yml             # ← Edit this to configure your lab
├── generate-config.sh       # ← Run this to generate boot files
├── docker-compose.yml       # Orchestrates all three services
├── data/
│   ├── harvester/           # Bind-mounted into pxe-server at /var/www/harvester
│   │   ├── boot.ipxe                 # (generated) iPXE script
│   │   ├── harvester-config.yaml     # (generated) install config
│   │   ├── harvester-vmlinuz         # copied by generate-config.sh
│   │   ├── harvester-initrd          # copied by generate-config.sh
│   │   ├── harvester-rootfs.squashfs # copied by generate-config.sh
│   │   └── harvester-*.iso           # copied by generate-config.sh
│   └── tftpboot/            # Bind-mounted into pxe-server at /tftpboot
│       └── undionly.kpxe    # copied by generate-config.sh
├── pxe/
│   ├── Dockerfile           # Alpine + dnsmasq + nginx
│   ├── dnsmasq.conf         # DHCP (192.168.200.100-200) + TFTP config
│   ├── nginx.conf           # HTTP file server for Harvester artefacts
│   └── start-pxe.sh         # Starts nginx then dnsmasq
└── qemu/
    ├── Dockerfile           # Debian + qemu-system-x86
    └── start-vm.sh          # TAP/bridge networking setup + QEMU launch
```

## Settings Reference

All settings are in **`settings.yml`**. Run `./generate-config.sh` after editing.

| Key | Default | Description |
|---|---|---|
| `harvester_version` | `v1.7.1` | Harvester release tag — used to name the ISO inside `data/harvester/` |
| `pxe_server_ip` | `192.168.200.2` | IP of the `pxe-server` container (must match `docker-compose.yml`) |
| `harvester_iso_path` | _(empty)_ | Local path to the Harvester ISO; copied to `data/harvester/harvester-<version>-amd64.iso` |
| `harvester_kernel_path` | _(empty)_ | Local path to the vmlinuz; copied to `data/harvester/harvester-vmlinuz` |
| `harvester_ramdisk_path` | _(empty)_ | Local path to the initrd; copied to `data/harvester/harvester-initrd` |
| `harvester_rootfs_path` | _(empty)_ | Local path to the squashfs; copied to `data/harvester/harvester-rootfs.squashfs` |
| `undionly_kpxe_path` | _(empty)_ | Local path to `undionly.kpxe`; copied to `data/tftpboot/undionly.kpxe` |
| `harvester_config.hostname` | `harvester-node-0` | Hostname assigned to the installed node |
| `harvester_config.password` | `password1234` | Password for the built-in `rancher` user |
| `harvester_config.token` | `password1234` | Cluster join token (same on all nodes) |
| `install.device` | `/dev/vda` | Target disk — virtio disks appear as `/dev/vda` in QEMU |
| `install.management_interface` | `ens3` | Management NIC name inside the VM (verify in boot console) |
| `install.vip` | _(empty)_ | Cluster VIP IP; leave empty to skip |
| `install.vip_mode` | `dhcp` | VIP allocation mode (`dhcp` or `static`) |

## Networking Details

* Docker bridge subnet: `192.168.200.0/24`, gateway `192.168.200.1`
* `pxe-server` fixed IP: `192.168.200.2`
* DHCP pool for the Harvester VM: `192.168.200.100 – 192.168.200.200`
* The `qemu-node` container creates a TAP device and bridges it with `eth0` so the QEMU guest is directly reachable on the Docker network.
* QEMU capabilities required: `NET_ADMIN`, `NET_RAW` (set in `docker-compose.yml`).

