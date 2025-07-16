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
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
INSTALL_SCRIPT_LOCAL="$BASE_DIR/ai-offline.sh"

MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"
LLAMA_BINARY_NAME="llama-simple-chat"
LLAMA_BIN="$BUILD_DIR/bin/$LLAMA_BINARY_NAME"

# === Functions ===

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
    log "Installing missing dependencies: ${missing[*]}"
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
  if [ ! -f "$SCRIPT_MANAGER" ]; then
    log "Creating stub script_manager.sh..."
    cat > "$SCRIPT_MANAGER" <<'EOF'
#!/usr/bin/env bash
echo "[SCRIPT_MANAGER] Received task: $*"
# Placeholder multi-agent logic
echo "Stub: no script generation implemented."
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

# === Variables ===
LLAMA_BIN="$LLAMA_BIN"
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"
SCRIPT_MANAGER="$SCRIPT_MANAGER"

UPDATE_CHECK_URL="$INSTALL_SCRIPT_URL"
INSTALL_SCRIPT_LOCAL="$INSTALL_SCRIPT_LOCAL"

check_for_update() {
  # Download remote install script to temp file
  TMP_UPDATE="\$(mktemp)"
  if curl -sSfL "\$UPDATE_CHECK_URL" -o "\$TMP_UPDATE"; then
    if ! cmp -s "\$TMP_UPDATE" "\$INSTALL_SCRIPT_LOCAL"; then
      echo "[UPDATE] New version of install script available."
      read -rp "Update install script now? [Y/n]: " resp
      resp=\${resp:-Y}
      if [[ "\$resp" =~ ^[Yy]$ ]]; then
        cp "\$TMP_UPDATE" "\$INSTALL_SCRIPT_LOCAL"
        chmod +x "\$INSTALL_SCRIPT_LOCAL"
        echo "[UPDATE] Install script updated. Please rerun it manually to update your AI CLI."
      else
        echo "[UPDATE] Update skipped by user."
      fi
    fi
  else
    echo "[UPDATE] Could not check for updates."
  fi
  rm -f "\$TMP_UPDATE"
}

# Run update check in background to avoid delaying prompt (optional)
check_for_update &

if [[ ! -x "\$LLAMA_BIN" ]]; then
  echo "[ERROR] llama-simple-chat binary not found or not executable at \$LLAMA_BIN" >&2
  exit 1
fi

if [[ ! -f "\$MODEL_PATH" ]]; then
  echo "[ERROR] Model file not found at \$MODEL_PATH" >&2
  exit 1
fi

PROMPT="\$*"

# Detect script generation requests
if echo "\$PROMPT" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
  echo "[AGENT MODE] Delegating to script manager."
  bash "\$SCRIPT_MANAGER" "\$PROMPT"
  exit 0
fi

exec "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$PROMPT"
EOF
  sudo chmod +x "$AI_WRAPPER"
  log "AI CLI wrapper script created."
}

self_heal() {
  log "Starting self-healing checks..."

  # Check repo presence
  if [ ! -d "$LLAMA_DIR" ]; then
    warn "llama.cpp directory missing, recloning..."
    clone_and_build_llama
  fi

  # Check build presence and binary executable
  if [ ! -x "$LLAMA_BIN" ]; then
    warn "llama binary missing or not executable, rebuilding..."
    cd "$BUILD_DIR"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)" || error_exit "Rebuild failed."
  fi

  # Check model presence
  if [ ! -f "$MODELS_DIR/$MODEL_NAME" ]; then
    warn "Model missing, downloading..."
    download_model
  fi

  # Check script_manager.sh presence
  if [ ! -f "$SCRIPT_MANAGER" ]; then
    warn "script_manager.sh missing, recreating stub..."
    create_script_manager
  fi

  # Check AI wrapper presence and content
  if [ ! -x "$AI_WRAPPER" ]; then
    warn "AI wrapper missing or not executable, recreating..."
    create_ai_wrapper
  fi

  log "Self-healing complete."
}

main() {
  mkdir -p "$BASE_DIR" "$MODELS_DIR"

  log "Starting AI CLI offline installation..."

  check_dependencies

  clean_previous_install

  clone_and_build_llama

  download_model

  create_script_manager

  create_ai_wrapper

  log "[DONE] Installation complete!"
  log "Run AI with: ai \"Your prompt here\""
}

# === Entry point ===
if [[ "${1:-}" == "selfheal" ]]; then
  self_heal
else
  main
fi
