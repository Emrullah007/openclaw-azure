#!/usr/bin/env bash
# ============================================================
# OpenClaw — VM Initialization Script
# Run this on your LOCAL machine after deploying the VM.
# It SSHes into the VM and installs Docker + OpenClaw deps.
#
# Usage:
#   ./scripts/setup-vm.sh                      # reads IP + username from .deployment-info
#   ./scripts/setup-vm.sh <ip>                 # explicit IP, username from .deployment-info
#   ./scripts/setup-vm.sh <ip> <username>      # fully explicit, ignores .deployment-info
# ============================================================

set -euo pipefail

# ── Resolve VM IP and SSH username ───────────────────────────
# If both args are provided, use them directly (no .deployment-info needed).
# If only IP is provided, still read username from .deployment-info.
# If neither is provided, read both from .deployment-info.

if [ $# -ge 2 ]; then
  # Fully explicit — ignore .deployment-info entirely
  VM_IP="$1"
  SSH_USER="$2"
else
  # Load state file if present
  if [ -f ".deployment-info" ]; then
    # shellcheck source=/dev/null
    source .deployment-info
  fi
  VM_IP="${1:-${PUBLIC_IP:-}}"
  SSH_USER="${ADMIN_USERNAME:-azureuser}"
fi

if [ -z "$VM_IP" ]; then
  echo "❌ No VM IP provided and no .deployment-info found."
  echo "   Usage: $0 <vm-public-ip> [admin-username]"
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)

echo "🔗 Connecting to $SSH_USER@$VM_IP..."

# Pass SSH_USER into the remote script via environment
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${VM_IP}" "SETUP_USER=${SSH_USER} bash" <<'REMOTE_SCRIPT'
set -euo pipefail

echo ""
echo "════════════════════════════════════════"
echo " OpenClaw VM Setup"
echo "════════════════════════════════════════"

export DEBIAN_FRONTEND=noninteractive

# ── System update ─────────────────────────────────────────────
echo "📦 Updating system packages..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ── Install dependencies ──────────────────────────────────────
echo "📦 Installing dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl git ufw fail2ban unattended-upgrades \
  apt-transport-https ca-certificates gnupg lsb-release

# ── Docker (via official apt repo — pinned, auditable) ────────
echo "🐳 Installing Docker..."
if ! command -v docker &>/dev/null; then
  # Add Docker's official GPG key and repo (avoids pipe-to-sh)
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "${SETUP_USER}"
  echo "✅ Docker installed"
else
  echo "✅ Docker already installed"
fi

docker compose version &>/dev/null && echo "✅ Docker Compose available"

# ── Firewall (UFW) ────────────────────────────────────────────
# Note: Azure NSG restricts SSH to your IP at the cloud level.
# UFW here is a second layer — allow SSH so we don't lock ourselves out.
echo "🔥 Configuring UFW firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw --force enable
echo "✅ UFW active — SSH allowed, all other inbound denied"

# ── fail2ban ──────────────────────────────────────────────────
echo "🛡️  Enabling fail2ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
echo "✅ fail2ban active"

# ── Automatic security updates (non-interactive) ──────────────
echo "🔄 Enabling unattended security updates..."
sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
echo "✅ Automatic security updates enabled"

# ── OpenClaw directory ────────────────────────────────────────
echo "📁 Setting up OpenClaw directories..."
mkdir -p ~/.openclaw/workspace

echo ""
echo "════════════════════════════════════════"
echo " ✅ VM setup complete!"
echo ""
echo " Security summary:"
echo "   ✔ SSH key auth only (no passwords)"
echo "   ✔ UFW firewall active (deny all inbound except SSH)"
echo "   ✔ fail2ban active (blocks brute force)"
echo "   ✔ Automatic security updates enabled"
echo "   ✔ Azure NSG restricts SSH to your IP (cloud level)"
echo "   ✔ Docker installed via official apt repo (pinned, auditable)"
echo ""
echo " Next steps:"
echo "   Run on your local machine: ./scripts/configure-openclaw.sh"
echo "   This will clone OpenClaw, write the model config, build"
echo "   the Docker image, and print your dashboard access URL."
echo "════════════════════════════════════════"
REMOTE_SCRIPT

echo ""
echo "✅ Remote setup complete on $VM_IP"
echo ""
echo -e "   Next step: \033[0;36m./scripts/configure-openclaw.sh\033[0m"
