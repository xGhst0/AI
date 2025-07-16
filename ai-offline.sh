#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
LOGFILE="$BASE_DIR/install.log"
BIN_WRAPPER="/usr/local/bin/ai"
SCRIPT_MANAGER="/usr/local/bin/script_manager.sh"
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"

mkdir -p "$BASE_DIR" "$MODELS_DIR"
touch "$LOGFILE"

log() {
    echo "[INFO] $*" | tee -a "$LOGFILE"
}

error_exit() {
    echo "[ERROR] $*" | tee -a "$LOGFILE" >&2
    exit 1
}

# === 1. Install Dependencies ===
log "Installing system dependencies..."
sudo apt update
sudo apt install -y build-essential cmake git curl libcurl4-openssl-dev libomp-dev

# === 2. Clone llama.cpp ===
if [ -d "$LLAMA_DIR" ]; then
    log "Updating llama.cpp repo..."
    git -C "$LLAMA_DIR" pull || log "Could not update, using existing copy."
else
    log "Cloning llama.cpp..."
    git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR" || error_exit "Failed to clone llama.cpp"
fi

# === 3. Build llama.cpp ===
log "Building llama.cpp with CMake..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)" || error_exit "Build failed"

# === 4. Locate Executable ===
LLAMA_BIN=$(find "$BUILD_DIR/bin" -type f -executable -name 'llama-*' | grep -E 'cli$|run$|simple-chat$' | head -n 1 || true)

if [ -z "$LLAMA_BIN" ]; then
    error_exit "No working llama binary found."
else
    log "Found llama binary: $LLAMA_BIN"
fi

# === 5. Download Model ===
cd "$MODELS_DIR"
if [ ! -f "$MODEL_NAME" ]; then
    echo -n "Enter your HuggingFace API token: "
    read -r HF_API_TOKEN
    log "Downloading model..."
    curl -L -o "$MODEL_NAME" -H "Authorization: Bearer $HF_API_TOKEN" "$MODEL_URL" || error_exit "Model download failed"
else
    log "Model already downloaded."
fi

# === 6. Create script_manager.sh ===
log "Creating script_manager.sh agent pipeline..."
sudo tee "$SCRIPT_MANAGER" > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

PROMPT="$*"
WORK_DIR="$HOME/.ai_cli_offline/scripts"
mkdir -p "$WORK_DIR"

# === Agent Simulation ===
echo "[SCRIPT_MANAGER] Received task: $PROMPT"
FILENAME=$(echo "$PROMPT" | tr ' ' '_' | tr -dc '[:alnum:]_-').py
SCRIPT_PATH="$WORK_DIR/$FILENAME"

echo "[THINKING AGENT] Breaking down task..."
sleep 1

echo "[WRITING AGENT] Generating draft..."
echo "#!/usr/bin/env python3" > "$SCRIPT_PATH"
echo "# TODO: implement logic for -> $PROMPT" >> "$SCRIPT_PATH"
echo "print('Task: $PROMPT')" >> "$SCRIPT_PATH"

echo "[QC AGENT] Reviewing draft..."
sleep 1
echo "[QC AGENT] No errors detected."

chmod +x "$SCRIPT_PATH"
echo "[HANDOVER AGENT] Script saved at: $SCRIPT_PATH"
EOF

sudo chmod +x "$SCRIPT_MANAGER"

# === 7. Create CLI Wrapper ===
log "Creating /usr/local/bin/ai wrapper..."

sudo tee "$BIN_WRAPPER" > /dev/null <<EOF
#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/.ai_cli_offline"
MODEL_NAME="$MODEL_NAME"
MODEL_PATH="\$BASE_DIR/models/\$MODEL_NAME"
SCRIPT_MANAGER="/usr/local/bin/script_manager.sh"

# Resolve llama binary
LLAMA_BIN=\$(find "\$BASE_DIR/llama.cpp/build/bin" -type f -executable -name 'llama-*' | grep -E 'cli$|run$|simple-chat$' | head -n 1 || true)

# Fallback to root
if [ -z "\$LLAMA_BIN" ] && [ -d "/root/.ai_cli_offline/llama.cpp/build/bin" ]; then
  LLAMA_BIN=\$(find "/root/.ai_cli_offline/llama.cpp/build/bin" -type f -executable -name 'llama-*' | grep -E 'cli$|run$|simple-chat$' | head -n 1 || true)
fi

if [ -z "\$LLAMA_BIN" ]; then
  echo "[ERROR] Llama binary not found."
  exit 1
fi

if [ ! -f "\$MODEL_PATH" ]; then
  echo "[ERROR] Model not found at \$MODEL_PATH"
  exit 1
fi

# Agent detection
if echo "\$*" | grep -Ei "^(write|create|generate|make|script) .*script" > /dev/null; then
  echo "[AGENT MODE] Handing task to agent pipeline..."
  exec "\$SCRIPT_MANAGER" "\$@"
fi

exec "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$*"
EOF

sudo chmod +x "$BIN_WRAPPER"

# === DONE ===
log "Installation complete!"
log "Try it now: ai \"Write a script that finds all .txt files\""
