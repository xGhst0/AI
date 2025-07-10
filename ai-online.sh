#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

log()    { echo -e "\e[1;34m[INFO]\e[0m $*"; }
warn()   { echo -e "\e[1;33m[WARN]\e[0m $*"; }
error()  { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

if [ "$EUID" -eq 0 ]; then
  error "Please do NOT run this script as root. Run as a normal user."
fi

API_KEY=""

# Parse optional -apikey argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    -apikey)
      shift
      if [[ $# -eq 0 ]]; then
        error "Missing value for -apikey"
      fi
      API_KEY="$1"
      shift
      ;;
    *)
      error "Unknown argument: $1"
      ;;
  esac
done

AI_DIR="$HOME/.ai_cli"
VENV_DIR="$AI_DIR/venv"
AI_SCRIPT="$AI_DIR/ai_cli.py"
WRAPPER="/usr/local/bin/ai"
HISTORY_FILE="$HOME/.ai_cli/history.json"

# Determine shell config file to edit
user_shell="$(basename "$SHELL")"
case "$user_shell" in
  bash) SHELL_RC="$HOME/.bashrc" ;;
  zsh)  SHELL_RC="$HOME/.zshrc" ;;
  *)    SHELL_RC="$HOME/.profile" ;;  # fallback
esac

log "Detected shell: $user_shell"
log "Will save API key to $SHELL_RC"

log "Removing any previous AI CLI installation..."
sudo rm -f "$WRAPPER" || true
rm -rf "$AI_DIR"
log "Cleanup done."

log "Updating package list and installing dependencies..."
sudo apt update
sudo apt install -y python3 python3-venv python3-pip curl jq

log "Creating Python virtual environment at $VENV_DIR..."
python3 -m venv "$VENV_DIR"

log "Activating virtual environment and installing OpenAI Python client..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install openai

log "Writing AI CLI Python script to $AI_SCRIPT..."
mkdir -p "$AI_DIR"
cat > "$AI_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import os, sys, json, openai

HISTORY_FILE = os.path.expanduser("~/.ai_cli/history.json")
MODEL = "gpt-3.5-turbo"

def load_history():
    if not os.path.exists(HISTORY_FILE):
        return []
    try:
        with open(HISTORY_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return []

def save_history(history):
    try:
        with open(HISTORY_FILE, "w") as f:
            json.dump(history, f, indent=2)
    except Exception as e:
        print(f"❌ Failed to save conversation history: {e}")

def main():
    args = sys.argv[1:]
    if not args:
        print("Usage:\n  ai <prompt>\n  ai -reset\n  ai -finish")
        return

    cmd = args[0].lower()
    if cmd in ("-reset", "--reset"):
        save_history([])
        print("✅ Conversation memory reset.")
        return
    if cmd in ("-finish", "--finish"):
        save_history([])
        print("👋 Conversation finished and memory cleared.")
        return

    prompt = " ".join(args)
    history = load_history()
    history.append({"role": "user", "content": prompt})

    openai.api_key = os.getenv("OPENAI_API_KEY")
    if not openai.api_key:
        print("❌ OPENAI_API_KEY environment variable not set. Please set it and retry.")
        sys.exit(1)

    try:
        resp = openai.chat.completions.create(
            model=MODEL,
            messages=history,
            temperature=0.7,
        )
        reply = resp.choices[0].message.content.strip()
        print(reply)
        history.append({"role": "assistant", "content": reply})
        save_history(history)
    except Exception as e:
        print(f"❌ OpenAI API error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
chmod +x "$AI_SCRIPT"

log "Creating global ai wrapper script at $WRAPPER..."
sudo tee "$WRAPPER" > /dev/null <<EOF
#!/bin/bash
export OPENAI_API_KEY="\$OPENAI_API_KEY"
"$VENV_DIR/bin/python" "$AI_SCRIPT" "\$@"
EOF
sudo chmod +x "$WRAPPER"

if [ -n "$API_KEY" ]; then
  if [[ "$API_KEY" =~ ^sk- ]]; then
    log "Using provided API key from -apikey argument."
    # Remove old keys from shell rc, then add new
    sed -i '/^export OPENAI_API_KEY=/d' "$SHELL_RC"
    echo "export OPENAI_API_KEY=\"$API_KEY\"" >> "$SHELL_RC"
    export OPENAI_API_KEY="$API_KEY"
    log "API key saved to $SHELL_RC and environment variable set for this session."
    log "Please reload your shell config by running:"
    echo "source $SHELL_RC"
  else
    warn "Provided API key does not look valid. Please check and rerun script."
  fi
else
  if [ -z "${OPENAI_API_KEY-}" ]; then
    warn "OPENAI_API_KEY is not set in your environment."
    read -rp "Please enter your OpenAI API key (sk-...): " user_key
    if [[ "$user_key" =~ ^sk- ]]; then
      sed -i '/^export OPENAI_API_KEY=/d' "$SHELL_RC"
      echo "export OPENAI_API_KEY=\"$user_key\"" >> "$SHELL_RC"
      export OPENAI_API_KEY="$user_key"
      log "API key saved to $SHELL_RC and environment variable set for this session."
      log "Please reload your shell config by running:"
      echo "source $SHELL_RC"
    else
      warn "Invalid key format. Please manually set OPENAI_API_KEY environment variable later."
    fi
  else
    log "OPENAI_API_KEY detected in environment."
  fi
fi

log "Installation complete!"
log "Use 'ai \"your prompt\"' to talk with the AI."
exit 0
