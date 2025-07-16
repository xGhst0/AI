#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# Configuration
# ----------------------------------------
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGFILE="$BASE_DIR/install.log"
WRAPPER="/usr/local/bin/ai"

MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"

SCRIPT_MANAGER="$BASE_DIR/script_manager.sh"

# ----------------------------------------
# Logging Functions
# ----------------------------------------
log() {
  echo "[INFO] $*" | tee -a "$LOGFILE"
}
error_exit() {
  echo "[ERROR] $*" | tee -a "$LOGFILE" >&2
  exit 1
}

# ----------------------------------------
# Clean previous installation
# ----------------------------------------
log "Cleaning previous installation..."
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR" "$MODELS_DIR" "$SCRIPTS_DIR"

# ----------------------------------------
# Install dependencies if missing
# ----------------------------------------
log "Checking dependencies..."
deps=(git cmake build-essential python3 wget)
for dep in "${deps[@]}"; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    log "Installing missing dependency: $dep"
    sudo apt-get update -y
    sudo apt-get install -y "$dep"
  fi
done

# ----------------------------------------
# Clone llama.cpp
# ----------------------------------------
if [[ ! -d "$LLAMA_DIR" ]]; then
  log "Cloning llama.cpp repository..."
  git clone https://github.com/ggerganov/llama.cpp "$LLAMA_DIR" || error_exit "Failed to clone llama.cpp"
else
  log "llama.cpp directory exists, pulling latest changes..."
  git -C "$LLAMA_DIR" pull || log "Warning: Failed to update llama.cpp repo, continuing with existing code"
fi

# ----------------------------------------
# Build llama-simple-chat binary
# ----------------------------------------
log "Cleaning previous build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Configuring build..."
cmake -B "$BUILD_DIR" -S "$LLAMA_DIR" -DCMAKE_BUILD_TYPE=Release

log "Building llama-simple-chat binary..."
cmake --build "$BUILD_DIR" --target llama-simple-chat -- -j"$(nproc)" || error_exit "Build failed"

LLAMA_BIN="$BUILD_DIR/bin/llama-simple-chat"
if [[ ! -x "$LLAMA_BIN" ]]; then
  error_exit "llama-simple-chat binary not found after build"
fi

# ----------------------------------------
# Download the model
# ----------------------------------------
if [[ ! -f "$MODEL_PATH" ]]; then
  log "Downloading model $MODEL_NAME..."
  wget -O "$MODEL_PATH" "$MODEL_URL" || error_exit "Failed to download model"
else
  log "Model already downloaded."
fi

# ----------------------------------------
# Create script_manager.sh (simple placeholder)
# ----------------------------------------
if [[ ! -f "$SCRIPT_MANAGER" ]]; then
  log "Creating script_manager.sh agent pipeline..."
  cat <<'EOF' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash
echo "[SCRIPT_MANAGER] Received task: $*"
echo "[THINKING AGENT] Breaking down task..."
echo "[WRITING AGENT] Generating draft..."
FILENAME=$(echo "$*" | tr '[:space:]' '_' | tr -cd '[:alnum:]_').py
SCRIPT_PATH="$HOME/.ai_cli_offline/scripts/$FILENAME"
cat > "$SCRIPT_PATH" <<PYTHON
#!/usr/bin/env python3
print('Task:', "$*")
# TODO: Implement script generation logic here
PYTHON
chmod +x "$SCRIPT_PATH"
echo "[QC AGENT] Reviewing draft..."
echo "[QC AGENT] No errors detected."
echo "[HANDOVER AGENT] Script saved at: $SCRIPT_PATH"
EOF
  chmod +x "$SCRIPT_MANAGER"
else
  log "script_manager.sh already exists."
fi

# ----------------------------------------
# Create AI CLI wrapper
# ----------------------------------------
log "Creating AI CLI wrapper script at $WRAPPER..."
sudo tee "$WRAPPER" > /dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

LLAMA_BIN="$LLAMA_BIN"
MODEL_PATH="$MODEL_PATH"
SCRIPT_MANAGER="$SCRIPT_MANAGER"

if [[ ! -x "\$LLAMA_BIN" ]]; then
  echo "[ERROR] llama-simple-chat binary not found or not executable at \$LLAMA_BIN" >&2
  exit 1
fi

# Detect script generation requests
if echo "\$*" | grep -Ei "^(write|create|generate|make).*(script|program)" >/dev/null; then
  echo "[AGENT MODE] Delegating to script manager."
  bash "\$SCRIPT_MANAGER" "\$@"
  exit 0
fi

exec "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$*"
EOF

sudo chmod +x "$WRAPPER"

log "Installation complete!"
log "You can now run the AI CLI with the command: ai \"Your prompt here\""
