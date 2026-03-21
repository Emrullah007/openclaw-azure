#!/usr/bin/env bash
# ============================================================
# OpenClaw — VM Initialization Script
# Run this on your LOCAL machine after deploying the VM.
# It SSHes into the VM and installs Docker + OpenClaw deps.
# Usage: ./scripts/setup-vm.sh <vm-public-ip>
# ============================================================

set -euo pipefail

VM_IP="${1:?Usage: $0 <vm-public-ip>}"
SSH_USER="azureuser"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)

echo "🔗 Connecting to $SSH_USER@$VM_IP..."

# Run the full setup remotely via SSH heredoc
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${VM_IP}" bash <<'REMOTE_SCRIPT'
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

# ── Docker ────────────────────────────────────────────────────
echo "🐳 Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
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
mkdir -p ~/.openclaw/config ~/.openclaw/workspace

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
echo ""
echo " Next steps:"
echo "   1. Clone OpenClaw:  git clone https://github.com/openclaw/openclaw.git ~/openclaw"
echo "   2. Copy .env file:  (run locally) scp docker/.env azureuser@<vm-ip>:~/openclaw/.env"
echo "   3. Start OpenClaw:  cd ~/openclaw && ./scripts/docker/setup.sh"
echo ""
echo " Access gateway from your machine (SSH tunnel):"
echo "   ssh -L 18789:localhost:18789 azureuser@<vm-ip>"
echo "   Then open: http://localhost:18789"
echo "════════════════════════════════════════"
REMOTE_SCRIPT

echo ""
echo "✅ Remote setup complete on $VM_IP"
echo ""
echo "📋 Next: Copy your .env to the VM:"
echo "   scp docker/.env ${SSH_USER}@${VM_IP}:~/openclaw/.env"
