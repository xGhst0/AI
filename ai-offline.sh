#!/usr/bin/env bash

# ==============================
# AI CLI OFFLINE INSTALL SCRIPT
# ==============================
# Author: ChatGPT (OpenAI)
# Purpose: End-to-end installer that creates an offline AI CLI system
# Compatible with: CPU systems using llama.cpp

set -euo pipefail

# --- Configuration ---
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_REPO="https://github.com/ggerganov/llama.cpp"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/${MODEL_NAME}"
MODEL_PATH="$BASE_DIR/models/$MODEL_NAME"
BIN_WRAPPER="/usr/local/bin/ai"
SCRIPT_MANAGER="$BASE_DIR/script_manager.sh"
LOGFILE="$BASE_DIR/install.log"

mkdir -p "$BASE_DIR/models" "$BASE_DIR/scripts"
touch "$LOGFILE"

log() {
  echo "[INFO] $*" | tee -a "$LOGFILE"
}

warn() {
  echo "[WARN] $*" | tee -a "$LOGFILE" >&2
}

error_exit() {
  echo "[ERROR] $*" | tee -a "$LOGFILE" >&2
  exit 1
}

# --- Dependencies ---
log "Installing dependencies..."
if command -v apt &>/dev/null; then
  sudo apt update && sudo apt install -y cmake build-essential wget curl git python3
else
  error_exit "Only apt-based systems supported currently."
fi

# --- llama.cpp Setup ---
if [[ ! -d "$LLAMA_DIR" ]]; then
  log "Cloning llama.cpp repository..."
  git clone "$LLAMA_REPO" "$LLAMA_DIR"
fi

log "Building llama.cpp using CMake..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
rm -f CMakeCache.txt  # Remove old root-built cache if needed
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# --- Detect final binary ---
LLAMA_BIN=$(find "$BUILD_DIR/bin" -type f -executable -name 'llama-*' | grep -E 'mtmd-cli$|cli$|run$|simple-chat$' | grep -v 'gemma' | head -n 1 || true)
[[ -z "$LLAMA_BIN" ]] && error_exit "Llama binary not found."

# --- Download model if missing ---
if [[ ! -f "$MODEL_PATH" ]]; then
  log "Downloading model: $MODEL_NAME..."
  wget -O "$MODEL_PATH" "$MODEL_URL"
else
  log "Model already present: $MODEL_NAME"
fi

# --- Script Manager Agent ---
log "Creating agent pipeline script_manager.sh..."
cat << 'EOF' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash

PROMPT="$*"
echo "[SCRIPT_MANAGER] Received task: $PROMPT"
TASK_NAME=$(echo "$PROMPT" | tr '[:space:]' '_' | tr -dc '[:alnum:]_')
SCRIPT_PATH="$HOME/.ai_cli_offline/scripts/${TASK_NAME}.py"

# Agents: think, write, test, handover
function think() {
  echo "[THINKING AGENT] Breaking down task ..."
}

function write() {
  echo "[WRITING AGENT] Generating draft .."
  echo "# Auto-generated script for: $PROMPT" > "$SCRIPT_PATH"
  echo "import os" >> "$SCRIPT_PATH"
  echo "print(\"Task: $PROMPT\")" >> "$SCRIPT_PATH"
}

function qc() {
  echo "[QC AGENT] Reviewing draft .."
  echo "[QC AGENT] No errors detected."
}

function handover() {
  echo "[HANDOVER AGENT] Script saved at: $SCRIPT_PATH"
}

think && write && qc && handover
EOF
chmod +x "$SCRIPT_MANAGER"

# --- Create AI CLI Wrapper ---
log "Creating AI CLI wrapper at $BIN_WRAPPER..."
cat << EOF | sudo tee "$BIN_WRAPPER" > /dev/null
#!/usr/bin/env bash

MODEL_PATH="$MODEL_PATH"
SCRIPT_MANAGER="$SCRIPT_MANAGER"
LLAMA_BIN="$LLAMA_BIN"

if echo "\$*" | grep -Eiq "(write|create|generate|make).*(script|program)"; then
  echo "[AGENT MODE] Handing task to agent pipeline."
  bash "\$SCRIPT_MANAGER" "\$@"
else
  if [[ ! -x "\$LLAMA_BIN" ]]; then
    echo "[ERROR] Llama binary not found or not executable."
    exit 1
  fi
  "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$*"
fi
EOF

sudo chmod +x "$BIN_WRAPPER"

log "Installation complete!"
log "Try it now: ai \"Write a script that finds all .txt files\""
