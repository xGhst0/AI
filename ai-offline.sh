#!/usr/bin/env bash
set -euo pipefail

### === VERSION === ###
echo 'Script v4.0'

# ========== CONFIGURATION ==========
INSTALL_DIR="$HOME/.ai_cli_offline"
VENV_DIR="$INSTALL_DIR/venv"
MODEL_DIR="$INSTALL_DIR/models"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"
AI_WRAPPER="/usr/local/bin/ai"
DISK_REQUIRED_GB=10
LOG_FILE="$INSTALL_DIR/conversation.txt"

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

# ========== PRECHECKS ==========
# Disk space
FREE_GB=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
(( FREE_GB < DISK_REQUIRED_GB )) && log_error "Need ${DISK_REQUIRED_GB}GB free, only ${FREE_GB}GB available"
log_success "Disk check passed: ${FREE_GB}GB free"

# Create directories
mkdir -p "$INSTALL_DIR" "$MODEL_DIR"
touch "$LOG_FILE"

# ========== VENV SETUP ==========
log_info "Setting up Python virtual environment..."
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
log_success "Virtual environment ready"

# ========== DEPENDENCIES ==========
log_info "Installing Python packages..."
pip install --quiet llama-cpp-python llm >/dev/null
log_success "Packages installed: llama-cpp-python, llm"

# ========== MODEL SELECTION ==========
log_info "Select model to download:"
echo "1) LLaMA 2 7B Chat"
echo "2) Mistral 7B Instruct"
echo "3) Zephyr 7B"
read -rp "Enter choice [1-3]: " CHOICE
case "$CHOICE" in
  1) MODEL_URL="https://huggingface.co/TheBloke/LLaMA-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf"; MODEL_FILE="llama-2-7b-chat.Q4_K_M.gguf";;
  2) MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"; MODEL_FILE="mistral-7b-instruct-v0.1.Q4_K_M.gguf";;
  3) MODEL_URL="https://huggingface.co/HuggingFaceH4/zephyr-7b-beta-GGUF/resolve/main/zephyr-7b-beta.Q4_K_M.gguf"; MODEL_FILE="zephyr-7b-beta.Q4_K_M.gguf";;
  *) log_error "Invalid selection";;
esac

# ========== DOWNLOAD MODEL ==========
if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
  log_info "Downloading model $MODEL_FILE..."
  curl -fsSL "$MODEL_URL" -o "$MODEL_DIR/$MODEL_FILE" || wget -q "$MODEL_URL" -O "$MODEL_DIR/$MODEL_FILE" || log_error "Model download failed"
  log_success "Model saved to $MODEL_DIR/$MODEL_FILE"
else
  log_warn "Model already present, skipping download"
fi

# ========== SCRIPT MANAGER ==========
cat > "$SCRIPT_MANAGER" << 'EOF'
#!/usr/bin/env bash
PROMPT="$*"
echo "[SCRIPT MANAGER] processing: $PROMPT"
# custom extension logic here
EOF
chmod +x "$SCRIPT_MANAGER"
log_success "Script manager created"

# ========== WRAPPER ==========
cat > wrapper.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
PROMPT="$*"
echo "$PROMPT" >> "$LOG_FILE"
LAST=\$(tail -n1 "$LOG_FILE")
# Agent detection
if echo "$LAST" | grep -Eiq '^(write|create|generate|make).*(script|program)'; then
  "\$HOME"/.ai_cli_offline/script_manager.sh "$LAST"
else
  # Use llm CLI to invoke the model
  llm --model-path "$HOME/.ai_cli_offline/models/$MODEL_FILE" "$LAST"
fi
EOF
sudo mv wrapper.sh "$AI_WRAPPER"
sudo chmod +x "$AI_WRAPPER"
log_success "AI CLI installed as 'ai' at $AI_WRAPPER"

log_success "Installation complete. Use: ai 'Your prompt here'"
exit 0
