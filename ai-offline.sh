#!/usr/bin/env bash
set -euo pipefail

### === VERSION === ###
echo 'Script v3.0'

# ========== CONFIGURATION ==========
INSTALL_DIR="$HOME/.ai_cli_offline"
MODEL_DIR="$INSTALL_DIR/models"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"
AI_WRAPPER="/usr/local/bin/ai"
INSTALLER_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
TMP_UPDATE="$INSTALL_DIR/ai-offline.sh.tmp"
DISK_REQUIRED_GB=10
LOG_FILE="$INSTALL_DIR/conversation.txt"

# ========== EMOJI CONSTANTS ==========
EMOJI_INFO="[\033[1;34mℹ️\033[0m]"
EMOJI_WARN="[\033[1;33m⚠️\033[0m]"
EMOJI_SUCCESS="[\033[1;32m✅\033[0m]"
EMOJI_ERROR="[\033[1;31m❌\033[0m]"

# ========== ECHO WRAPPERS ==========
log_info()    { echo -e "${EMOJI_INFO} $1"; }
log_warn()    { echo -e "${EMOJI_WARN} $1"; }
log_success() { echo -e "${EMOJI_SUCCESS} $1"; }
log_error()   { echo -e "${EMOJI_ERROR} $1"; }

# ========== UPDATE MODE ==========
if [[ "${1:-}" == "--update" ]]; then
  log_info "Checking for installer updates..."
  mkdir -p "$INSTALL_DIR"
  if curl -fsSL "$INSTALLER_URL" -o "$TMP_UPDATE"; then
    if ! cmp -s "$0" "$TMP_UPDATE"; then
      log_info "Update found, applying..."
      mv "$TMP_UPDATE" "$0" 2>/dev/null || sudo mv "$TMP_UPDATE" "$0"
      log_success "Updated. Re-run script."
      exit 0
    fi
  fi
  exit 0
fi

# ========== DISK CHECK ==========
log_info "Ensuring >=${DISK_REQUIRED_GB}GB free..."
FREE_GB=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
(( FREE_GB < DISK_REQUIRED_GB )) && { log_error "Need ${DISK_REQUIRED_GB}GB, have ${FREE_GB}GB"; exit 1; }
log_success "Disk space OK: ${FREE_GB}GB free"

# ========== MODEL SELECTION ==========
log_info "Select model to install:"
echo "1) 🧠 LLaMA 2 7B Chat"
echo "2) 💬 Mistral 7B Instruct"
echo "3) 🦊 Zephyr 7B"
read -rp "Choice [1-3]: " MODEL_CHOICE
case "$MODEL_CHOICE" in
  1) MODEL_URL="https://huggingface.co/TheBloke/LLaMA-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf"; MODEL_FILE="llama-2-7b-chat.Q4_K_M.gguf";;
  2) MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"; MODEL_FILE="mistral-7b-instruct-v0.1.Q4_K_M.gguf";;
  3) MODEL_URL="https://huggingface.co/HuggingFaceH4/zephyr-7b-beta-GGUF/resolve/main/zephyr-7b-beta.Q4_K_M.gguf"; MODEL_FILE="zephyr-7b-beta.Q4_K_M.gguf";;
  *) log_error "Invalid choice"; exit 1;;
esac

# ========== PREPARE ==========
mkdir -p "$MODEL_DIR" && touch "$LOG_FILE"

# ========== SYSTEM DEPENDENCIES ==========
log_info "Installing dependencies..."
sudo apt-get update -qq && sudo apt-get install -y -qq cmake build-essential curl python3-venv python3-dev git >/dev/null
log_success "Dependencies installed"

# ========== TRY GPT4ALL ==========
BACKEND_DIR="$INSTALL_DIR/gpt4all"
if [[ -d "$BACKEND_DIR" ]]; then rm -rf "$BACKEND_DIR"; fi
log_info "Cloning gpt4all..."
if git clone --depth 1 https://github.com/nomic-ai/gpt4all.git "$BACKEND_DIR" && cd "$BACKEND_DIR" && cmake . && make -j$(nproc); then
  log_success "gpt4all built"
  BACKEND_BIN="$BACKEND_DIR/build/bin/gpt4all"
  BACKEND_CMD=("$BACKEND_BIN" --model-path "$MODEL_DIR/$MODEL_FILE" --prompt)
else
  log_warn "gpt4all build failed, falling back to llama.cpp"
  rm -rf "$BACKEND_DIR"
  # Build llama.cpp
  LLAMA_DIR="$INSTALL_DIR/llama.cpp"
  log_info "Cloning llama.cpp..."
  git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
  mkdir -p "$LLAMA_DIR/build" && cd "$LLAMA_DIR/build"
  cmake .. -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF && make -j$(nproc)
  log_success "llama.cpp built"
  BACKEND_BIN="$LLAMA_DIR/build/bin/llama-simple-chat"
  BACKEND_CMD=("$BACKEND_BIN" -m "$MODEL_DIR/$MODEL_FILE" -p)
fi

# ========== DOWNLOAD MODEL ==========
if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
  log_info "Downloading model..."
  curl -fSL "$MODEL_URL" -o "$MODEL_DIR/$MODEL_FILE" || { wget -q "$MODEL_URL" -O "$MODEL_DIR/$MODEL_FILE"; }
  log_success "Model downloaded"
else
  log_warn "Model exists, skipping"
fi

# ========== SCRIPT MANAGER ==========
cat << 'EOF' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash
PROMPT="$*"
echo "[SCRIPT MANAGER] \$PROMPT"
# custom logic
EOF
chmod +x "$SCRIPT_MANAGER"
log_success "Script manager created"

# ========== WRAPPER ==========
cat << EOF > wrapper.sh
#!/usr/bin/env bash
set -euo pipefail
# log and dispatch
PROMPT="\$*"
echo "\$PROMPT" >> "$LOG_FILE"
LAST=\$(tail -n1 "$LOG_FILE")
if echo "\$LAST" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
  bash "$SCRIPT_MANAGER" "\$LAST"
else
  "${BACKEND_CMD[@]}" "\$LAST"
fi
EOF
sudo mv wrapper.sh "$AI_WRAPPER" && sudo chmod +x "$AI_WRAPPER"
log_success "Wrapper installed at $AI_WRAPPER"

log_success "Installation v2.9 complete"
exit 0
