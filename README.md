# OpenClaw on Azure

> Deploy your own personal AI assistant on Azure — private, secure, and fully under your control.

[OpenClaw](https://openclaw.ai/) is an open-source personal AI assistant that connects to the messaging apps you already use (Telegram, WhatsApp, Discord, and more) and executes real tasks on your behalf — managing emails, checking calendars, browsing the web, running shell commands, and much more.

This repository gives you everything you need to deploy OpenClaw on a single Azure VM, powered by your own Azure AI Foundry model (GPT-4o or any other deployed model). When you are done experimenting, you can stop the VM to pause costs — or destroy everything with a single command and redeploy from scratch whenever you want.

---

## What You Will Learn

- Provisioning Azure infrastructure with **Bicep** (Azure's native Infrastructure-as-Code language)
- Deploying and securing a **Linux VM** on Azure
- Running a self-hosted AI assistant using **Docker**
- Connecting your own **Azure AI Foundry** model to an open-source project
- Accessing private services securely using **SSH tunnels**

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Your Local Machine                                     │
│                                                         │
│  $ ssh -L 18789:localhost:18789 <admin-username>@<vm-ip> │
│         │                                               │
│         │  SSH Tunnel (encrypted)                       │
└─────────┼───────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│  Azure Resource Group                                   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Ubuntu 24.04 VM  (Standard_B2als_v2)            │   │
│  │                                                  │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │  Docker Container: OpenClaw                │  │   │
│  │  │                                            │  │   │
│  │  │  Gateway (ws://localhost:18789)            │◄─┼───┼── Telegram Bot
│  │  │  ├── Session & channel management         │  │   │
│  │  │  ├── Tool execution (browser, shell, etc) │  │   │
│  │  │  └── LLM calls ──────────────────────────►│  │   │
│  │  └─────────────────────────────┬──────────────┘  │   │
│  └────────────────────────────────┼─────────────────┘   │
│                                   │                     │
└───────────────────────────────────┼─────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │  Azure AI Foundry         │
                    │  (separate resource group)│
                    │  GPT-4o / custom model    │
                    └───────────────────────────┘
```

**Key design decisions:**

- **Gateway is never publicly exposed.** Port 18789 is bound inside Docker and not reachable from the internet. You access it from your browser via an encrypted SSH tunnel — this means no credentials or traffic are ever sent over the open internet.
- **Everything lives in one resource group.** Tear it all down with one command, redeploy from scratch with another.
- **Your AI model stays yours.** OpenClaw calls your own Azure AI Foundry deployment — your data does not go through any third-party AI service you have not already authorized.

---

## Prerequisites

You will need the following before starting. Each section below explains how to get it.

### 1. Azure CLI

The command-line tool for managing Azure resources.

```bash
az --version
```

If not installed: https://docs.microsoft.com/cli/azure/install-azure-cli

### 2. Azure Subscription and Login

```bash
az login --use-device-code
```

Go to https://microsoft.com/devicelogin, enter the code shown, and sign in with your Azure account. If you belong to multiple Azure tenants (organizations), specify the correct one:

```bash
az login --tenant <your-tenant-id> --use-device-code
```

### 3. SSH Key Pair

SSH keys are how you authenticate to your VM — no passwords. Check if you already have one:

```bash
ls ~/.ssh/*.pub
```

If not, generate one:

```bash
ssh-keygen -t ed25519 -C "openclaw"
```

View your public key (you will paste this into `parameters.json` in a later step):

```bash
cat ~/.ssh/id_ed25519.pub   # or id_rsa.pub if you used RSA
```

### 4. Your Public IP Address

This is used to lock down SSH access so only your machine can connect to the VM.

```bash
curl -4 ifconfig.me
```

You will add `/32` to the result (e.g. `203.0.113.10/32`). This tells Azure: "only allow SSH from this exact IP address."

> **Tip:** Home internet IPs can change occasionally. If you ever get locked out of your VM, update the NSG (Network Security Group) rule in Azure Portal with your new IP.

### 5. Azure AI Foundry Keys

1. Go to [Azure Portal](https://portal.azure.com)
2. Open your **Azure AI Foundry** resource
3. Click **Keys and Endpoint** in the left menu
4. Copy **Key 1** and the **Target URI**
5. Note the exact **deployment name** of your model (found under Deployments)

### 6. Telegram Bot Token

Telegram is the easiest messaging channel to set up with OpenClaw.

1. Open Telegram on your phone or desktop
2. Search for `@BotFather` and start a chat
3. Send `/newbot`
4. Choose a display name (e.g. `My AI Assistant`)
5. Choose a username ending in `bot` (e.g. `myai_bot`)
6. BotFather replies with a token like `123456789:AABBcc...` — copy it

---

## Step-by-Step Deployment

### Step 1 — Clone this repo

```bash
git clone https://github.com/Emrullah007/openclaw-azure.git
cd openclaw-azure
chmod +x scripts/*.sh
```

### Step 2 — Configure infrastructure parameters

```bash
cp infra/parameters.example.json infra/parameters.json
```

Open `infra/parameters.json` and fill in your values:

```json
{
  "parameters": {
    "sshPublicKey": {
      "value": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-username@your-machine"
    },
    "allowedSshSourceIp": {
      "value": "12.34.56.78/32"
    }
  }
}
```

> Replace `12.34.56.78` with your actual public IP (run `curl -4 ifconfig.me` to find it). The `/32` means "this exact IP only".

> `parameters.json` is listed in `.gitignore` and will never be committed to GitHub.

### Step 3 — Configure your environment

```bash
cp docker/.env.example docker/.env
```

Open `docker/.env` and fill in your values:

```env
# Standard Azure OpenAI endpoint:
AZURE_API_BASE=https://<your-resource>.openai.azure.com/openai/v1

# Your API key (from Azure Portal > your resource > Keys and Endpoint)
AZURE_API_KEY=your-key-here

# Your model deployment name exactly as set in Azure AI Foundry
# Examples: gpt-4o, gpt-4.1, or any custom name you gave it
AZURE_DEPLOYMENT_NAME=your-deployment-name

# Your Telegram bot token from @BotFather
TELEGRAM_BOT_TOKEN=123456789:your-token-here

# Update <admin-username> to match the username you will choose in Step 4
OPENCLAW_WORKSPACE_DIR=/home/<admin-username>/.openclaw/workspace
```

> `docker/.env` is listed in `.gitignore` and will never be committed to GitHub.

> **Azure AI Foundry vs Azure OpenAI:** The standard Azure OpenAI endpoint (`*.openai.azure.com/openai/v1`) works out of the box. If you are using the newer Azure AI Foundry project-based endpoint (`*.services.ai.azure.com/api/projects/...`), use that URL instead — both formats are supported.

### Step 4 — Deploy Azure infrastructure

```bash
./scripts/deploy.sh
```

This interactive script will guide you through:

1. **Region selection** — choose the Azure region closest to you
2. **Resource group name** — press Enter to use the default `openclaw-rg`
3. **VM name** — the script automatically checks if the DNS name is available and prompts you to try another if it is taken
4. **Admin username** — press Enter for the default `azureuser`
5. **Confirmation** — review your choices, then confirm to deploy

Deployment takes approximately 3 minutes. When complete, you will see:

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

> Your VM's IP address and deployment details are automatically saved to `.deployment-info` (gitignored) so the next scripts can read them without you having to type them again.

### Step 5 — Initialize and harden the VM

```bash
./scripts/setup-vm.sh
```

This script connects to your new VM over SSH and automatically sets it up for production use. It installs Docker using the official apt repository (not a convenience script), configures the UFW firewall, enables fail2ban for brute-force protection, and turns on automatic security updates.

When complete, you will see a security summary:

```
 Security summary:
   ✔ SSH key auth only (no passwords)
   ✔ UFW firewall active (deny all inbound except SSH)
   ✔ fail2ban active (blocks brute force)
   ✔ Automatic security updates enabled
   ✔ Azure NSG restricts SSH to your IP (cloud level)
   ✔ Docker installed via official apt repo (pinned, auditable)
```

### Step 6 — Configure and start OpenClaw

Run this on your **local machine**:

```bash
./scripts/configure-openclaw.sh
```

This script SSHes into your VM and automatically:

1. Clones the OpenClaw repository
2. Writes the AI model configuration to `~/.openclaw/openclaw.json`
3. Builds the Docker image and starts the containers (~3–5 minutes)
4. Prints a tokenized dashboard URL and all pairing commands

When complete, you will see:

```
╔══════════════════════════════════════════════════════════════════╗
║  ✅  OpenClaw is running!                                        ║
╠══════════════════════════════════════════════════════════════════╣
║
║  1. Open an SSH tunnel (keep this terminal open):
║     ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>
║
║  2. Open the dashboard in your browser:
║     http://localhost:18789/#token=...
║
║  3. Click Connect — then approve the browser device (on the VM):
║     ...
║
║  4. Pair Telegram — send /start to your bot, then (on the VM):
║     ...
║
╚══════════════════════════════════════════════════════════════════╝
```

### Step 7 — Open the dashboard

Follow the output from Step 6:

1. **Open the SSH tunnel** in a new terminal (keep it open):

```bash
ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>
```

2. **Open the tokenized URL** printed by Step 6 in your browser. The URL includes a session token (`#token=...`) — use the exact URL from the script output, not the plain `http://localhost:18789`.

3. **Approve your browser as a trusted device.** When you click Connect, OpenClaw registers your browser as a new device that must be approved. SSH into the VM and run:

```bash
# List pending device requests
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices list

# Approve your device using the request ID shown
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices approve <request-id>
```

Your browser will automatically connect once approved.

### Step 8 — Pair Telegram

Send `/start` to your Telegram bot. It will reply with a pairing code. Then approve it on the VM:

```bash
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli pairing approve telegram <code>
```

Your bot is now active. Send it any message and it will respond using your Azure AI model.

> **Tip:** Add an alias on the VM to shorten these commands:
> ```bash
> alias oc='docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli'
> # Then use: oc devices list | oc devices approve <id> | oc pairing approve telegram <code>
> ```

---

## Daily Operations

| Task | Command |
|---|---|
| Stop VM (pause costs) | `az vm deallocate -g <resource-group> -n <vm-name>` |
| Start VM | `az vm start -g <resource-group> -n <vm-name>` |
| SSH into VM | `ssh <admin-username>@<vm-ip>` |
| Open dashboard (SSH tunnel) | `ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>` |
| Get dashboard URL with token | on VM: `docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli dashboard --no-open` |
| Approve new device | on VM: `docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices list` then `devices approve <id>` |
| View OpenClaw logs | on VM: `docker compose -f ~/openclaw/docker-compose.yml logs -f` |
| Full teardown | `./scripts/destroy.sh` |

> **Reconnecting after VM restart:** after `az vm start`, SSH into the VM and run `docker compose -f ~/openclaw/docker-compose.yml up -d` if containers did not restart automatically. Then get a fresh dashboard URL with `dashboard --no-open` and approve your device again.

---

## Troubleshooting

**Dashboard shows "unauthorized" or "origin not allowed"**

You are likely opening `http://localhost:18789` directly. OpenClaw requires a token in the URL. Get the correct URL by running on the VM:

```bash
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli dashboard --no-open
```

Copy the full URL (including `#token=...`) and open it in your browser.

---

**`docker: command not found` after `setup-vm.sh`**

Your SSH session predates the Docker group assignment. Log out and back in, or use `sg docker -c "docker ..."` to run commands as the docker group without re-logging in.

---

**Azure AI onboarding wizard fails ("fetch failed" / "verification failed")**

OpenClaw's built-in onboarding wizard does not natively support Azure AI. The `configure-openclaw.sh` script bypasses the wizard entirely by writing the config file directly — this is the correct approach for Azure deployments.

---

**VM becomes very slow or unresponsive**

The `Standard_B2als_v2` is a burstable VM — it accumulates CPU credits when idle and spends them under load. If the container crash-loops for an extended period, credits are exhausted and the CPU is throttled to its baseline (~20%). Check **VM → Metrics → CPU Credits Remaining** in Azure Portal. Credits recover automatically once load drops. If the VM is completely unresponsive, use **Stop (Deallocate)** → **Start** for a cold reboot on a fresh host.

---

## Security

Every layer of this deployment is hardened by default:

| Layer | What it does |
|---|---|
| **SSH key authentication** | Password login is disabled entirely on the VM |
| **Azure NSG** | The cloud-level firewall allows port 22 only from your IP address |
| **UFW firewall** | A second firewall layer on the VM itself |
| **fail2ban** | Automatically bans IPs that repeatedly fail SSH authentication |
| **Automatic OS updates** | Security patches are applied without manual intervention |
| **Docker-internal gateway** | Port 18789 is not reachable from the internet — SSH tunnel only |
| **Gitignored secrets** | `.env` and `parameters.json` are never committed to version control |

---

## Teardown

To permanently delete all Azure resources and stop all costs:

```bash
./scripts/destroy.sh
```

The script will ask you to type the resource group name to confirm before deleting anything. Your Azure AI Foundry model lives in a separate resource group and will not be affected.

To redeploy from scratch later, start again from Step 4.
