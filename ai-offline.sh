#!/bin/bash
set -euo pipefail

# Variables
BASE_DIR="$HOME/.ai_cli_offline"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$BASE_DIR/models"
BIN_WRAPPER="/usr/local/bin/ai"
LOGFILE="$BASE_DIR/install.log"
HF_API_TOKEN=""
LLAMA_BIN=""
MODEL_NAME="llama-2-7b-chat.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/$MODEL_NAME"

# Functions for logging and errors
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

install_dependencies() {
    log "Installing required dependencies..."
    sudo apt update
    sudo apt install -y build-essential cmake libcurl4-openssl-dev libomp-dev git curl
}

clone_or_update_repo() {
    if [ -d "$LLAMA_DIR" ]; then
        log "Updating llama.cpp repository..."
        git -C "$LLAMA_DIR" pull || warn "Failed to update repo, proceeding with existing code."
    else
        log "Cloning llama.cpp repository..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR" || error_exit "Failed to clone llama.cpp."
    fi
}

build_llama() {
    log "Building llama.cpp with CMake..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc) || error_exit "Build failed."
    log "Build completed."
}

find_working_binary() {
    log "Searching for llama executables in $BUILD_DIR/bin ..."
    local candidates=(
        "llama"
        "llama-cli"
    )

    for binname in "${candidates[@]}"; do
        local binpath="$BUILD_DIR/bin/$binname"
        if [ -x "$binpath" ]; then
            log "Testing binary: $binpath"
            if "$binpath" --help >/dev/null 2>&1; then
                log "Binary $binname works."
                LLAMA_BIN="$binpath"
                return 0
            else
                warn "Binary $binname exists but does not run correctly."
            fi
        else
            warn "Binary $binname not found or not executable."
        fi
    done

    error_exit "No working llama binary found."
}

download_model() {
    mkdir -p "$MODELS_DIR"
    cd "$MODELS_DIR"

    if [ -f "$MODEL_NAME" ]; then
        log "Model $MODEL_NAME already exists. Skipping download."
        return
    fi

    if [ -z "$HF_API_TOKEN" ]; then
        read -rp "Enter your HuggingFace API token: " HF_API_TOKEN
    fi

    log "Downloading model $MODEL_NAME ..."
    curl -L -o "$MODEL_NAME" -H "Authorization: Bearer $HF_API_TOKEN" "$MODEL_URL" || error_exit "Failed to download model."
    log "Model downloaded."
}

create_wrapper_script() {
    log "Creating AI CLI wrapper script at $BIN_WRAPPER ..."
    sudo tee "$BIN_WRAPPER" > /dev/null <<EOF
#!/bin/bash
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"
if [ ! -f "\$MODEL_PATH" ]; then
  echo "Model file not found at \$MODEL_PATH"
  exit 1
fi

exec "$LLAMA_BIN" -m "\$MODEL_PATH" -p "\$*"
EOF
    sudo chmod +x "$BIN_WRAPPER"
    log "Wrapper script created."
}

main() {
    log "Starting offline AI CLI setup..."

    install_dependencies

    clone_or_update_repo

    build_llama

    find_working_binary

    download_model

    create_wrapper_script

    log "[DONE] Offline AI CLI installed successfully."
    log "Test it by running: ai \"Hello, what are open ports?\""
}

main "$@"
