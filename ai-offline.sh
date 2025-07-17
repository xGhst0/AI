#!/usr/bin/env bash
set -euo pipefail

### === VERSION === ###
echo 'Script v5.0'

# ========== CONFIGURATION ==========
INSTALL_DIR="$HOME/.ai_cli_offline"
INSTALLER="$INSTALL_DIR/ai-offline.sh"
VENV_DIR="$INSTALL_DIR/venv"
MODEL_DIR="$INSTALL_DIR/models"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"
USER_BIN="$HOME/.local/bin"
AI_WRAPPER="$USER_BIN/ai"
DISK_REQUIRED_GB=10
LOG_FILE="$INSTALL_DIR/conversation.txt"
INSTALLER_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
TMP_UPDATE="$INSTALL_DIR/ai-offline.sh.tmp"

# ========== EMOJI CONSTANTS ==========
EMOJI_INFO="[\033[1;34mℹ️\033[0m]"
EMOJI_WARN="[\033[1;33m⚠️\033[0m]"
EMOJI_SUCCESS="[\033[1;32m✅\033[0m]"
EMOJI_ERROR="[\033[1;31m❌\033[0m]"

# ========== LOGGER ==========
log() { echo -e "$1 $2"; }
log_info()    { log "$EMOJI_INFO" "$1"; }
log_warn()    { log "$EMOJI_WARN" "$1"; }
log_success() { log "$EMOJI_SUCCESS" "$1"; }
log_error()   { log "$EMOJI_ERROR" "$1"; exit 1; }

# ========== HANDLE --update ==========
if [[ "${1:-}" == "--update" ]]; then
  log_info "Checking for installer updates..."
  mkdir -p "$INSTALL_DIR"
  if curl -fsSL "$INSTALLER_URL" -o "$TMP_UPDATE"; then
    if ! cmp -s "$INSTALLER" "$TMP_UPDATE"; then
      log_info "Backup and apply update"
      cp "$INSTALLER" "$INSTALL_DIR/installer_backup_$(date +%Y%m%d%H%M%S).sh"
      mv "$TMP_UPDATE" "$INSTALLER"
      chmod +x "$INSTALLER"
      log_success "Installer updated. Rerun without --update."
    else
      log_info "Installer is already up to date"
      rm "$TMP_UPDATE"
    fi
  else
    log_warn "Unable to fetch updates"
  fi
  exit 0
fi

# ========== PRECHECKS ==========
mkdir -p "$INSTALL_DIR" "$MODEL_DIR" "$USER_BIN"
touch "$LOG_FILE" "$INSTALLER"
FREE_GB=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
(( FREE_GB < DISK_REQUIRED_GB )) && log_error "Require ${DISK_REQUIRED_GB}GB, have ${FREE_GB}GB"
log_success "Disk OK: ${FREE_GB}GB free"
if ! echo "$PATH" | grep -q "$USER_BIN"; then
  log_warn "Add '$USER_BIN' to PATH"
fi

# ========== VENV & DEPENDENCIES ==========
log_info "Creating virtual environment..."
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
pip install --quiet llama-cpp-python llm >/dev/null
log_success "Venv ready with llama-cpp-python & llm"

# ========== MODEL SELECTION ==========
log_info "Select a model:"
echo "1) LLaMA 2 7B Chat"
echo "2) Mistral 7B Instruct"
echo "3) Zephyr 7B"
read -rp "Enter choice [1-3]: " CHOICE
case "$CHOICE" in
  1) MODEL_FILE="llama-2-7b-chat.Q4_K_M.gguf"; MODEL_URL="https://huggingface.co/TheBloke/LLaMA-2-7B-Chat-GGUF/resolve/main/$MODEL_FILE";;
  2) MODEL_FILE="mistral-7b-instruct-v0.1.Q4_K_M.gguf"; MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/$MODEL_FILE";;
  3) MODEL_FILE="zephyr-7b-beta.Q4_K_M.gguf"; MODEL_URL="https://huggingface.co/HuggingFaceH4/zephyr-7b-beta-GGUF/resolve/main/$MODEL_FILE";;
  *) log_error "Invalid selection";;
esac

# ========== DOWNLOAD MODEL ==========
if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
  log_info "Downloading $MODEL_FILE..."
  curl -fsSL "$MODEL_URL" -o "$MODEL_DIR/$MODEL_FILE" || wget -q "$MODEL_URL" -O "$MODEL_DIR/$MODEL_FILE" || log_error "Model download failed"
  log_success "Model saved: $MODEL_DIR/$MODEL_FILE"
else
  log_warn "Model already exists, skipping download"
fi

# ========== SCRIPT MANAGER ==========
cat > "$SCRIPT_MANAGER" << 'EOF'
#!/usr/bin/env bash
PROMPT="$*"
echo "[SCRIPT MANAGER] \$PROMPT"
# custom logic here
EOF
chmod +x "$SCRIPT_MANAGER"
log_success "Script manager at $SCRIPT_MANAGER"

# ========== WRAPPER CREATION ==========
cat > "$AI_WRAPPER" << EOF
#!/usr/bin/env bash
set -euo pipefail
# Activate environment
source "$VENV_DIR/bin/activate"
PROMPT="\$*"
# Log prompt
echo "\$PROMPT" >> "$LOG_FILE"
LAST=\$(tail -n1 "$LOG_FILE")
if [[ "\$LAST" == "--update" ]]; then
  exec "$INSTALLER" --update
elif echo "\$LAST" | grep -Eiq '^(write|create|generate|make).*(script|program)'; then
  bash "$SCRIPT_MANAGER" "\$LAST"
else
  llm --model-path "$MODEL_DIR/$MODEL_FILE" "\$LAST"
fi
EOF
chmod +x "$AI_WRAPPER"
log_success "Wrapper installed at $AI_WRAPPER"

log_success "Installation complete (v5.0). Use 'ai --update' to update and 'ai "Your prompt"' to chat."
exit 0
