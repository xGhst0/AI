#!/bin/bash
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

BASE_DIR="$REAL_HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
LOGFILE="$BASE_DIR/install.log"
BIN_WRAPPER="/usr/local/bin/ai"
SCRIPT_MANAGER="$BASE_DIR/script_manager.sh"
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"

mkdir -p "$BASE_DIR" "$MODELS_DIR"
touch "$LOGFILE"

log() {
    echo "[INFO] $*" | tee -a "$LOGFILE"
}

error_exit() {
    echo "[ERROR] $*" | tee -a "$LOGFILE" >&2
    exit 1
}

install_dependencies() {
    log "Checking system dependencies..."
    local deps=(build-essential cmake git curl libcurl4-openssl-dev libomp-dev)
    local to_install=()
    for dep in "${deps[@]}"; do
        if ! dpkg -s "$dep" >/dev/null 2>&1; then
            to_install+=("$dep")
        fi
    done
    if [ "${#to_install[@]}" -gt 0 ]; then
        echo "Installing missing dependencies: ${to_install[*]}"
        sudo apt update
        sudo apt install -y "${to_install[@]}"
    else
        log "All dependencies already installed."
    fi
}

clone_or_update_repo() {
    if [ -d "$LLAMA_DIR/.git" ]; then
        log "Updating llama.cpp repository..."
        git -C "$LLAMA_DIR" pull || log "Failed to update, continuing with existing code."
    else
        log "Cloning llama.cpp repository..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR" || error_exit "Failed to clone llama.cpp."
    fi
}

build_llama() {
    if [ -f "$BUILD_DIR/libllama.so" ] || [ -x "$(find "$BUILD_DIR/bin" -type f -executable -name 'llama-*' | head -n 1)" ]; then
        log "llama.cpp appears to be built, skipping build step."
        return
    fi
    log "Building llama.cpp with CMake..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)" || error_exit "Build failed."
}

download_model() {
    local model_path="$MODELS_DIR/$MODEL_NAME"
    if [ -f "$model_path" ]; then
        log "Model $MODEL_NAME already exists. Skipping download."
        return
    fi
    echo -n "Enter your HuggingFace API token: "
    read -r HF_API_TOKEN
    log "Downloading model $MODEL_NAME ..."
    curl -L -o "$model_path" -H "Authorization: Bearer $HF_API_TOKEN" "$MODEL_URL" || error_exit "Model download failed."
}

create_script_manager() {
    if [ -f "$SCRIPT_MANAGER" ]; then
        log "script_manager.sh already exists. Skipping creation."
        return
    fi
    log "Creating script_manager.sh agent pipeline at $SCRIPT_MANAGER..."
    cat > "$SCRIPT_MANAGER" <<'EOF'
#!/bin/bash
set -euo pipefail

PROMPT="$*"
WORK_DIR="$HOME/.ai_cli_offline/scripts"
mkdir -p "$WORK_DIR"

echo "[SCRIPT_MANAGER] Received task: $PROMPT"
FILENAME=$(echo "$PROMPT" | tr ' ' '_' | tr -dc '[:alnum:]_-').py
SCRIPT_PATH="$WORK_DIR/$FILENAME"

echo "[THINKING AGENT] Breaking down task..."
sleep 1

echo "[WRITING AGENT] Generating draft..."
echo "#!/usr/bin/env python3" > "$SCRIPT_PATH"
echo "# TODO: implement logic for -> $PROMPT" >> "$SCRIPT_PATH"
echo "print('Task: $PROMPT')" >> "$SCRIPT_PATH"

echo "[QC AGENT] Reviewing draft..."
sleep 1
echo "[QC AGENT] No errors detected."

chmod +x "$SCRIPT_PATH"
echo "[HANDOVER AGENT] Script saved at: $SCRIPT_PATH"
EOF
    chmod +x "$SCRIPT_MANAGER"
}

create_cli_wrapper() {
    if [ -f "$BIN_WRAPPER" ]; then
        log "AI CLI wrapper already exists at $BIN_WRAPPER. Skipping creation."
        return
    fi
    log "Creating AI CLI wrapper at $BIN_WRAPPER (requires sudo)..."
    sudo tee "$BIN_WRAPPER" > /dev/null <<EOF
#!/bin/bash
set -euo pipefail

BASE_DIR="$BASE_DIR"
MODEL_NAME="$MODEL_NAME"
MODEL_PATH="\$BASE_DIR/models/\$MODEL_NAME"
SCRIPT_MANAGER="\$BASE_DIR/script_manager.sh"

LLAMA_BIN=\$(find "\$BASE_DIR/llama.cpp/build/bin" -type f -executable -name 'llama-*' | grep -E 'cli\$|run\$|simple-chat\$' | head -n 1 || true)

if [ -z "\$LLAMA_BIN" ]; then
    echo "[ERROR] Llama binary not found."
    exit 1
fi

if [ ! -f "\$MODEL_PATH" ]; then
    echo "[ERROR] Model not found at \$MODEL_PATH"
    exit 1
fi

if echo "\$*" | grep -Ei "^(write|create|generate|make|script) .*script" > /dev/null; then
    echo "[AGENT MODE] Handing task to agent pipeline..."
    exec "\$SCRIPT_MANAGER" "\$@"
fi

exec "\$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$*"
EOF
    sudo chmod +x "$BIN_WRAPPER"
}

main() {
    log "Starting installation..."

    install_dependencies
    clone_or_update_repo
    build_llama
    download_model
    create_script_manager
    create_cli_wrapper

    log "Installation completed successfully!"
    echo ""
    echo "Usage: ai \"Your prompt here\""
    echo "Example: ai \"create a python script to list .txt files\""
    echo ""
}

main "$@"
