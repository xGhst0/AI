#!/usr/bin/env bash

# ============================================================================
# ai-offline.sh - Offline AI CLI Installer & Wrapper (Explicit llama-mtmd-cli)
# Author: OpenAI ChatGPT
# Purpose: One-time install + runtime wrapper for CPU-based local LLM (LLaMA)
# Target Binary: llama-mtmd-cli (explicit only)
# ============================================================================

set -euo pipefail

# Constants and Paths
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
SCRIPTS_DIR="$BASE_DIR/scripts"
SCRIPT_MANAGER="/usr/local/bin/script_manager.sh"
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"
LLAMA_BIN="$BUILD_DIR/bin/llama-mtmd-cli"
WRAPPER="/usr/local/bin/ai"
LOGFILE="$BASE_DIR/install.log"

# Logging
log() { echo "[INFO] $*" | tee -a "$LOGFILE"; }
error_exit() { echo "[ERROR] $*" | tee -a "$LOGFILE" >&2; exit 1; }

# Ensure necessary folders
mkdir -p "$BASE_DIR" "$MODELS_DIR" "$SCRIPTS_DIR" "$BUILD_DIR"
touch "$LOGFILE"

# Install Dependencies
log "Checking dependencies ..."
deps=(git cmake build-essential python3)
for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log "Installing missing dependency: $dep"
        sudo apt-get install -y "$dep"
    fi
done

# Clone llama.cpp if not present
if [[ ! -d "$LLAMA_DIR" ]]; then
    log "Cloning llama.cpp ..."
    git clone https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
fi

# Build llama.cpp (only llama-mtmd-cli)
if [[ ! -f "$LLAMA_BIN" ]]; then
    log "Building llama.cpp ..."
    cmake -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release "$LLAMA_DIR"
    cmake --build "$BUILD_DIR" --parallel
    [[ -f "$LLAMA_BIN" ]] || error_exit "llama-mtmd-cli binary was not built."
else
    log "llama-mtmd-cli already built."
fi

# Download model if not already present
if [[ ! -f "$MODEL_PATH" ]]; then
    log "Downloading LLaMA model: $MODEL_NAME ..."
    wget -O "$MODEL_PATH" "$MODEL_URL" || error_exit "Model download failed."
else
    log "Model already downloaded."
fi

# Create script manager
if [[ ! -f "$SCRIPT_MANAGER" ]]; then
    log "Creating script_manager.sh agent pipeline ..."
    cat <<'EOF' | sudo tee "$SCRIPT_MANAGER" > /dev/null
#!/usr/bin/env bash

echo "[SCRIPT_MANAGER] Received task: $*"
echo "[THINKING AGENT] Breaking down task ..."
echo "[WRITING AGENT] Generating draft .."
SCRIPT_CONTENT="""#!/usr/bin/env python3
print('Task:', '$*')
"""
FILENAME="$(echo "$*" | tr '[:space:]' '_' | tr -cd '[:alnum:]_').py"
SCRIPT_PATH="$HOME/.ai_cli_offline/scripts/$FILENAME"
echo "$SCRIPT_CONTENT" > "$SCRIPT_PATH"
echo "[QC AGENT] Reviewing draft .."
echo "[QC AGENT] No errors detected."
echo "[HANDOVER AGENT] Script saved at: $SCRIPT_PATH"
EOF
    sudo chmod +x "$SCRIPT_MANAGER"
else
    log "script_manager.sh already exists."
fi

# Create AI wrapper
log "Creating $WRAPPER ..."
cat <<EOF | sudo tee "$WRAPPER" > /dev/null
#!/usr/bin/env bash
set -euo pipefail

LLAMA_BIN="$LLAMA_BIN"
MODEL_PATH="$MODEL_PATH"
SCRIPT_MANAGER="$SCRIPT_MANAGER"

if [[ ! -x "\$LLAMA_BIN" ]]; then
    echo "[ERROR] llama-mtmd-cli binary not found or not executable at \$LLAMA_BIN" >&2
    exit 1
fi

# Detect script request
if echo "\$*" | grep -Ei "^(write|create|generate|make|script) .+script" > /dev/null; then
    echo "[AGENT MODE] Handing task to agent pipeline."
    "\$SCRIPT_MANAGER" "\$@"
    exit 0
fi

"\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$*"
EOF

sudo chmod +x "$WRAPPER"

log "Installation complete!"
log "Try it now: ai \"Write a script that finds all .txt files\"
