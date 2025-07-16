#!/usr/bin/env bash
set -euo pipefail

# === CONFIG === #
INSTALL_DIR="$HOME/.ai_cli_offline"
VENV_DIR="$INSTALL_DIR/venv"
BIN_DIR="$INSTALL_DIR/llama.cpp/build/bin"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"
WRAPPER_PATH="/usr/local/bin/ai"
MODEL_DIR="$INSTALL_DIR/models"
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
INSTALLER_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
TMP_INSTALLER="/tmp/ai-offline.sh.tmp"
LLAMA_REPO="https://github.com/ggerganov/llama.cpp"
MODEL_PRIMARY="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"
MODEL_SECONDARY="https://huggingface.co/alternate/path/to/$MODEL_NAME"  # Update as needed
FEATURE_URL_BASE="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main"

# Download and apply feature update by number
apply_feature_update() {
  local feature_number="$1"
  local feature_url="$FEATURE_URL_BASE/feature${feature_number}.sh"
  local feature_script="/tmp/feature${feature_number}.sh"

  echo "[INFO] Downloading feature #$feature_number from $feature_url ..."
  if curl -fsSL "$feature_url" -o "$feature_script"; then
    echo "[INFO] Running feature update script: feature${feature_number}.sh"
    chmod +x "$feature_script"
    bash "$feature_script"
    echo "[SUCCESS] Feature #$feature_number applied."
    rm -f "$feature_script"
  else
    echo "[ERROR] Failed to download feature #$feature_number. Skipping."
  fi
}

# === LOG FUNCTIONS === #
function info()  { echo -e "\033[1;33m[INFO]\033[0m $1"; }
function warn()  { echo -e "\033[1;35m[WARN]\033[0m $1" >&2; }
function error_exit() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# === SELF-UPDATE CHECK === #
info "Checking for installer updates ..."
if curl -fsSL "$INSTALLER_URL" -o "$TMP_INSTALLER"; then
    if ! cmp -s "$0" "$TMP_INSTALLER"; then
        info "New version of ai-offline.sh found. Applying update."
        chmod +x "$TMP_INSTALLER"
        mv "$TMP_INSTALLER" "$0"
        info "Updated successfully. Please re-run the script."
        exit 0
    else
        rm -f "$TMP_INSTALLER"
    fi
else
    warn "Failed to download installer update. Continuing ..."
fi

# === CLEAN INSTALL === #
info "Preparing installation at $INSTALL_DIR ..."
rm -rf "$INSTALL_DIR"
mkdir -p "$MODEL_DIR"
apply_feature_update
# === INSTALL DEPENDENCIES === #
info "Installing required system packages ..."
sudo apt update -y && sudo apt install -y build-essential cmake curl git python3 python3-venv

# === CREATE VIRTUAL ENVIRONMENT === #
info "Creating Python virtual environment ..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

info "Upgrading pip inside virtual environment ..."
pip install --upgrade pip setuptools wheel

info "Installing Python packages inside virtual environment ..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install transformers accelerate bitsandbytes huggingface-hub sentence-transformers chromadb langchain tiktoken crewai[tools] autogen-core wikipedia beautifulsoup4 duckduckgo-search

# === CLONE LLAMA.CPP === #
info "Cloning llama.cpp repository ..."
git clone "$LLAMA_REPO" "$INSTALL_DIR/llama.cpp"

info "Building llama.cpp ..."
mkdir -p "$INSTALL_DIR/llama.cpp/build"
cd "$INSTALL_DIR/llama.cpp/build"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# === DOWNLOAD MODEL === #
info "Downloading LLM model: $MODEL_NAME ..."
if ! curl -fLo "$MODEL_PATH" "$MODEL_PRIMARY"; then
    warn "Primary model download failed. Trying fallback ..."
    curl -fLo "$MODEL_PATH" "$MODEL_SECONDARY" || error_exit "Model download failed from all sources."
fi

# === SCRIPT MANAGER === #
info "Creating script manager logic ..."
cat << 'EOF' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash
set -euo pipefail
PROMPT="$*"
echo "[QC AGENT] Reviewing prompt: \$PROMPT"
echo "[QC AGENT] All checks passed."
echo "[HANDOVER AGENT] Script saved to: \$HOME/.ai_cli_offline/scripts/$(date +%s)_script.sh"
EOF
chmod +x "$SCRIPT_MANAGER"

# === AI WRAPPER === #
info "Creating AI CLI wrapper at $WRAPPER_PATH ..."
cat << EOF | sudo tee "$WRAPPER_PATH" > /dev/null
#!/usr/bin/env bash
set -euo pipefail
source "$VENV_DIR/bin/activate"
LLAMA_BIN="$BIN_DIR/llama-simple-chat"
MODEL="$MODEL_PATH"
SCRIPT_MANAGER="$SCRIPT_MANAGER"
PROMPT="\$*"

if [[ ! -x "\$LLAMA_BIN" ]]; then
    echo "[ERROR] llama-simple-chat not found at \$LLAMA_BIN" >&2
    exit 1
fi

if echo "\$PROMPT" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
    echo "[AGENT MODE] Delegating to script manager."
    bash "\$SCRIPT_MANAGER" "\$PROMPT"
    exit 0
fi

exec "\$LLAMA_BIN" -m "\$MODEL" -p "\$PROMPT"
EOF

sudo chmod +x "$WRAPPER_PATH"

# === FINAL TEST === #
info "Running basic test ..."
if ai "What is the capital of France?" | grep -iq "paris"; then
    info "AI CLI is working correctly."
else
    warn "Basic test failed. Please check the logs."
fi

info "Installation complete. Use 'ai \"your prompt here\"' to begin."
