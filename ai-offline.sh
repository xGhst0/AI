#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
LOGFILE="$BASE_DIR/install.log"
SCRIPT_MANAGER="$BASE_DIR/script_manager.sh"
AI_WRAPPER="/usr/local/bin/ai"

MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"
LLAMA_BINARY_NAME="llama-mtmd-cli"
LLAMA_BIN="$BUILD_DIR/bin/$LLAMA_BINARY_NAME"

# === Functions ===

log() {
  echo "[INFO] $*" | tee -a "$LOGFILE"
}

error_exit() {
  echo "[ERROR] $*" | tee -a "$LOGFILE" >&2
  exit 1
}

check_dependencies() {
  log "Checking dependencies..."
  local deps=(git cmake build-essential libcurl4-openssl-dev libomp-dev curl)
  local missing=()
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log "Missing dependencies detected: ${missing[*]}"
    sudo apt update
    sudo apt install -y "${missing[@]}"
  else
    log "All dependencies installed."
  fi
}

clean_previous_install() {
  if [ -d "$LLAMA_DIR" ]; then
    log "Removing previous llama.cpp directory..."
    rm -rf "$LLAMA_DIR"
  fi
  if [ -f "$AI_WRAPPER" ]; then
    log "Removing existing AI CLI wrapper at $AI_WRAPPER"
    sudo rm -f "$AI_WRAPPER"
  fi
  mkdir -p "$BASE_DIR"
  mkdir -p "$MODELS_DIR"
}

clone_and_build_llama() {
  log "Cloning llama.cpp repository..."
  git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR" || error_exit "Failed to clone llama.cpp."

  log "Building llama.cpp..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  cmake .. -DCMAKE_BUILD_TYPE=Release
  make -j"$(nproc)" || error_exit "Build failed."
  if [ ! -x "$LLAMA_BIN" ]; then
    error_exit "Expected binary $LLAMA_BIN not found after build."
  fi
  log "llama.cpp built successfully."
}

download_model() {
  if [ -f "$MODELS_DIR/$MODEL_NAME" ]; then
    log "Model $MODEL_NAME already exists, skipping download."
    return
  fi
  log "Downloading model $MODEL_NAME ..."
  curl -L -o "$MODELS_DIR/$MODEL_NAME" "$MODEL_URL" || error_exit "Failed to download model."
  log "Model downloaded successfully."
}

create_script_manager() {
  # Create a simple stub script_manager.sh if not existing
  if [ ! -f "$SCRIPT_MANAGER" ]; then
    log "Creating stub script_manager.sh..."
    cat > "$SCRIPT_MANAGER" <<'EOF'
#!/usr/bin/env bash
echo "[SCRIPT_MANAGER] Received task: $*"
# This is a placeholder. Replace with your multi-agent logic.
echo "Stub: No actual script generation implemented."
EOF
    chmod +x "$SCRIPT_MANAGER"
  else
    log "script_manager.sh already exists, skipping creation."
  fi
}

create_ai_wrapper() {
  log "Creating AI CLI wrapper script at $AI_WRAPPER ..."
  sudo tee "$AI_WRAPPER" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

LLAMA_BIN="$LLAMA_BIN"
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"
SCRIPT_MANAGER="$SCRIPT_MANAGER"

if [[ ! -x "\$LLAMA_BIN" ]]; then
  echo "[ERROR] llama binary not found or not executable at \$LLAMA_BIN" >&2
  exit 1
fi

PROMPT="\$*"

# Detect script generation requests
if echo "\$PROMPT" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
  echo "[AGENT MODE] Delegating to script manager."
  bash "\$SCRIPT_MANAGER" "\$PROMPT"
  exit 0
fi

# Run llama-mtmd-cli with CPU-only options
exec "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$PROMPT" --no-mmproj-offload
EOF
  sudo chmod +x "$AI_WRAPPER"
  log "AI CLI wrapper script created."
}

# === Main installation flow ===

log "Starting AI CLI offline installation..."

check_dependencies

clean_previous_install

clone_and_build_llama

download_model

create_script_manager

create_ai_wrapper

log "[DONE] Installation complete!"
log "Run AI with: ai \"Your prompt here\""
