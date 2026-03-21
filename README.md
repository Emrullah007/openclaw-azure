# OpenClaw on Azure

Personal deployment of [OpenClaw](https://openclaw.ai/) on an Azure VM, powered by Azure AI Foundry (GPT-4o).

**Budget target:** $20–30/month | **Region:** West US 2 (Seattle area)

---

## Architecture

```
Your Machine
    │
    └─ SSH Tunnel (port 18789)
            │
    Azure Resource Group: openclaw-rg
            │
    ┌───────▼────────────────────────┐
    │  Ubuntu 24.04 VM               │
    │  Standard_B2als_v2             │
    │  (2 vCPU, 4 GiB RAM)          │
    │                                │
    │  ┌──────────────────────────┐  │
    │  │  Docker: OpenClaw        │  │
    │  │  Gateway :18789          │  │◄── Telegram Bot
    │  └──────────────────────────┘  │
    └────────────────────────────────┘
            │
    Azure AI Foundry (separate RG)
    GPT-4o deployment
```

---

## Cost Estimate (West US 2)

| Resource | ~Monthly Cost |
|---|---|
| Standard_B2als_v2 VM | ~$24 |
| Standard LRS OS Disk (32 GB) | ~$2 |
| Standard Public IP | ~$3 |
| Outbound bandwidth (< 5 GB) | ~$0 |
| **Total** | **~$29/month** |

> Stop the VM when not in use to save ~$24/month on compute.
> `az vm deallocate --resource-group openclaw-rg --name openclaw-vm`

---

## Prerequisites

### 1. Azure CLI

Check if installed:
```bash
az --version
```
If not installed: https://docs.microsoft.com/cli/azure/install-azure-cli

### 2. Azure Login

```bash
az login --use-device-code
```
Go to https://microsoft.com/devicelogin, enter the code shown, and sign in with your **Azure subscription account**.
If you have multiple tenants, specify yours:
```bash
az login --tenant <your-tenant-id> --use-device-code
```
Verify you see your subscription listed after login.

### 3. SSH Key

Check if you already have one:
```bash
ls ~/.ssh/*.pub
```
If none exists, generate one:
```bash
ssh-keygen -t ed25519 -C "openclaw"
```
Get the contents to paste into `parameters.json`:
```bash
cat ~/.ssh/id_ed25519.pub   # or id_rsa.pub if you used RSA
```

### 4. Your Public IP (for NSG security rule)

```bash
curl -4 ifconfig.me
```
This restricts SSH access to only your machine. Add `/32` to the result (e.g. `203.0.113.10/32`).

> **Note:** Your home IP may change occasionally (ISP dynamic IP). If you get locked out, update the NSG rule in Azure Portal or run `./scripts/deploy.sh` again with the new IP.

### 5. Azure AI Foundry Keys

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your **Azure AI Foundry** resource
3. Click **Keys and Endpoint** in the left menu
4. Copy **Key 1** and the **Endpoint URL**
5. Note your **GPT-4o deployment name** (under Deployments)

### 6. Telegram Bot Token

1. Open Telegram and search for `@BotFather`
2. Send `/newbot`
3. Follow the prompts — choose a name and username for your bot
4. BotFather will give you a token like `123456789:AABBcc...`
5. Copy that token for `.env`

---

## Deployment Steps

### 1. Configure parameters

```bash
cp infra/parameters.example.json infra/parameters.json
```

Edit `infra/parameters.json`:
- `sshPublicKey`: full contents of your `~/.ssh/id_ed25519.pub` (or `id_rsa.pub`)
- `allowedSshSourceIp`: your IP from `curl -4 ifconfig.me` + `/32`

> `parameters.json` is gitignored — it will never be committed to GitHub.

### 2. Configure environment

```bash
cp docker/.env.example docker/.env
```

Edit `docker/.env` with your Azure AI Foundry keys and Telegram bot token.

### 3. Deploy Azure infrastructure

```bash
chmod +x scripts/*.sh
az login
./scripts/deploy.sh
```

This creates the resource group, VM, networking, and NSG in ~3 minutes.

### 4. Initialize the VM

```bash
./scripts/setup-vm.sh <vm-public-ip>
```

Installs Docker, configures UFW firewall, and sets up fail2ban.

### 5. Install OpenClaw on the VM

SSH into the VM:
```bash
ssh azureuser@<vm-public-ip>
```

Then on the VM:
```bash
git clone https://github.com/openclaw/openclaw.git ~/openclaw
cd ~/openclaw
```

Copy your `.env` from your local machine:
```bash
# Run this locally:
scp docker/.env azureuser@<vm-public-ip>:~/openclaw/.env
```

Run the OpenClaw Docker setup:
```bash
# On the VM:
cd ~/openclaw
./scripts/docker/setup.sh
```

### 6. Access the Gateway

The gateway is bound to loopback only (secure). Access it via SSH tunnel:

```bash
ssh -L 18789:localhost:18789 azureuser@<vm-public-ip>
```

Then open `http://localhost:18789` in your browser.

---

## Azure AI Foundry Model Configuration

In `docker/.env`, set:

```env
AZURE_API_BASE=https://YOUR-RESOURCE.openai.azure.com
AZURE_API_KEY=your-key
AZURE_API_VERSION=2024-02-01
OPENCLAW_MODEL=azure/gpt-4o   # must match your deployment name
```

In `~/.openclaw/config/openclaw.json` on the VM:
```json
{
  "agent": {
    "model": "azure/gpt-4o"
  }
}
```

---

## Daily Operations

| Task | Command |
|---|---|
| Stop VM (save money) | `az vm deallocate -g openclaw-rg -n openclaw-vm` |
| Start VM | `az vm start -g openclaw-rg -n openclaw-vm` |
| SSH in | `ssh azureuser@<vm-ip>` |
| Gateway tunnel | `ssh -L 18789:localhost:18789 azureuser@<vm-ip>` |
| View logs | `ssh vm` → `docker compose -f ~/openclaw/docker-compose.yml logs -f` |
| Teardown everything | `./scripts/destroy.sh` |

---

## Security Notes

- SSH key authentication only (no passwords)
- NSG allows only port 22 inbound (restrict to your IP)
- UFW firewall on VM as second layer
- fail2ban protects against SSH brute force
- Gateway is NOT exposed publicly — SSH tunnel only
- `.env` and `parameters.json` are gitignored
