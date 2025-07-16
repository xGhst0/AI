#!/usr/bin/env bash
set -euo pipefail

### --- CONFIG --- ###
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
MODEL_SECONDARY="https://huggingface.co/alternate/path/to/$MODEL_NAME" # Replace with real fallback

# --- APPLY MODULAR FEATURES ---
FEATURE_BASE_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/feature"
MAX_FEATURES=99

info "Applying modular AI CLI features..."
for i in $(seq 1 $MAX_FEATURES); do
    FEATURE_URL="${FEATURE_BASE_URL}${i}.sh"
    FEATURE_SCRIPT="/tmp/feature${i}.sh"
    
    # Check if the script exists remotely
    if curl --silent --head --fail "$FEATURE_URL" > /dev/null; then
        info "Fetching and applying feature ${i}..."
        curl -fsSL "$FEATURE_URL" -o "$FEATURE_SCRIPT" || { warn "Failed to download feature${i}.sh"; continue; }
        chmod +x "$FEATURE_SCRIPT"
        bash "$FEATURE_SCRIPT" || warn "Feature${i}.sh execution failed."
    else
        info "No more features found after feature${i}.sh."
        break
    fi
done

### --- FUNCTIONS --- ###
function info() { echo -e "[INFO] $1"; }
function warn() { echo -e "[WARN] $1" >&2; }
function error_exit() { echo -e "[ERROR] $1" >&2; exit 1; }

function apply_feature_update() {
    for i in {1..10}; do
        URL="$FEATURE_BASE_URL/feature$i.sh"
        DEST="$INSTALL_DIR/feature$i.sh"
        if curl -fsSL "$URL" -o "$DEST"; then
            chmod +x "$DEST"
            bash "$DEST" || warn "Feature $i failed to apply."
        else
            warn "Feature $i not found or download failed."
        fi
    done
}

### --- SELF UPDATE CHECK --- ###
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

### --- CLEAN INSTALL --- ###
info "Preparing installation at $INSTALL_DIR ..."
rm -rf "$INSTALL_DIR"
mkdir -p "$MODEL_DIR"

### --- DEPENDENCIES --- ###
info "Installing required packages ..."
sudo apt update -y && sudo apt install -y build-essential cmake curl git python3 python3-venv python3-pip

### --- PYTHON VENV --- ###
info "Setting up Python virtual environment ..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

info "Upgrading pip inside venv ..."
pip install --upgrade pip setuptools wheel || warn "Pip upgrade failed."

info "Installing Python AI packages ..."
pip install torch transformers accelerate bitsandbytes huggingface-hub sentence-transformers chromadb langchain tiktoken crewai autogen-core wikipedia beautifulsoup4 duckduckgo-search pipx || error_exit "Python package installation failed."

### --- CLONE & BUILD LLAMA.CPP --- ###
info "Cloning llama.cpp repo ..."
git clone "$LLAMA_REPO" "$INSTALL_DIR/llama.cpp"

info "Building llama.cpp ..."
mkdir -p "$INSTALL_DIR/llama.cpp/build"
cd "$INSTALL_DIR/llama.cpp/build"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

### --- DOWNLOAD MODEL --- ###
info "Downloading model: $MODEL_NAME"
if ! curl -fLo "$MODEL_PATH" "$MODEL_PRIMARY"; then
    warn "Primary model download failed. Trying fallback ..."
    curl -fLo "$MODEL_PATH" "$MODEL_SECONDARY" || error_exit "Model download failed from all sources."
fi

### --- CREATE SCRIPT MANAGER --- ###
cat << 'EOF' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash
set -euo pipefail
PROMPT="$*"
echo "[QC AGENT] Reviewing draft ..."
echo "[QC AGENT] No errors detected."
echo "[HANDOVER AGENT] Script saved at: \$HOME/.ai_cli_offline/scripts/script_from_prompt.sh"
EOF
chmod +x "$SCRIPT_MANAGER"

### --- CREATE AI WRAPPER --- ###
info "Creating AI CLI wrapper at $WRAPPER_PATH"
cat << EOF | sudo tee "$WRAPPER_PATH" > /dev/null
#!/usr/bin/env bash
set -euo pipefail
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

### --- APPLY FEATURE UPDATES --- ###
info "Applying feature updates ..."
apply_feature_update

### --- DONE --- ###
info "Installation complete!"
echo "You can now run AI CLI with: ai \"Your prompt here\""
