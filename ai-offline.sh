#!/usr/bin/env bash
set -euo pipefail

### === VERSION === ###
echo 'Script v2.9'

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
EMOJI_ROCKET="[🚀]"

# ========== ECHO WRAPPER ==========
log_info()    { echo -e "$EMOJI_INFO $1"; }
log_warn()    { echo -e "$EMOJI_WARN $1"; }
log_success() { echo -e "$EMOJI_SUCCESS $1"; }
log_error()   { echo -e "$EMOJI_ERROR $1"; }
log_launch()  { echo -e "$EMOJI_ROCKET $1"; }

# ========== UPDATE MODE ONLY ==========
if [[ "${1:-}" == "--update" ]]; then
  log_info "Checking for installer updates ..."
  mkdir -p "$INSTALL_DIR"
  if curl -fsSL "$INSTALLER_URL" -o "$TMP_UPDATE"; then
      if ! cmp -s "$0" "$TMP_UPDATE"; then
          log_info "Update found! Applying update ..."
          if mv "$TMP_UPDATE" "$0" 2>/dev/null || sudo mv "$TMP_UPDATE" "$0"; then
              log_success "Installer updated. Please re-run the script."
              exit 0
          else
              log_error "Failed to apply update. Check permissions."
              exit 1
          fi
      else
          rm "$TMP_UPDATE"
          log_info "Installer is up to date."
      fi
  else
      log_warn "Could not check for updates. Continuing ..."
  fi
  exit 0
fi

# ========== DISK CHECK ==========
log_info "Checking for at least ${DISK_REQUIRED_GB}GB of free space ..."
FREE_GB=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
if (( FREE_GB < DISK_REQUIRED_GB )); then
    log_error "Not enough disk space. Required: ${DISK_REQUIRED_GB}GB, Available: ${FREE_GB}GB"
    exit 1
else
    log_success "Sufficient disk space available: ${FREE_GB}GB"
fi

# ========== MODEL SELECTION ==========
log_info "Choose a model to install:"
echo "1) 🧠 LLaMA 2 7B Chat (Meta)"
echo "2) 💬 Mistral 7B Instruct (MistralAI)"
echo "3) 🦊 Zephyr 7B (HuggingFace Community)"
read -rp "Enter your choice [1-3]: " MODEL_CHOICE
case "$MODEL_CHOICE" in
    1)
        MODEL_URL="https://huggingface.co/TheBloke/LLaMA-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf"
        MODEL_FILE="llama-2-7b-chat.Q4_K_M.gguf"
        ;;
    2)
        MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
        MODEL_FILE="mistral-7b-instruct-v0.1.Q4_K_M.gguf"
        ;;
    3)
        MODEL_URL="https://huggingface.co/HuggingFaceH4/zephyr-7b-beta-GGUF/resolve/main/zephyr-7b-beta.Q4_K_M.gguf"
        MODEL_FILE="zephyr-7b-beta.Q4_K_M.gguf"
        ;;
    *)
        log_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

# ========== CLEAN OLD LLAMA.CPP ==========
if [[ -d "$HOME/.ai_cli_offline/llama.cpp" ]]; then
  log_warn "Removing existing llama.cpp ..."
  rm -rf "$HOME/.ai_cli_offline/llama.cpp"
  log_success "llama.cpp removed."
fi

# ========== SYSTEM DEPENDENCIES ==========
log_info "Installing system dependencies ..."
sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq cmake build-essential curl python3-venv python3-dev git >/dev/null
log_success "System dependencies installed."

# ========== INSTALL GPT4ALL CHAT BACKEND ==========
BACKEND_DIR="$INSTALL_DIR/gpt4all"
git clone --depth 1 https://github.com/nomic-ai/gpt4all.git "$BACKEND_DIR"
cd "$BACKEND_DIR"
mkdir -p build && cd build
cmake .. >/dev/null && make -j$(nproc) >/dev/null
log_success "gpt4all built."

# ========== DOWNLOAD MODEL ==========
mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL_DIR/$MODEL_FILE" ]]; then
    log_warn "Model already exists at $MODEL_DIR/$MODEL_FILE. Skipping download."
else
    log_info "Downloading model: $MODEL_FILE ..."
    if ! curl -fSL "$MODEL_URL" -o "$MODEL_DIR/$MODEL_FILE" 2>/dev/null; then
        log_warn "Primary download failed. Retrying with wget ..."
        if ! wget -q "$MODEL_URL" -O "$MODEL_DIR/$MODEL_FILE"; then
            log_error "Failed to download model from both sources."
            exit 1
        fi
    fi
    log_success "Model downloaded to: $MODEL_DIR/$MODEL_FILE"
fi

# ========== CREATE SCRIPT MANAGER ==========
log_info "Creating script manager agent ..."
cat << 'EOF_SCRIPT' > "$SCRIPT_MANAGER"
#!/usr/bin/env bash
PROMPT="$*"
echo "[SCRIPT MANAGER] Handling script generation: $PROMPT"
# Add logic here to handle prompt parsing
EOF_SCRIPT
chmod +x "$SCRIPT_MANAGER"
log_success "Script manager created."

# ========== CREATE AI WRAPPER ==========
log_info "Creating AI CLI wrapper script ..."
RESOLVED_BIN="$BACKEND_DIR/build/bin/gpt4all"
RESOLVED_MODEL="$MODEL_DIR/$MODEL_FILE"
RESOLVED_LOG="$LOG_FILE"
RESOLVED_SCRIPT_MANAGER="$SCRIPT_MANAGER"

cat << EOF_WRAPPER | sudo tee "$AI_WRAPPER" >/dev/null
#!/usr/bin/env bash
set -euo pipefail
MODEL_PATH="$RESOLVED_MODEL"
BINARY="$RESOLVED_BIN"
SCRIPT_MANAGER="$RESOLVED_SCRIPT_MANAGER"
LOG_FILE="$RESOLVED_LOG"

mkdir -p \$(dirname "\$LOG_FILE")
touch "\$LOG_FILE"

PROMPT="\$*"
echo "\$PROMPT" >> "\$LOG_FILE"
LAST_LINE=\$(tail -n 1 "\$LOG_FILE")

if echo "\$LAST_LINE" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
    echo "[AGENT MODE] Delegating to script manager ..."
    bash "\$SCRIPT_MANAGER" "\$LAST_LINE"
    exit 0
fi

exec "\$BINARY" --model-path "\$MODEL_PATH" --prompt "\$LAST_LINE"
EOF_WRAPPER

sudo chmod +x "$AI_WRAPPER"
log_success "AI CLI wrapper created at: $AI_WRAPPER"

# ========== SELF-TEST ==========
log_info "Verifying wrapper execution ..."
if ! "$AI_WRAPPER" --help >/dev/null 2>&1; then
  log_error "Wrapper test failed. Please verify that gpt4all runs manually."
  echo "Try running: \"$RESOLVED_BIN --model-path $RESOLVED_MODEL --prompt 'Hello'\" manually to debug."
  exit 1
fi
log_success "Wrapper test completed. Installation successful."
