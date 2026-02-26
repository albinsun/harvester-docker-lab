# Harvester Docker Lab (harvester-docker-lab)

A self-contained, lightweight test laboratory for booting and testing [Harvester](https://harvesterhci.io/) via iPXE. 

Unlike traditional setups, this project **completely removes the dependency on `libvirt` and `virt-manager`**. It uses pure Docker containers to orchestrate the PXE boot environment, QEMU/KVM virtualization, and a web-based GUI (noVNC).

## 🏗 Architecture

The lab consists of three core services connected via a dedicated Docker bridge network:

1. **`pxe-server`**: A lightweight container running `dnsmasq` (DHCP/TFTP) and `nginx` (HTTP). It assigns an IP to the QEMU node and serves the Harvester kernel, initrd, and rootfs for iPXE booting.
2. **`qemu-node`**: The actual Harvester virtual machine running inside a container. It uses `qemu-system-x86_64` and strictly requires host KVM acceleration (`/dev/kvm`).
3. **`novnc-viewer`**: A web-based VNC client that connects to the `qemu-node`, allowing you to view the Harvester installation screen directly in your browser without any desktop VNC client.

## ⚠️ Prerequisites (Linux Only)

Due to the strict requirements of nested hardware virtualization and Layer 2 networking for PXE booting, this project is designed for **Linux bare-metal or Linux VMs with nested virtualization enabled**.

* **OS**: Linux (Ubuntu, Debian, Fedora, etc.)
* **Hardware**: CPU with VT-x / AMD-V enabled.
* **Dependencies**:
  * Docker
  * Docker Compose
  * `/dev/kvm` must exist and be accessible on the host.

*(Note: Docker Desktop on macOS and Windows is **not supported** due to hypervisor limitations regarding `/dev/kvm` passthrough.)*

## 🚀 Quick Start

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/](https://github.com/)<your-username>/harvester-docker-lab.git
   cd harvester-docker-lab
