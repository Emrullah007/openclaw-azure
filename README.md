# OpenClaw on Azure

Deploy [OpenClaw](https://openclaw.ai/) (open-source personal AI assistant) on a single Azure VM, powered by your own Azure AI Foundry model. OpenClaw connects to messaging apps (Telegram, WhatsApp, etc.) and uses LLMs to execute real tasks.

**Budget target:** ~$29/month | **VM:** Standard_B2als_v2 (2 vCPU, 4 GiB RAM)

---

## Architecture

```
Your Machine
    │
    └─ SSH Tunnel (port 18789)
            │
    Azure Resource Group
            │
    ┌───────▼────────────────────────┐
    │  Ubuntu 24.04 VM               │
    │  Standard_B2als_v2             │
    │  (2 vCPU, 4 GiB RAM)          │
    │                                │
    │  ┌──────────────────────────┐  │
    │  │  Docker: OpenClaw        │  │
    │  │  Gateway :18789          │  │◄── Telegram / WhatsApp / etc.
    │  └──────────────────────────┘  │
    └────────────────────────────────┘
            │
    Azure AI Foundry (separate resource group)
    GPT-4o (or any deployed model)
```

---

## Cost Estimate

| Resource | ~Monthly Cost |
|---|---|
| Standard_B2als_v2 VM | ~$24 |
| Standard LRS OS Disk (32 GB) | ~$2 |
| Standard Public IP | ~$3 |
| Outbound bandwidth (< 5 GB) | ~$0 |
| **Total** | **~$29/month** |

> Stop the VM when not in use to save ~$24/month on compute:
> `az vm deallocate -g <resource-group> -n <vm-name>`

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
Go to https://microsoft.com/devicelogin, enter the code shown, and sign in with your Azure subscription account.

If you have multiple tenants, specify yours:
```bash
az login --tenant <your-tenant-id> --use-device-code
```

### 3. SSH Key

Check if you already have one:
```bash
ls ~/.ssh/*.pub
```
If none exists, generate one:
```bash
ssh-keygen -t ed25519 -C "openclaw"
```
Get the public key contents (you'll paste this into `parameters.json`):
```bash
cat ~/.ssh/id_ed25519.pub   # or id_rsa.pub if you used RSA
```

### 4. Your Public IP (for firewall rule)

```bash
curl -4 ifconfig.me
```
This restricts SSH access to only your machine. You'll add `/32` to the result (e.g. `203.0.113.10/32`).

> **Note:** If your home IP changes (dynamic ISP), update the NSG rule in Azure Portal or redeploy with the new IP.

### 5. Azure AI Foundry Keys

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your **Azure AI Foundry** resource
3. Click **Keys and Endpoint** in the left menu
4. Copy **Key 1** and the **Endpoint URL**
5. Note your model **deployment name** (under Deployments)

### 6. Telegram Bot Token (or other channel)

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. BotFather will give you a token like `123456789:AABBcc...`
4. Copy that token — you'll paste it into `.env`

---

## Deployment Steps

### 1. Clone this repo

```bash
git clone https://github.com/Emrullah007/openclaw-azure.git
cd openclaw-azure
chmod +x scripts/*.sh
```

### 2. Configure parameters

```bash
cp infra/parameters.example.json infra/parameters.json
```

Edit `infra/parameters.json` and fill in:
- `sshPublicKey`: full contents of your `~/.ssh/id_ed25519.pub` (or `id_rsa.pub`)
- `allowedSshSourceIp`: your IP from `curl -4 ifconfig.me` + `/32` (e.g. `203.0.113.10/32`)

> `parameters.json` is gitignored — it will never be committed to GitHub.

### 3. Configure environment

```bash
cp docker/.env.example docker/.env
```

Edit `docker/.env` and fill in:
- `AZURE_API_BASE`: your Azure AI Foundry endpoint URL
- `AZURE_API_KEY`: your Azure AI Foundry key
- `AZURE_DEPLOYMENT_NAME`: your GPT-4o (or other) deployment name
- `OPENCLAW_MODEL`: `azure/<your-deployment-name>`
- `TELEGRAM_BOT_TOKEN`: your Telegram bot token (or other channel)
- `OPENCLAW_CONFIG_DIR` / `OPENCLAW_WORKSPACE_DIR`: update `<admin-username>` to match what you'll choose in the next step

> `docker/.env` is gitignored — it will never be committed to GitHub.

### 4. Deploy Azure infrastructure

```bash
./scripts/deploy.sh
```

The script interactively asks you to:
- Select a region (with estimated monthly cost)
- Name your resource group (default: `openclaw-rg`)
- Choose a VM name — checks DNS availability and re-prompts if taken
- Choose an admin username (default: `azureuser`)
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

> VM IP and deployment details are saved to `.deployment-info` (gitignored).

### 5. Initialize the VM

```bash
./scripts/setup-vm.sh
```

Reads the VM IP and username from `.deployment-info` automatically. This SSHes into the VM and:
- Updates all system packages
- Installs Docker (via official apt repo) and Docker Compose
- Configures UFW firewall (deny all inbound except SSH)
- Enables fail2ban (brute force protection)
- Enables automatic security updates
- Creates `~/.openclaw/config` and `~/.openclaw/workspace` directories

At the end you'll see a security summary confirming all layers are active.

### 6. Install OpenClaw on the VM

**6a.** SSH into the VM:
```bash
ssh <admin-username>@<vm-ip>
```

**6b.** Clone OpenClaw:
```bash
git clone https://github.com/openclaw/openclaw.git ~/openclaw
```

**6c.** Copy your `.env` — run this on your **local machine**:
```bash
scp docker/.env <admin-username>@<vm-ip>:~/openclaw/.env
```

**6d.** Run OpenClaw setup — back on the VM:
```bash
cd ~/openclaw
./scripts/docker/setup.sh
```

This builds the Docker image and starts the OpenClaw gateway.

### 7. Access the Gateway

The gateway only listens on localhost (not exposed to the internet). Access it via SSH tunnel from your local machine:

```bash
ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>
```

Then open `http://localhost:18789` in your browser.

---

## Azure AI Foundry Configuration

In `docker/.env`:

```env
AZURE_API_BASE=https://your-resource.openai.azure.com
AZURE_API_KEY=your-key
AZURE_API_VERSION=2024-02-01
AZURE_DEPLOYMENT_NAME=gpt-4o
OPENCLAW_MODEL=azure/gpt-4o
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
| View OpenClaw logs | on VM: `docker compose -f ~/openclaw/docker-compose.yml logs -f` |
| Teardown everything | `./scripts/destroy.sh` |

---

## Security

- SSH key authentication only (no password login)
- Azure NSG restricts port 22 to your IP only
- UFW firewall on the VM as a second layer
- fail2ban blocks SSH brute force attempts
- Automatic OS security updates enabled
- OpenClaw gateway is NOT exposed to the internet — SSH tunnel only
- `docker/.env` and `infra/parameters.json` are gitignored and never committed
