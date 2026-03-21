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
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"

echo "🔗 Connecting to $SSH_USER@$VM_IP..."

# Run the full setup remotely via SSH heredoc
ssh $SSH_OPTS "${SSH_USER}@${VM_IP}" bash <<'REMOTE_SCRIPT'
set -euo pipefail

echo ""
echo "════════════════════════════════════════"
echo " OpenClaw VM Setup"
echo "════════════════════════════════════════"

# ── System update ─────────────────────────────────────────────
echo "📦 Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# ── Install dependencies ──────────────────────────────────────
echo "📦 Installing dependencies..."
sudo apt-get install -y -qq \
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

# Docker Compose v2 plugin (built into Docker Engine ≥23)
docker compose version &>/dev/null && echo "✅ Docker Compose available"

# ── Firewall (UFW) ────────────────────────────────────────────
echo "🔥 Configuring UFW firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh          # port 22
sudo ufw --force enable
sudo ufw status verbose

# ── fail2ban ──────────────────────────────────────────────────
echo "🛡️  Enabling fail2ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# ── Automatic security updates ────────────────────────────────
echo "🔄 Enabling unattended security updates..."
sudo dpkg-reconfigure --priority=low unattended-upgrades

# ── OpenClaw directory ────────────────────────────────────────
echo "📁 Setting up OpenClaw directories..."
mkdir -p ~/.openclaw/config ~/.openclaw/workspace

echo ""
echo "════════════════════════════════════════"
echo " ✅ VM setup complete!"
echo ""
echo " Next steps (run on VM):"
echo "   1. Clone OpenClaw repo:"
echo "      git clone https://github.com/openclaw/openclaw.git ~/openclaw"
echo "   2. Copy your .env file to ~/openclaw/.env"
echo "   3. cd ~/openclaw && ./scripts/docker/setup.sh"
echo ""
echo " To access the gateway from your machine:"
echo "   ssh -L 18789:localhost:18789 azureuser@<vm-ip>"
echo "   Then open: http://localhost:18789"
echo "════════════════════════════════════════"
REMOTE_SCRIPT

echo ""
echo "✅ Remote setup complete on $VM_IP"
echo ""
echo "📋 Next: Copy your docker/.env file to the VM:"
echo "   scp docker/.env ${SSH_USER}@${VM_IP}:~/openclaw/.env"
