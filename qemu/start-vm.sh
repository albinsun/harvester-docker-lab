#!/bin/bash
set -e

# Create a persistent disk image for Harvester if one does not already exist
DISK=/data/harvester.img
if [ ! -f "${DISK}" ]; then
    echo "Creating ${DISK} (150G)..."
    qemu-img create -f qcow2 "${DISK}" 150G
fi

# ---------------------------------------------------------------------------
# Set up TAP + bridge networking so the QEMU guest joins the Docker network
# and can receive DHCP from the pxe-server container.
# ---------------------------------------------------------------------------

# 1. Create a TAP device for the guest NIC
ip tuntap add dev tap0 mode tap || true
ip link set tap0 up

# 2. Create a software bridge
ip link add name br0 type bridge || true
ip link set br0 up

# 3. Capture the container's current IP/prefix and default gateway
#    before we detach eth0 from the IP stack.
CONTAINER_CIDR=$(ip -4 addr show eth0 | awk '/inet / {print $2}')
GW=$(ip route show default | awk '/via/ {print $3; exit}')

# 4. Move eth0 into the bridge and re-assign the IP to the bridge itself
ip addr del "${CONTAINER_CIDR}" dev eth0 || true
ip link set eth0 master br0
ip link set tap0 master br0
ip addr add "${CONTAINER_CIDR}" dev br0
ip route add default via "${GW}" dev br0 || true

# ---------------------------------------------------------------------------
# Launch QEMU
#   -boot order=n  → network first (PXE)
#   -vnc 0.0.0.0:0 → listen on TCP 5900 (noVNC connects here)
# ---------------------------------------------------------------------------
exec qemu-system-x86_64 \
    -name harvester-node \
    -m 8G \
    -smp 4 \
    -accel kvm \
    -cpu host \
    -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
    -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:56 \
    -drive file="${DISK}",if=virtio,format=qcow2,cache=writeback \
    -boot order=n,strict=on \
    -vnc 0.0.0.0:0 \
    -nographic \
    -no-reboot
