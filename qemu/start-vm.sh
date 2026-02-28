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

# 1. Create a TAP device for the guest NIC (idempotent on container restart)
ip tuntap add dev tap0 mode tap 2>/dev/null \
    || ip link show tap0 >/dev/null 2>&1 \
    || { echo "Error: failed to create tap0 (is /dev/net/tun available?)" >&2; exit 1; }
ip link set tap0 up

# 2. Create a software bridge (idempotent on container restart)
ip link add name br0 type bridge 2>/dev/null \
    || ip link show br0 >/dev/null 2>&1 \
    || { echo "Error: failed to create br0" >&2; exit 1; }
ip link set br0 up

# 3. Capture the container's current IP/prefix and default gateway
#    before we detach eth0 from the IP stack.
CONTAINER_CIDR=$(ip -4 addr show eth0 | awk '/inet / {print $2}')
GW=$(ip route show default | awk '/via/ {print $3; exit}')

# Validate that we actually obtained an IP and a default gateway.
if [ -z "${CONTAINER_CIDR}" ] || [ -z "${GW}" ]; then
    echo "Error: Container IP (CONTAINER_CIDR='${CONTAINER_CIDR}') or default gateway (GW='${GW}') not found. Aborting bridge setup." >&2
    exit 1
fi

# 4. Move eth0 into the bridge and re-assign the IP to the bridge itself
ip addr del "${CONTAINER_CIDR}" dev eth0 || true
ip link set eth0 master br0
ip link set tap0 master br0
ip addr add "${CONTAINER_CIDR}" dev br0
ip route add default via "${GW}" dev br0 || true

# ---------------------------------------------------------------------------
# Launch QEMU
#   -boot order=nc  → network first (PXE install), then disk on subsequent boots
#   -display vnc    → listen on TCP 5900; bound to 0.0.0.0 so the novnc-viewer
#                     container can reach it across the Docker bridge network
#                     (VNC port 5900 is not exposed to the host)
#   -serial mon:stdio → serial console on stdout for logging
#   NOTE: cache=writeback favours performance; in a test lab this is acceptable.
#         Use cache=writethrough or cache=none for stronger durability.
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
    -boot order=nc \
    -display vnc=0.0.0.0:0 \
    -serial mon:stdio \
    -no-reboot
