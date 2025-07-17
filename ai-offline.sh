#!/usr/bin/env bash
set -euo pipefail

### === VERSION === ###
echo 'Script v3.1'

# ========== CONFIGURATION ==========
INSTALL_DIR="$HOME/.ai_cli_offline"
MODEL_DIR="$INSTALL_DIR/models"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"
AI_WRAPPER="/usr/local/bin/ai"
INSTALLER_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
TMP_UPDATE="$INSTALL_DIR/ai-offline.sh.tmp"
DISK_REQUIRED_GB=10
LOG_FILE="$INSTALL_DIR/conversation.txt"
BACKUP_DIR="$INSTALL_DIR/backups"

# ========== EMOJI CONSTANTS ==========
EMOJI_INFO="[\033[1;34mℹ️\033[0m]"
EMOJI_WARN="[\033[1;33m⚠️\033[0m]"
EMOJI_SUCCESS="[\033[1;32m✅\033[0m]"
EMOJI_ERROR="[\033[1;31m❌\033[0m]"

# ========== ECHO FUNCTIONS ==========
log_info()    { echo -e "${EMOJI_INFO} $1"; }
log_warn()    { echo -e "${EMOJI_WARN} $1"; }
log_success() { echo -e "${EMOJI_SUCCESS} $1"; }
log_error()   { echo -e "${EMOJI_ERROR} $1"; }

# ========== UPDATE CHECK ==========
if [[ "${1:-}" == "--update" ]]; then
  log_info "Checking for installer updates..."
  mkdir -p "$INSTALL_DIR" "$BACKUP_DIR"
  if curl -fsSL "$INSTALLER_URL" -o "$TMP_UPDATE"; then
    if ! cmp -s "$0" "$TMP_UPDATE"; then
      log_info "Update found, backing up current installer"
      cp "$0" "$BACKUP_DIR/installer_$(date +%s).sh"
      log_info "Applying update..."
      mv "$TMP_UPDATE" "$0" 2>/dev/null || sudo mv "$TMP_UPDATE" "$0"
      log_success "Updated. Re-run script."
      exit 0
    fi
  fi
  exit 0
fi

# ========== DISK SPACE CHECK ==========
log_info "Ensuring >=${DISK_REQUIRED_GB}GB free..."
FREE_GB=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
if (( FREE_GB < DISK_REQUIRED_GB )); then
  log_error "Need ${DISK_REQUIRED_GB}GB, have ${FREE_GB}GB"
  exit 1
fi
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

# ========== PREPARE DIRECTORIES ==========
mkdir -p "$MODEL_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

# ========== DEPENDENCIES INSTALLATION ==========
log_info "Installing dependencies..."
sudo apt-get update -qq && sudo apt-get install -y -qq cmake build-essential curl python3-venv python3-dev git python3-pip >/dev/null
log_success "Dependencies installed"

# ========== BACKEND BUILD SEQUENCE ==========
choose_backend() {
  # 1) GPT4All C++
  BACKENDS=(
    "gpt4all.cpp https://github.com/nomic-ai/gpt4all.cpp.git build/bin/gpt4all --model-path"
    "llama.cpp https://github.com/ggerganov/llama.cpp.git build/bin/llama-simple-chat -m"
    "llm pip:llm llm -m"
  )
  for entry in "${BACKENDS[@]}"; do
    IFS=' ' read -r name repo path binflag <<< "$entry"
    dir="$INSTALL_DIR/$name"
    log_info "Backing up any existing $name..."
    [[ -d "$dir" ]] && mv "$dir" "$BACKUP_DIR/${name}_$(date +%s)"

    log_info "Attempting to install/build $name..."
    if [[ \$repo == pip:* ]]; then
      pkg=\${repo#pip:}
      pip3 install --upgrade "\$pkg" >/dev/null 2>&1 && 
        BACKEND_CMD=("\$path" "\$MODEL_DIR/$MODEL_FILE") && return 0
    else
      git clone --depth 1 "\$repo" "$dir" >/dev/null 2>&1 || continue
      pushd "\$dir" >/dev/null
      if [[ "$name" == "llama.cpp" ]]; then
        mkdir -p build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF >/dev/null 2>&1 && make -j$(nproc) >/dev/null 2>&1
        binpath="$dir/\$path"
      else
        cmake . >/dev/null 2>&1 && make -j$(nproc) >/dev/null 2>&1
        binpath="$dir/\$path"
      fi
      popd >/dev/null
      if [[ -x "$binpath" ]]; then
        BACKEND_CMD=("$binpath" $binflag "\$MODEL_DIR/$MODEL_FILE")
        log_success "$name ready"
        return 0
      fi
    fi
  done
  return 1
}

if ! choose_backend; then
  log_error "All backends failed"
  exit 1
fi

# ========== MODEL DOWNLOAD ==========
if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
  log_info "Downloading model..."
  curl -fSL "$MODEL_URL" -o "$MODEL_DIR/$MODEL_FILE" || wget -q "$MODEL_URL" -O "$MODEL_DIR/$MODEL_FILE"
  log_success "Model downloaded"
else
  log_warn "Model exists, skipping download"
fi

# ========== SCRIPT MANAGER ==========
cat << 'EOF' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash
PROMPT="$*"
echo "[SCRIPT MANAGER] \$PROMPT"
# custom logic here
EOF
chmod +x "$SCRIPT_MANAGER"
log_success "Script manager created"

# ========== WRAPPER CREATION ==========
cat << 'EOF' > wrapper.sh
#!/usr/bin/env bash
set -euo pipefail
PROMPT="$*"
echo "\$PROMPT" >> "$LOG_FILE"
LAST_LINE=\$(tail -n1 "$LOG_FILE")
if echo "\$LAST_LINE" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
  bash "$SCRIPT_MANAGER" "\$LAST_LINE"
else
  "\${BACKEND_CMD[@]}" "\$LAST_LINE"
fi
EOF
sudo mv wrapper.sh "$AI_WRAPPER"
sudo chmod +x "$AI_WRAPPER"

log_success "Wrapper installed at $AI_WRAPPER"
log_success "Installation v3.1 complete"
exit 0
