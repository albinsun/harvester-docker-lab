#!/usr/bin/env bash
# generate-config.sh
#
# Reads settings.yml and writes:
#   data/harvester/boot.ipxe
#   data/harvester/harvester-config.yaml
#
# Usage:
#   ./generate-config.sh
#
# Requires: python3 and PyYAML (pip3 install pyyaml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${SCRIPT_DIR}/settings.yml"

if [ ! -f "${SETTINGS}" ]; then
    echo "Error: settings.yml not found at ${SETTINGS}" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required. Please install Python 3." >&2
    exit 1
fi

# Install PyYAML if absent (installs into the user's Python environment)
python3 -c "import yaml" 2>/dev/null || {
    echo "PyYAML not found. Installing pyyaml via pip (pass --no-deps to pip3 to skip)..."
    python3 -m pip install --quiet pyyaml
}

echo "Generating configuration from settings.yml ..."

python3 - "${SETTINGS}" <<'PYEOF'
import sys, os

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

settings_path = sys.argv[1]

with open(settings_path) as f:
    s = yaml.safe_load(f)

pxe_ip  = str(s.get('pxe_server_ip', '192.168.200.2'))
version = str(s.get('harvester_version', 'v1.7.1'))

iso_url    = s.get('harvester_iso_url',    f'http://{pxe_ip}/harvester-{version}-amd64.iso')
kernel_url = s.get('harvester_kernel_url', f'http://{pxe_ip}/harvester-vmlinuz')
initrd_url = s.get('harvester_ramdisk_url', f'http://{pxe_ip}/harvester-initrd')
rootfs_url = s.get('harvester_rootfs_url', f'http://{pxe_ip}/harvester-rootfs.squashfs')

cfg      = s.get('harvester_config', {}) or {}
hostname = cfg.get('hostname', 'harvester-node-0')
password = cfg.get('password', 'password1234')
token    = cfg.get('token', 'harvester-token')

install  = s.get('install', {}) or {}
device   = install.get('device', '/dev/vda')
mgmt_nic = install.get('management_interface', 'ens3')
vip      = str(install.get('vip', ''))  # empty string → skip VIP block
vip_mode = install.get('vip_mode', 'dhcp')

os.makedirs('data/harvester', exist_ok=True)
os.makedirs('data/tftpboot', exist_ok=True)

# ── data/harvester/boot.ipxe ───────────────────────────────────────────────
boot_ipxe = (
    "#!ipxe\n"
    f"kernel {kernel_url} \\\n"
    f"    ip=dhcp \\\n"
    f"    rd.neednet=1 \\\n"
    f"    console=ttyS0,115200n8 \\\n"
    f"    root=live:{rootfs_url} \\\n"
    f"    harvester.install.automatic=true \\\n"
    f"    harvester.install.config_url=http://{pxe_ip}/harvester-config.yaml \\\n"
    f"    harvester.install.skipchecks=true \\\n"
    f"    initrd=harvester-initrd\n"
    f"initrd {initrd_url}\n"
    f"boot\n"
)

with open('data/harvester/boot.ipxe', 'w') as f:
    f.write(boot_ipxe)
print("  \u2713  data/harvester/boot.ipxe")

# ── data/harvester/harvester-config.yaml ───────────────────────────────────
config_lines = [
    "scheme_version: 1\n",
    f"token: {token}\n",
    "os:\n",
    f"  hostname: {hostname}\n",
    f"  password: {password}\n",
    "  ntp_servers:\n",
    "    - 0.suse.pool.ntp.org\n",
    "install:\n",
    "  mode: create\n",
    f"  device: {device}\n",
    f"  iso_url: {iso_url}\n",
    "  management_interface:\n",
    "    interfaces:\n",
    f"      - name: {mgmt_nic}\n",
    "    bond_options:\n",
    "      mode: active-backup\n",
    "      miimon: 100\n",
    "    method: dhcp\n",
]
if vip:
    config_lines += [f"  vip: {vip}\n", f"  vip_mode: {vip_mode}\n"]

with open('data/harvester/harvester-config.yaml', 'w') as f:
    f.writelines(config_lines)
print("  \u2713  data/harvester/harvester-config.yaml")

print()
print("Next steps:")
print(f"  1. Copy Harvester artefacts to data/harvester/:")
print(f"       harvester-vmlinuz          (rename from harvester-{version}-vmlinuz-amd64)")
print(f"       harvester-initrd           (rename from harvester-{version}-initrd-amd64)")
print(f"       harvester-rootfs.squashfs  (rename from harvester-{version}-rootfs-amd64.squashfs)")
print(f"       harvester-{version}-amd64.iso  (keep original name)")
print(f"  2. Copy undionly.kpxe \u2192 data/tftpboot/undionly.kpxe")
print(f"     (download from https://boot.ipxe.org/undionly.kpxe)")
print(f"  3. Run:  docker compose up --build -d")
PYEOF
