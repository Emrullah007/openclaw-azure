# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Infrastructure-as-Code deployment of [OpenClaw](https://openclaw.ai/) (open-source personal AI assistant) on a single Azure VM. OpenClaw connects to messaging apps (Telegram, WhatsApp, etc.) and uses LLMs to execute real tasks. This project deploys it on Azure using the user's own Azure AI model.

**Budget target:** $20–30/month. Everything in one resource group (default: `openclaw-rg`) except the AI model (separate RG, pre-existing).

## Key Decisions

- **VM size:** `Standard_B2als_v2` (2 vCPU, 4 GiB RAM, AMD) — meets OpenClaw's 2 GB minimum, ~$24/month
- **IaC:** Azure Bicep (modular: `main.bicep` → `network.bicep` + `vm.bicep`)
- **Config:** OpenClaw model config is written directly to `~/.openclaw/openclaw.json` on the VM (not via the onboarding wizard — Azure AI is not natively supported there)
- **Security:** Gateway bound to `lan` inside Docker; port 18789 exposed only via Docker port mapping; access via SSH tunnel
- **LLM:** Azure OpenAI (`*.openai.azure.com/openai/v1`) using a custom provider in `openclaw.json`
- **Dashboard access:** Requires a tokenized URL (`openclaw-cli dashboard --no-open`) and device pairing approval

## Repository Structure

```
infra/               # Azure Bicep templates
  main.bicep         # Entry point — orchestrates modules
  network.bicep      # VNet, Subnet, NSG (SSH only inbound)
  vm.bicep           # Ubuntu 24.04 VM + Public IP
  parameters.example.json  # Template — copy to parameters.json (gitignored)

docker/
  .env.example       # Template — copy to .env (gitignored)

scripts/
  deploy.sh          # Interactive: region → RG → VM name → deploy Bicep
  setup-vm.sh        # SSH into VM: installs Docker + security hardening
  configure-openclaw.sh  # SSH into VM: clones OpenClaw, writes openclaw.json,
                     #   builds image, starts containers, prints dashboard URL
  destroy.sh         # Deletes entire resource group (irreversible)
```

## Deployment Pipeline

```bash
# 1. Deploy Azure infrastructure (interactive)
./scripts/deploy.sh

# 2. Initialize VM (Docker + security hardening)
./scripts/setup-vm.sh          # reads IP from .deployment-info

# 3. Configure and start OpenClaw
./scripts/configure-openclaw.sh  # reads .deployment-info + docker/.env

# 4. Open SSH tunnel (keep terminal open)
ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>

# 5. Get tokenized dashboard URL (on VM)
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli dashboard --no-open

# 6. Approve browser device (on VM, after clicking Connect in browser)
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices list
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices approve <id>

# 7. Pair Telegram (on VM, after sending /start to your bot)
docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli pairing approve telegram <code>

# Stop VM to save money
az vm deallocate -g openclaw-rg -n openclaw-vm

# Full teardown
./scripts/destroy.sh
```

## Configuration Files (never commit)

- `infra/parameters.json` — SSH public key, your IP for NSG
- `docker/.env` — Azure API keys, Telegram bot token, deployment name

## OpenClaw Config on VM

Written by `configure-openclaw.sh` to `~/.openclaw/openclaw.json`:

```json
{
  "gateway": { "mode": "local", "controlUi": { "allowedOrigins": ["http://localhost:18789"] } },
  "agents": { "defaults": { "model": { "primary": "my-model/<deployment-name>" } } },
  "models": {
    "providers": {
      "my-model": {
        "baseUrl": "https://<resource>.openai.azure.com/openai/v1",
        "apiKey": "...",
        "api": "openai-completions",
        "models": [{ "id": "<deployment>", "name": "<deployment>" }]
      }
    }
  },
  "channels": { "telegram": { "botToken": "..." } }
}
```

## Cost Guardrails

Stop the VM when not in use: `az vm deallocate -g openclaw-rg -n openclaw-vm`
The main cost driver is compute (~$24/month running). Disk + IP = ~$5/month even when stopped.
The `Standard_B2als_v2` is a burstable VM — avoid sustained CPU load (e.g. crash-looping containers) as it drains CPU credits and throttles performance.
