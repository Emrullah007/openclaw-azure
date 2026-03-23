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
./scripts/deploy.sh
```

The script will interactively ask you to:
- Select a region (with estimated monthly cost shown)
- Name your resource group (default: `openclaw-rg`)
- Choose a VM name — it checks DNS availability automatically and re-prompts if taken
- Confirm before deploying

Deployment takes ~3 minutes. At the end you'll see:

```
╔══════════════════════════════════════════════════╗
║  ✅  Deployment complete!                        ║
╠══════════════════════════════════════════════════╣
║  Public IP  : 20.x.x.x
║  DNS        : your-vm-name.westus2.cloudapp.azure.com
║  SSH        : ssh <admin-username>@20.x.x.x
║  Tunnel     : ssh -L 18789:localhost:18789 <admin-username>@20.x.x.x
╚══════════════════════════════════════════════════╝
```

> Your VM IP and name are saved to `.deployment-info` (gitignored).

### 4. Initialize the VM

```bash
./scripts/setup-vm.sh 20.x.x.x   # use your actual VM IP from step 3
```

This SSHes into the VM and automatically:
- Updates all system packages
- Installs Docker (v29+) and Docker Compose
- Configures UFW firewall (deny all inbound except SSH)
- Enables fail2ban (brute force protection)
- Enables automatic security updates
- Creates `~/.openclaw/config` and `~/.openclaw/workspace` directories

At the end you'll see a security summary confirming all layers are active.

### 5. Install OpenClaw on the VM

**5a. Clone OpenClaw** — SSH into the VM and clone the repo:
```bash
ssh <admin-username>@20.x.x.x   # username chosen during deploy, default: azureuser
git clone https://github.com/openclaw/openclaw.git ~/openclaw
```

**5b. Copy your `.env`** — run this on your **local machine**:
```bash
scp docker/.env <admin-username>@20.x.x.x:~/openclaw/.env
```

**5c. Run OpenClaw setup** — back on the VM:
```bash
cd ~/openclaw
./scripts/docker/setup.sh
```

This builds the Docker image and starts the OpenClaw gateway.

### 6. Access the Gateway

The gateway only listens on localhost (not exposed to the internet). Access it via SSH tunnel from your local machine:

```bash
ssh -L 18789:localhost:18789 <admin-username>@20.x.x.x
```

Then open `http://localhost:18789` in your browser. You'll see the OpenClaw web UI.

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
| Stop VM (save money) | `az vm deallocate -g <resource-group> -n <vm-name>` |
| Start VM | `az vm start -g <resource-group> -n <vm-name>` |
| SSH in | `ssh <admin-username>@<vm-ip>` |
| Gateway tunnel | `ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>` |
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
