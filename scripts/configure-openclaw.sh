#!/usr/bin/env bash
# ============================================================
# OpenClaw — Configure and Start Script
# Run this on your LOCAL machine after setup-vm.sh completes.
#
# Reads .deployment-info and docker/.env, SSHes to the VM,
# clones OpenClaw, writes the model config, builds the Docker
# image, starts the containers, and prints the dashboard URL
# with all pairing steps.
#
# Usage: ./scripts/configure-openclaw.sh
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    OpenClaw — Configure and Start        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────
if [ ! -f ".deployment-info" ]; then
  echo -e "${RED}❌ .deployment-info not found.${NC}"
  echo "   Run ./scripts/deploy.sh first."
  exit 1
fi

if [ ! -f "docker/.env" ]; then
  echo -e "${RED}❌ docker/.env not found.${NC}"
  echo "   Copy docker/.env.example → docker/.env and fill in your values."
  exit 1
fi

# ── Load deployment info ───────────────────────────────────────
# shellcheck source=/dev/null
source .deployment-info
VM_IP="${PUBLIC_IP}"
SSH_USER="${ADMIN_USERNAME:-azureuser}"

echo -e "   VM IP    : ${CYAN}${VM_IP}${NC}"
echo -e "   SSH user : ${CYAN}${SSH_USER}${NC}"
echo ""

# ── Parse docker/.env ─────────────────────────────────────────
# Use grep+cut rather than sourcing the file — sourcing would allow any
# existing shell env vars (e.g. OPENCLAW_CONFIG_DIR) to override values,
# which is exactly the class of bug we want to avoid.
get_env_val() {
  grep -E "^${1}=" docker/.env | head -1 | cut -d= -f2-
}

AZURE_API_BASE="$(get_env_val AZURE_API_BASE)"
AZURE_API_KEY="$(get_env_val AZURE_API_KEY)"
AZURE_DEPLOYMENT_NAME="$(get_env_val AZURE_DEPLOYMENT_NAME)"
TELEGRAM_BOT_TOKEN="$(get_env_val TELEGRAM_BOT_TOKEN)"
# shellcheck disable=SC2034  # used via indirect ${!var} in placeholder detection loop below
OPENCLAW_WORKSPACE_DIR="$(get_env_val OPENCLAW_WORKSPACE_DIR)"
# Base64-encode the full .env so it can be passed as a single env var over SSH
# and written verbatim to ~/openclaw/.env on the VM. tr strips the line wrapping
# that base64 adds by default — both macOS (BSD) and Linux (GNU) support this.
ENV_CONTENT_B64="$(base64 < docker/.env | tr -d '\n')"

# Validate required values — check for empty and unfilled placeholders
missing=()
[ -z "${AZURE_API_BASE}" ]        && missing+=("AZURE_API_BASE")
[ -z "${AZURE_API_KEY}" ]         && missing+=("AZURE_API_KEY")
[ -z "${AZURE_DEPLOYMENT_NAME}" ] && missing+=("AZURE_DEPLOYMENT_NAME")
[ -z "${TELEGRAM_BOT_TOKEN}" ]    && missing+=("TELEGRAM_BOT_TOKEN")

if [ "${#missing[@]}" -gt 0 ]; then
  echo -e "${RED}❌ Missing required values in docker/.env:${NC}"
  for v in "${missing[@]}"; do echo "   - $v"; done
  exit 1
fi

# Detect unfilled placeholders — match exact example values from .env.example only,
# not broad patterns that could reject legitimate resource or deployment names.
placeholder_found=0
declare -A PLACEHOLDER_VALS=(
  [AZURE_API_BASE]="https://<your-resource>.openai.azure.com/openai/v1"
  [AZURE_API_KEY]="your-azure-api-key-here"
  [AZURE_DEPLOYMENT_NAME]="your-deployment-name"
  [TELEGRAM_BOT_TOKEN]="123456789:AABBccDDeeffGGhhIIjjKKllMMnnOOppQQrr"
  [OPENCLAW_WORKSPACE_DIR]="/home/<admin-username>/.openclaw/workspace"
)
for var in "${!PLACEHOLDER_VALS[@]}"; do
  val="${!var}"
  if [[ "$val" == "${PLACEHOLDER_VALS[$var]}" ]]; then
    echo -e "${RED}❌ $var still contains the example placeholder value.${NC}"
    echo -e "   Update docker/.env with your real value before running this script."
    placeholder_found=1
  fi
done
if [ "$placeholder_found" -eq 1 ]; then
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)

echo -e "${CYAN}🔗 Connecting to ${SSH_USER}@${VM_IP}...${NC}"
echo ""

# ── Remote execution ──────────────────────────────────────────
# Values are passed as environment variables on the ssh invocation line
# so they are available in the remote shell without being embedded literally
# in the heredoc (avoids quoting and injection issues).
#
# All progress output inside the heredoc goes to stderr (>&2).
# The very last line of stdout is the tokenized dashboard URL — captured
# by the local $(...) substitution into DASHBOARD_URL.
DASHBOARD_URL=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${VM_IP}" \
  AZURE_API_BASE="${AZURE_API_BASE}" \
  AZURE_API_KEY="${AZURE_API_KEY}" \
  AZURE_DEPLOYMENT_NAME="${AZURE_DEPLOYMENT_NAME}" \
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}" \
  ENV_CONTENT_B64="${ENV_CONTENT_B64}" \
  bash <<'REMOTE_SCRIPT'
set -euo pipefail

# ── 1. Clone OpenClaw ─────────────────────────────────────────
echo "" >&2
echo "════════════════════════════════════════" >&2
echo " Step 1/5 — Clone OpenClaw" >&2
echo "════════════════════════════════════════" >&2

if [ -d "$HOME/openclaw/.git" ]; then
  echo "✅ Already cloned — skipping" >&2
else
  git clone https://github.com/openclaw/openclaw.git "$HOME/openclaw" >&2
  echo "✅ Cloned to ~/openclaw" >&2
fi

# ── 2. Write docker/.env to the VM ───────────────────────────
echo "" >&2
echo "════════════════════════════════════════" >&2
echo " Step 2/5 — Write docker/.env" >&2
echo "════════════════════════════════════════" >&2

# Decode the base64-encoded .env and write it with restricted permissions.
# This ensures OPENCLAW_SANDBOX, OPENCLAW_WORKSPACE_DIR, and any other
# docker-compose vars from the local file take effect on the VM.
echo "${ENV_CONTENT_B64}" | base64 -d > "$HOME/openclaw/.env"
chmod 600 "$HOME/openclaw/.env"
echo "✅ .env written to ~/openclaw/.env" >&2

# ── 3. Write openclaw.json ────────────────────────────────────
echo "" >&2
echo "════════════════════════════════════════" >&2
echo " Step 3/5 — Write model config" >&2
echo "════════════════════════════════════════" >&2

mkdir -p "$HOME/.openclaw"

# Config is written directly to ~/.openclaw/openclaw.json — not to
# ~/.openclaw/config/openclaw.json. Docker Compose uses OPENCLAW_CONFIG_DIR
# from the environment, but the shell env can override what is in .env.
# Writing directly here guarantees the correct path regardless.
cat > "$HOME/.openclaw/openclaw.json" <<CONFIG
{
  "gateway": {
    "mode": "local",
    "controlUi": {
      "allowedOrigins": ["http://localhost:18789", "http://127.0.0.1:18789"]
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "my-model/${AZURE_DEPLOYMENT_NAME}"
      }
    }
  },
  "models": {
    "providers": {
      "my-model": {
        "baseUrl": "${AZURE_API_BASE}",
        "apiKey": "${AZURE_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "${AZURE_DEPLOYMENT_NAME}",
            "name": "${AZURE_DEPLOYMENT_NAME}"
          }
        ]
      }
    }
  },
  "channels": {
    "telegram": {
      "botToken": "${TELEGRAM_BOT_TOKEN}"
    }
  }
}
CONFIG

echo "✅ Config written to ~/.openclaw/openclaw.json" >&2

# ── 4. Build image and start containers ───────────────────────
echo "" >&2
echo "════════════════════════════════════════" >&2
echo " Step 4/5 — Build image and start containers" >&2
echo " (first build takes ~3-5 minutes)" >&2
echo "════════════════════════════════════════" >&2

# sg docker runs the command as the docker group — needed because the user
# was added to the group by setup-vm.sh in the same SSH session (group
# assignment takes effect on next login; sg works without re-login).
sg docker -c "cd $HOME/openclaw && ./scripts/docker/setup.sh" >&2

echo "✅ Containers running" >&2

# ── 5. Get dashboard URL ─────────────────────────────────────
echo "" >&2
echo "════════════════════════════════════════" >&2
echo " Step 5/5 — Get dashboard URL" >&2
echo "════════════════════════════════════════" >&2

sleep 3

RAW_URL=$(sg docker -c \
  "docker compose -f $HOME/openclaw/docker-compose.yml run --rm openclaw-cli dashboard --no-open" \
  2>/dev/null | grep -Eo 'http[s]?://[^ ]+' | head -1)

# Replace 127.0.0.1 with localhost so the URL works via SSH tunnel
TOKENIZED_URL="${RAW_URL/127.0.0.1/localhost}"

echo "✅ Dashboard URL ready" >&2
echo "" >&2

# ── Output: URL only on stdout (captured by local shell) ──────
echo "${TOKENIZED_URL}"
REMOTE_SCRIPT
)

# ── Print final access instructions ──────────────────────────
echo ""

if [ -z "${DASHBOARD_URL}" ]; then
  echo -e "${YELLOW}⚠️  OpenClaw started but could not retrieve the dashboard URL.${NC}"
  echo -e "   Get it manually by running on the VM:"
  echo -e "   ${CYAN}docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli dashboard --no-open${NC}"
  echo ""
  DASHBOARD_LINE="(run the command above on the VM to get your tokenized URL)"
else
  DASHBOARD_LINE="${DASHBOARD_URL}"
fi

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅  OpenClaw is running!                                        ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}1. Open an SSH tunnel — this also gives you a VM shell:${NC}"
echo -e "${GREEN}║${NC}     ssh -L 18789:localhost:18789 ${SSH_USER}@${VM_IP}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}2. Get your tokenized dashboard URL (run this on the VM):${NC}"
echo -e "${GREEN}║${NC}     docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli dashboard --no-open"
echo -e "${GREEN}║${NC}     Then open the printed URL (including #token=...) in your browser."
if [ -n "${DASHBOARD_URL}" ]; then
echo -e "${GREEN}║${NC}     URL: ${DASHBOARD_LINE}"
fi
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}3. Click Connect — then approve the browser device (on the VM):${NC}"
echo -e "${GREEN}║${NC}     docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices list"
echo -e "${GREEN}║${NC}     docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli devices approve <id>"
echo -e "${GREEN}║${NC}     Then refresh the browser — it will not auto-connect after approval."
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}4. Pair Telegram — send /start to your bot, then (on the VM):${NC}"
echo -e "${GREEN}║${NC}     docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli pairing approve telegram <code>"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   ${YELLOW}ℹ Tip: Add this alias on the VM to shorten future commands:${NC}"
echo -e "   ${YELLOW}  alias oc='docker compose -f ~/openclaw/docker-compose.yml run --rm openclaw-cli'${NC}"
echo -e "   ${YELLOW}  Then: oc devices list  |  oc devices approve <id>  |  oc pairing approve telegram <code>${NC}"
echo ""
