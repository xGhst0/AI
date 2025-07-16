# --- Self-Update Check ---
INSTALLER_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
INSTALLER_PATH="$HOME/.ai_cli_offline/ai-offline.sh"
TMP_INSTALLER="/tmp/ai-offline.sh.tmp"

echo "[INFO] Checking for installer updates .."

# Fetch latest version to temporary file
if curl -fsSL "$INSTALLER_URL" -o "$TMP_INSTALLER"; then
    # Compare hashes
    if ! cmp -s "$0" "$TMP_INSTALLER"; then
        echo "[UPDATE] New version found. Updating installer .."
        chmod +x "$TMP_INSTALLER"
        mv "$TMP_INSTALLER" "$0"
        echo "[UPDATE] Installer updated. Please re-run the script."
        exit 0
    else
        echo "[INFO] You already have the latest version."
        rm -f "$TMP_INSTALLER"
    fi
else
    echo "[WARNING] Failed to download latest installer version. Continuing with current version."
fi


INSTALL_DIR="$HOME/.ai_cli_offline"
MODEL_DIR="$INSTALL_DIR/models"
BIN_DIR="$INSTALL_DIR/llama.cpp/build/bin"
WRAPPER_PATH="/usr/local/bin/ai"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"
INSTALL_SCRIPT_LOCAL="$INSTALL_DIR/ai-offline.sh"

MODEL_LIST=(
  "TheBloke/Llama-2-7B-Chat-GGUF/llama-2-7b-chat.Q4_K_M.gguf"
  "TheBloke/Mistral-7B-Instruct-v0.1-GGUF/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
  "TheBloke/CodeLlama-7B-Instruct-GGUF/codellama-7b-instruct.Q4_K_M.gguf"
)

MODEL_NAMES=(
  "LLaMA 2 7B Chat"
  "Mistral 7B Instruct"
  "CodeLlama 7B Instruct"
)

function update_check() {
  echo "[INFO] Checking for installer updates..."
  curl -sf --etag-save "$INSTALL_DIR/etag" --etag-compare "$INSTALL_DIR/etag" \
    -o "$INSTALL_SCRIPT_LOCAL.tmp" "$INSTALL_SCRIPT_URL" || return 0

  if ! cmp -s "$INSTALL_SCRIPT_LOCAL.tmp" "$INSTALL_SCRIPT_LOCAL"; then
    echo "[UPDATE] New version of ai-offline.sh found. Applying update."
    mv "$INSTALL_SCRIPT_LOCAL.tmp" "$INSTALL_SCRIPT_LOCAL"
    chmod +x "$INSTALL_SCRIPT_LOCAL"
  else
    rm -f "$INSTALL_SCRIPT_LOCAL.tmp"
  fi
}

function cleanup_old() {
  echo "[INFO] Removing previous installations..."
  rm -rf "$INSTALL_DIR"
  sudo rm -f "$WRAPPER_PATH"
}

function setup_dirs() {
  mkdir -p "$MODEL_DIR"
  mkdir -p "$INSTALL_DIR/scripts"
}

function install_deps() {
  echo "[INFO] Installing dependencies..."
  sudo apt update
  sudo apt install -y build-essential cmake git curl
}

function clone_llama() {
  echo "[INFO] Cloning llama.cpp..."
  git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR/llama.cpp"
}

function build_llama() {
  echo "[INFO] Building llama.cpp..."
  cd "$INSTALL_DIR/llama.cpp"
  mkdir -p build && cd build
  cmake .. -DCMAKE_BUILD_TYPE=Release
  make -j$(nproc)
}

function choose_model() {
  echo "[INFO] Choose a model to install:"
  select opt in "${MODEL_NAMES[@]}"; do
    case $REPLY in
      1|2|3)
        MODEL_HF_PATH=${MODEL_LIST[$((REPLY-1))]}
        break
        ;;
      *) echo "Invalid option";;
    esac
  done

  MODEL_FILENAME=$(basename "$MODEL_HF_PATH")
  MODEL_URL="https://huggingface.co/${MODEL_HF_PATH}?raw=true"
  echo "[INFO] Downloading model: $MODEL_FILENAME"
  curl -L -o "$MODEL_DIR/$MODEL_FILENAME" "$MODEL_URL"
}

function create_script_manager() {
  echo "#!/usr/bin/env bash" > "$SCRIPT_MANAGER"
  echo "echo '[SCRIPT MANAGER] Executing agent pipeline for: \$*'" >> "$SCRIPT_MANAGER"
  echo "# Implement actual logic here" >> "$SCRIPT_MANAGER"
  chmod +x "$SCRIPT_MANAGER"
}

function create_wrapper() {
  local MODEL_PATH="$MODEL_DIR/$MODEL_FILENAME"
  echo "[INFO] Creating AI CLI wrapper at $WRAPPER_PATH"

  sudo tee "$WRAPPER_PATH" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="$MODEL_PATH"
LLAMA_CLI="$BIN_DIR/llama-cli"
SCRIPT_MANAGER="$SCRIPT_MANAGER"
INSTALL_SCRIPT_URL="$INSTALL_SCRIPT_URL"

# Update checker
curl -sf --etag-save "$INSTALL_DIR/etag" --etag-compare "$INSTALL_DIR/etag" -o "$INSTALL_DIR/ai-offline.sh.tmp" "\$INSTALL_SCRIPT_URL" || true
if [ -s "$INSTALL_DIR/ai-offline.sh.tmp" ] && ! cmp -s "$INSTALL_DIR/ai-offline.sh.tmp" "$INSTALL_DIR/ai-offline.sh"; then
  mv "$INSTALL_DIR/ai-offline.sh.tmp" "$INSTALL_DIR/ai-offline.sh"
  chmod +x "$INSTALL_DIR/ai-offline.sh"
  echo "[UPDATE] New installer script fetched."
fi

PROMPT="\$*"
if echo "\$PROMPT" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
  echo "[AGENT MODE] Delegating to script manager."
  bash "\$SCRIPT_MANAGER" "\$PROMPT"
  exit 0
fi

if [[ ! -x "\$LLAMA_CLI" ]]; then
  echo "[ERROR] llama-cli not found. Attempting to rebuild..."
  cd "$INSTALL_DIR/llama.cpp"
  mkdir -p build && cd build
  cmake .. -DCMAKE_BUILD_TYPE=Release && make -j\$(nproc)
fi

exec "\$LLAMA_CLI" -m "\$MODEL_PATH" -p "\$PROMPT"
EOF

  sudo chmod +x "$WRAPPER_PATH"
  echo "[INFO] AI CLI wrapper script created."
}

### --- MAIN FLOW --- ###
update_check
cleanup_old
setup_dirs
install_deps
clone_llama
build_llama
choose_model
create_script_manager
create_wrapper

echo "[DONE] Installation complete! Use: ai 'Your prompt here'"
