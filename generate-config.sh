#!/usr/bin/env bash
# generate-config.sh
#
# Reads settings.yml and:
#   1. Copies Harvester artefacts from the local paths specified in settings.yml
#      into data/harvester/ (using the standard names expected by boot.ipxe)
#   2. Copies undionly.kpxe from the local path specified in settings.yml
#      into data/tftpboot/
#   3. Writes data/harvester/boot.ipxe
#   4. Writes data/harvester/harvester-config.yaml
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
import sys, os, shutil

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

iso_dest    = f'harvester-{version}-amd64.iso'
kernel_dest = 'harvester-vmlinuz'
initrd_dest = 'harvester-initrd'
rootfs_dest = 'harvester-rootfs.squashfs'

# Derived HTTP URLs (always from pxe_server_ip — served by nginx inside the container)
iso_url    = f'http://{pxe_ip}/{iso_dest}'
kernel_url = f'http://{pxe_ip}/{kernel_dest}'
initrd_url = f'http://{pxe_ip}/{initrd_dest}'
rootfs_url = f'http://{pxe_ip}/{rootfs_dest}'

cfg      = s.get('harvester_config', {}) or {}
hostname = cfg.get('hostname', 'harvester-node-0')
password = cfg.get('password', 'password1234')
token    = cfg.get('token', 'password1234')

install  = s.get('install', {}) or {}
device   = install.get('device', '/dev/vda')
mgmt_nic = install.get('management_interface', 'ens3')
vip      = str(install.get('vip', ''))  # empty string → skip VIP block
vip_mode = install.get('vip_mode', 'dhcp')

os.makedirs('data/harvester', exist_ok=True)
os.makedirs('data/tftpboot', exist_ok=True)

def _copy(src_key, dest_path):
    """Copy a local file into data/harvester/ (or data/tftpboot/) if the path is set."""
    src = str(s.get(src_key, '') or '').strip()
    if not src:
        return
    if not os.path.isfile(src):
        print(f"  ✗  {src_key}: '{src}' not found — skipping", file=sys.stderr)
        return
    shutil.copy2(src, dest_path)
    print(f"  ✓  copied {src}  →  {dest_path}")

_copy('harvester_kernel_path',  f'data/harvester/{kernel_dest}')
_copy('harvester_ramdisk_path', f'data/harvester/{initrd_dest}')
_copy('harvester_rootfs_path',  f'data/harvester/{rootfs_dest}')
_copy('harvester_iso_path',     f'data/harvester/{iso_dest}')
_copy('undionly_kpxe_path',     'data/tftpboot/undionly.kpxe')

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
print("  ✓  data/harvester/boot.ipxe")

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
print("  ✓  data/harvester/harvester-config.yaml")

# ── missing-file warnings ──────────────────────────────────────────────────
missing = []
for name in [kernel_dest, initrd_dest, rootfs_dest, iso_dest]:
    if not os.path.isfile(f'data/harvester/{name}'):
        missing.append(f'data/harvester/{name}')
if not os.path.isfile('data/tftpboot/undionly.kpxe'):
    missing.append('data/tftpboot/undionly.kpxe')

if missing:
    print()
    print("⚠  The following files are still missing — set their paths in settings.yml")
    print("   and re-run ./generate-config.sh, or copy them manually:")
    for m in missing:
        print(f"     {m}")
    print()
    print("   Download URLs:")
    print(f"     https://github.com/harvester/harvester/releases/tag/{version}")
    print(f"     https://boot.ipxe.org/undionly.kpxe  (for undionly.kpxe)")
else:
    print()
    print("✓  All artefacts present.  Run:  docker compose up --build -d")
PYEOF
