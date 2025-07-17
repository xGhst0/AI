#!/usr/bin/env bash
set -euo pipefail

# Constants
INSTALL_DIR="$HOME/.ai_cli_offline"
SCRIPT_NAME="ai-offline.sh"
TMP_SCRIPT="${INSTALL_DIR}/${SCRIPT_NAME}.tmp"
REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main/ai-offline.sh"
LLAMA_CPP_REPO="https://github.com/ggerganov/llama.cpp.git"
MODEL_DIR="$INSTALL_DIR/models"
DEFAULT_MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf"
ALTERNATE_MODEL_URL="https://huggingface.co/NousResearch/Nous-Hermes-Llama2-GGUF/resolve/main/nous-hermes-llama2-7b.Q4_K_M.gguf"
REQUIRED_SPACE_MB=10240

# Ensure install dir
mkdir -p "$INSTALL_DIR"

# Check disk space
AVAILABLE_SPACE_MB=$(df "$INSTALL_DIR" | awk 'NR==2 {print int($4/1024)}')
if (( AVAILABLE_SPACE_MB < REQUIRED_SPACE_MB )); then
  echo "[ERROR] Not enough disk space. Required: ${REQUIRED_SPACE_MB}MB, Available: ${AVAILABLE_SPACE_MB}MB"
  exit 1
fi

# Self-update check
echo "[INFO] Checking for installer updates ..."
if curl -fsSL "$REMOTE_SCRIPT_URL" -o "$TMP_SCRIPT"; then
  if ! diff -q "$0" "$TMP_SCRIPT" >/dev/null 2>&1; then
    echo "[UPDATE] New version of $SCRIPT_NAME found. Applying update."
    if mv "$TMP_SCRIPT" "$0" 2>/dev/null || sudo mv "$TMP_SCRIPT" "$0"; then
      chmod +x "$0"
      exec "$0" "$@"
    else
      echo "[ERROR] Failed to overwrite script. Manual update required."
      exit 1
    fi
  else
    rm -f "$TMP_SCRIPT"
  fi
else
  echo "[WARN] Could not check for updates. Continuing with existing script."
fi

# Dependencies
sudo apt-get update && sudo apt-get install -y git cmake build-essential curl python3 python3-venv

# Clone llama.cpp
echo "[INFO] Cloning llama.cpp ..."
rm -rf "$INSTALL_DIR/llama.cpp"
git clone "$LLAMA_CPP_REPO" "$INSTALL_DIR/llama.cpp"

# Build llama.cpp
mkdir -p "$INSTALL_DIR/llama.cpp/build"
cd "$INSTALL_DIR/llama.cpp/build"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Model selection
echo "[PROMPT] Choose a model to install:"
echo "1. LLaMA 2 7B Chat (default)"
echo "2. Nous Hermes LLaMA2 7B"
echo "3. Mistral-7B-Instruct (Experimental)"
read -rp "Enter your choice [1-3]: " MODEL_CHOICE
MODEL_PATH="$MODEL_DIR/llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="$DEFAULT_MODEL_URL"

case "$MODEL_CHOICE" in
  2)
    MODEL_PATH="$MODEL_DIR/nous-hermes-llama2-7b.Q4_K_M.gguf"
    MODEL_URL="$ALTERNATE_MODEL_URL"
    ;;
  3)
    MODEL_PATH="$MODEL_DIR/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
    MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
    ;;
esac

mkdir -p "$MODEL_DIR"
echo "[INFO] Downloading model ..."
if ! curl -L "$MODEL_URL" -o "$MODEL_PATH"; then
  echo "[WARN] Primary model download failed. Trying alternative mirror ..."
  if ! curl -L "$ALTERNATE_MODEL_URL" -o "$MODEL_PATH"; then
    echo "[ERROR] Failed to download model. Aborting."
    exit 1
  fi
fi

# Create script manager stub
cat << 'EOF' > "$INSTALL_DIR/script_manager.sh"
#!/usr/bin/env bash
PROMPT="$*"
echo "[SCRIPT MANAGER] Received: $PROMPT"
# Placeholder: script creation logic
EOF
chmod +x "$INSTALL_DIR/script_manager.sh"

# Create AI CLI wrapper
cat << EOF > "/usr/local/bin/ai"
#!/usr/bin/env bash
set -euo pipefail
LLAMA_BIN="$INSTALL_DIR/llama.cpp/build/bin/llama-simple-chat"
MODEL_PATH="$MODEL_PATH"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.sh"

PROMPT="\$*"

if [[ ! -x "\$LLAMA_BIN" ]]; then
  echo "[ERROR] Llama binary not found at \$LLAMA_BIN"
  exit 1
fi

if echo "\$PROMPT" | grep -Eiq "^(write|create|generate|make).*(script|program)"; then
  echo "[AGENT MODE] Delegating to script manager."
  bash "\$SCRIPT_MANAGER" "\$PROMPT"
  exit 0
fi

echo "Running: \$LLAMA_BIN -m \"\$MODEL_PATH\" -p \"\$PROMPT\""
exec "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$PROMPT"
EOF

chmod +x "/usr/local/bin/ai"
echo "[INFO] Installation complete! Run AI with: ai \"Your prompt here\""
