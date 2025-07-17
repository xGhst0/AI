#!/usr/bin/env bash
set -euo pipefail

# === AI-CLI OFFLINE INSTALLER & WRAPPER REDESIGN v1.0 ===
# Now uses a Python-based wrapper for robust prompt handling and extensibility.

### CONFIGURATION ###
INSTALL_DIR="$HOME/.ai_cli_offline"
VENV_DIR="$INSTALL_DIR/venv"
MODEL_DIR="$INSTALL_DIR/models"
SCRIPT_MANAGER="$INSTALL_DIR/script_manager.py"
USER_BIN="$HOME/.local/bin"
WRAPPER="$USER_BIN/ai"
LOG_FILE="$INSTALL_DIR/conversation.json"
UPDATE_URL="https://raw.githubusercontent.com/xGhst0/AI/main/ai-offline.sh"

# Ensure base directories
mkdir -p "$INSTALL_DIR" "$MODEL_DIR" "$USER_BIN"
touch "$INSTALLER" "$LOG_FILE"

# === Logging Helpers ===
info(){ printf "\e[34m[INFO]\e[0m %s\n" "$1"; }
warn(){ printf "\e[33m[WARN]\e[0m %s\n" "$1"; }
error(){ printf "\e[31m[ERROR]\e[0m %s\n" "$1"; exit 1; }

# === Self-Update ===
if [[ "${1:-}" == "--update" ]]; then
  info "Checking for updates..."
  tmp=$(mktemp)
  curl -fsSL "$UPDATE_URL" -o "$tmp" || error "Cannot reach update server"
  cmp -s "$0" "$tmp" && { info "Already latest"; rm "$tmp"; exit 0; }
  cp "$0" "$INSTALL_DIR/backup_installer_$(date +%s).sh"
  mv "$tmp" "$0" && chmod +x "$0"
  info "Installer updated. Rerun without --update."
  exit 0
fi

# === Disk Check ===
free_gb=$(df "$HOME" --output=avail -k | tail -1 | awk '{print int($1/1024/1024)}')
(( free_gb < 10 )) && error "Need >=10GB, have ${free_gb}GB"
info "Disk OK: ${free_gb}GB"

# === Virtualenv & Python Dependencies ===
if [[ ! -d "$VENV_DIR" ]]; then
  info "Creating virtualenv..."
  python3 -m venv "$VENV_DIR" || error "venv failed"
fi
# Activate
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
echo "{'installed':[]}" > "$LOG_FILE"  # initialize JSON log
pip install --quiet llama-cpp-python rich >/dev/null || error "pip install failed"
info "Python env ready"

# === Python-Based Interactive Wrapper ===
cat > "$SCRIPT_MANAGER" << 'EOF'
#!/usr/bin/env python3
import json, os, sys
from llama_cpp import Llama
from rich.console import Console

# Paths
home = os.path.expanduser('~')
install = os.path.join(home, '.ai_cli_offline')
model_dir = os.path.join(install, 'models')
log_file = os.path.join(install, 'conversation.json')

console = Console()
# Load or init log
if os.path.exists(log_file):
    with open(log_file, 'r') as f: conversation = json.load(f)
else:
    conversation = {'history': []}

# Handle update flag
if len(sys.argv) > 1 and sys.argv[1] == '--update':
    os.execvp(os.path.join(install, 'ai-offline.sh'), ['ai-offline.sh', '--update'])

# Collect prompt
prompt = ' '.join(sys.argv[1:])
conversation['history'].append({'role': 'user', 'content': prompt})

# Determine model file
models = [f for f in os.listdir(model_dir) if f.endswith('.gguf')]
if not models:
    console.print('[red]No model found in ~/.ai_cli_offline/models[/]')
    sys.exit(1)
model_path = os.path.join(model_dir, models[0])

# Instantiate Llama
llm = Llama(model_path=model_path)
# Build full context
context = '\n'.join([f"{msg['role']}: {msg['content']}" for msg in conversation['history']])
# Generate
res = llm(context, max_tokens=128, stop=['user:', 'assistant:'])
answer = res['choices'][0]['text'].strip()

# Append and print
conversation['history'].append({'role': 'assistant', 'content': answer})
with open(log_file, 'w') as f: json.dump(conversation, f, indent=2)
console.print(f"[bold green]AI:[/] {answer}")
EOF
chmod +x "$SCRIPT_MANAGER"
info "Python wrapper created at $SCRIPT_MANAGER"

# === Install CLI Shim ===
cat > "$WRAPPER" << 'EOF'
#!/usr/bin/env bash
# shim to Python wrapper
VENV="$VENV_DIR/bin/activate"
# shellcheck disable=SC1090
source "$VENV"
exec "$SCRIPT_MANAGER" "$@"
EOF
chmod +x "$WRAPPER"
info "CLI installed as '$WRAPPER'"

info "Installation v1.0 complete. Use 'ai Your prompt' to chat or 'ai --update' to update installer."
