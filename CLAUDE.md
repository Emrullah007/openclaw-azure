# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Infrastructure-as-Code deployment of [OpenClaw](https://openclaw.ai/) (open-source personal AI assistant) on a single Azure VM. OpenClaw connects to messaging apps (Telegram, WhatsApp, etc.) and uses LLMs to execute real tasks. This project deploys it on Azure using the user's own Azure AI Foundry GPT-4o model.

**Budget target:** $20–30/month. Everything in one resource group (default: `openclaw-rg`) except the AI Foundry model (separate RG, pre-existing).

## Key Decisions

- **Region:** `westus2` (West US 2 — closest to Seattle)
- **VM size:** `Standard_B2als_v2` (2 vCPU, 4 GiB RAM, AMD) — meets OpenClaw's 2 GB minimum, ~$24/month
- **IaC:** Azure Bicep (modular: `main.bicep` → `network.bicep` + `vm.bicep`)
- **Deployment:** Docker via OpenClaw's own `./scripts/docker/setup.sh`
- **Security:** Gateway bound to loopback only; access via SSH tunnel on port 18789
- **LLM:** Azure AI Foundry GPT-4o, referenced as `azure/gpt-4o` in OpenClaw config

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
  deploy.sh          # az login → create RG → deploy Bicep
  setup-vm.sh        # SSH into VM, installs Docker + security hardening
  destroy.sh         # Deletes entire resource group (irreversible)
```

## Common Commands

```bash
# Deploy infrastructure
az login
./scripts/deploy.sh

# Initialize VM after deploy
./scripts/setup-vm.sh <vm-public-ip>

# Access gateway via tunnel (run locally)
ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>

# Stop VM to save money
az vm deallocate --resource-group <resource-group> --name <vm-name>

# Full teardown
./scripts/destroy.sh
```

## Configuration Files (never commit)

- `infra/parameters.json` — SSH public key, your IP for NSG, Azure region
- `docker/.env` — Azure AI Foundry API keys, Telegram bot token, model name

## OpenClaw Architecture

OpenClaw runs as a Docker container on the VM. Its gateway (`ws://localhost:18789`) is the control plane for channels (Telegram, WhatsApp, etc.), tool execution, and LLM calls. The OpenClaw repo is cloned to `~/openclaw` on the VM and started via `./scripts/docker/setup.sh`.

## Cost Guardrails

Stop the VM when not in use: `az vm deallocate -g openclaw-rg -n openclaw-vm`
The main cost driver is compute (~$24/month running). Disk + IP = ~$5/month even when stopped.
