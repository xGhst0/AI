#!/usr/bin/env bash
set -euo pipefail

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# GitHub repository for updates
GITHUB_REPO="https://github.com/xGhst0/AI"
FEATURE_BASE="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main"

# Install pathing
INSTALL_DIR="$HOME/.ai_cli_offline"
VENV_DIR="$INSTALL_DIR/venv"
MODEL_DIR="$INSTALL_DIR/models"
MODEL_NAME="TheBloke/Mistral-7B-Instruct-v0.1-GGUF"
MODEL_CACHE="$HOME/.cache/huggingface/hub"

function log() { echo -e "${YELLOW}[INFO]${NC} $1"; }
function success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
function error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Root check
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root."
  exit 1
fi

log "Starting AI CLI environment installation."

# Update system
log "Updating system packages..."
apt-get update -y && apt-get upgrade -y || log "System update failed, continuing."

# Install base dependencies
log "Installing system dependencies..."
apt-get install -y python3 python3-venv python3-pip git curl wget build-essential ca-certificates unzip jq || error "Failed to install dependencies."

# Prepare directories
mkdir -p "$INSTALL_DIR" "$MODEL_DIR"

# Create virtual environment
log "Creating isolated Python virtual environment..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Upgrade pip inside venv
log "Upgrading pip and tools..."
pip install --upgrade pip setuptools wheel || log "Pip upgrade failed."

# Install Python AI packages
log "Installing Python AI packages..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu || pip install torch torchvision torchaudio

pip install transformers accelerate bitsandbytes huggingface-hub sentence-transformers chromadb langchain tiktoken autogen-core wikipedia beautifulsoup4 duckduckgo-search pipx

# Install crewai without extras (tools not supported in 0.1.0)
pip install crewai==0.1.0 || log "CrewAI install failed."

# Cache the model
log "Downloading and caching model..."
python3 - << PYTHON
from huggingface_hub import snapshot_download
try:
  snapshot_download(repo_id="$MODEL_NAME")
except Exception as e:
  print(f"[ERROR] Model download failed: {e}")
PYTHON

# Create CLI wrapper
CLI_BIN="/usr/local/bin/ai"
log "Creating CLI at $CLI_BIN"
cat << 'EOF' > "$CLI_BIN"
#!/usr/bin/env bash
PROMPT="$*"
VENV="$HOME/.ai_cli_offline/venv"
source "$VENV/bin/activate"
python3 - << PY
from transformers import pipeline
model = pipeline("text-generation", model="$MODEL_NAME", device_map="auto", trust_remote_code=True)
output = model("$PROMPT", max_new_tokens=300)[0]['generated_text']
print(output)
PY
EOF
chmod +x "$CLI_BIN"

# Apply update feature script dynamically
function apply_feature_update() {
  FEATURE_NUM="$1"
  FEATURE_URL="$FEATURE_BASE/feature${FEATURE_NUM}.sh"
  TARGET_SCRIPT="$INSTALL_DIR/feature${FEATURE_NUM}.sh"
  log "Downloading feature update #$FEATURE_NUM..."
  if curl -fsSL "$FEATURE_URL" -o "$TARGET_SCRIPT"; then
    chmod +x "$TARGET_SCRIPT"
    log "Running feature update #$FEATURE_NUM..."
    bash "$TARGET_SCRIPT"
    success "Feature update #$FEATURE_NUM applied."
  else
    error "Failed to download feature script from $FEATURE_URL"
  fi
}

# Example usage (remove or extend as needed)
# apply_feature_update 1

# Self test
log "Performing basic CLI test..."
if ai "What is the capital of Australia?" | grep -qi "Canberra"; then
  success "AI CLI is working."
else
  error "AI CLI failed the test."
fi

success "Installation complete. Run 'ai "your question"' to start."
log "Use 'apply_feature_update <number>' to pull new features from GitHub."

exit 0
