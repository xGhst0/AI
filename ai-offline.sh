#!/usr/bin/env bash

# Constants
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGFILE="$BASE_DIR/ai.log"
SCRIPT_MANAGER="/usr/local/bin/script_manager.sh"
LLAMA_BIN=""
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"

# Create necessary directories
mkdir -p "$BUILD_DIR" "$MODELS_DIR" "$SCRIPTS_DIR"
touch "$LOGFILE"

# Logging functions
log() { echo "[INFO] $*" | tee -a "$LOGFILE"; }
warn() { echo "[WARN] $*" | tee -a "$LOGFILE" >&2; }
error_exit() { echo "[ERROR] $*" | tee -a "$LOGFILE" >&2; exit 1; }

# Find the correct llama binary
resolve_llama_binary() {
  local candidates=("llama-mtmd-cli" "llama-cli" "llama-run" "llama-simple-chat")
  for bin in "${candidates[@]}"; do
    found_bin=$(find "$BUILD_DIR/bin" -type f -executable -name "$bin" 2>/dev/null | head -n 1)
    if [[ -x "$found_bin" ]]; then
      LLAMA_BIN="$found_bin"
      log "Using binary: $LLAMA_BIN"
      return
    fi
  done
  error_exit "No suitable llama binary found."
}

# Validate model file
validate_model() {
  if [[ ! -f "$MODEL_PATH" ]]; then
    log "Downloading model $MODEL_NAME ..."
    curl -L "$MODEL_URL" -o "$MODEL_PATH" || error_exit "Model download failed."
  else
    log "Model already exists at $MODEL_PATH"
  fi
}

# Handle agent-based scripting prompts
is_script_task() {
  echo "$*" | grep -Ei "^(write|create|generate|make).*script" > /dev/null
}

# Install script manager if missing
install_script_manager() {
  if [[ ! -f "$SCRIPT_MANAGER" ]]; then
    cat << 'EOF' | sudo tee "$SCRIPT_MANAGER" > /dev/null
#!/usr/bin/env bash
# Dummy script manager logic for demonstration
prompt="$*"
echo "[SCRIPT_MANAGER] Received task: $prompt"
echo "[THINKING AGENT] Breaking down task ..."
echo "[WRITING AGENT] Generating draft .."
echo "[QC AGENT] Reviewing draft ..."
echo "[QC AGENT] No errors detected."
filename="$HOME/.ai_cli_offline/scripts/$(echo "$prompt" | tr ' ' '_' | tr -cd '[:alnum:]_').py"
echo "# Auto-generated script" > "$filename"
echo "print('Task: $prompt')" >> "$filename"
echo "[HANDOVER AGENT] Script saved at: $filename"
EOF
    sudo chmod +x "$SCRIPT_MANAGER"
    log "Script manager installed."
  fi
}

# Entry point
main() {
  [[ $# -eq 0 ]] && { echo "Usage: ai \"your prompt here\""; exit 1; }
  resolve_llama_binary
  validate_model
  install_script_manager

  if is_script_task "$@"; then
    echo "[AGENT MODE] Detected script generation task. Handing over to agent pipeline ..."
    "$SCRIPT_MANAGER" "$@"
    exit
  fi

  log "Running prompt via Llama ..."
  "$LLAMA_BIN" -m "$MODEL_PATH" -p "$*"
}

main "$@"
