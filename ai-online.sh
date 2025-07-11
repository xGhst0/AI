#!/usr/bin/env bash
set -euo pipefail

echo "[ORCH] Starting Offline AI CLI Setup"

# ===== STEP 1: Fix missing GPG keys =====
echo "[GPG] Checking for missing keys..."
if sudo apt-get update 2>&1 | grep -q 'NO_PUBKEY'; then
  KEY=$(sudo apt-get update 2>&1 | grep 'NO_PUBKEY' | head -n1 | awk '{print $NF}')
  echo "[GPG] Importing missing key $KEY..."
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$KEY" || echo "[GPG] Failed to import $KEY"
  sudo apt-get update || echo "[GPG] Update failed after key import"
else
  echo "[GPG] No missing keys detected."
fi

# ===== STEP 2: Install dependencies =====
echo "[DEPS] Installing system dependencies..."
pkgs=(curl wget unzip python3 python3-pip git gnupg)
for i in {1..3}; do
  if sudo apt-get update && sudo apt-get install -y "${pkgs[@]}"; then
    echo "[DEPS] Dependencies installed."
    break
  fi
  echo "[DEPS] Attempt $i failed; cleaning cache..."
  sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
  sleep 2
done

# ===== STEP 3: Model selection =====
declare -A MODEL_URLS=(
  ["Nidum"]="https://example.com/nidum.gguf"
  ["Osmosis"]="https://example.com/osmosis.gguf"
  ["Qwen3"]="https://example.com/qwen3.gguf"
)
MODEL_NAMES=("Nidum" "Osmosis" "Qwen3")

echo "[MODEL] Choose your model:"
select MODEL in "${MODEL_NAMES[@]}"; do
  if [[ -n "$MODEL" ]]; then
    break
  fi
done

MODEL_URL="${MODEL_URLS[$MODEL]}"
MODEL_DIR="$HOME/.ai_cli_offline/models"
mkdir -p "$MODEL_DIR"
MODEL_PATH="$MODEL_DIR/$MODEL.gguf"

echo "[MODEL] Downloading $MODEL model..."
wget -q -O "$MODEL_PATH" "$MODEL_URL" || curl -sL -o "$MODEL_PATH" "$MODEL_URL"

# ===== STEP 4: Install AI core binary =====
CORE_URL="https://example.com/ai_core"
CORE_BIN="$HOME/.ai_cli_offline/bin/ai_core"
mkdir -p "$(dirname "$CORE_BIN")"
echo "[CORE] Downloading AI core binary..."
wget -q -O "$CORE_BIN" "$CORE_URL" || curl -sL -o "$CORE_BIN" "$CORE_URL"
chmod +x "$CORE_BIN"

# ===== STEP 5: Install manager AI command wrapper =====
AI_WRAPPER="$HOME/.ai_cli_offline/bin/ai"
mkdir -p "$(dirname "$AI_WRAPPER")"
cat > "$AI_WRAPPER" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CORE="$HOME/.ai_cli_offline/bin/ai_core"
HIST="$HOME/.ai_cli_offline/conversations/history.txt"
LOGS="$HOME/.ai_cli_offline/logs"
mkdir -p "$(dirname "$HIST")" "$LOGS"

query="$*"
echo "User: $query" >> "$HIST"

if [[ "$query" == run\ * ]]; then
  cmd="${query#run }"
  echo "[AI-CMD] Running shell command: $cmd"
  output=$(eval "$cmd" 2>&1)
  echo "$output"
  echo -e "Command: $cmd\n$output\n" >> "$LOGS/last_command.txt"
  exit 0
fi

if [[ "$query" == save\ * ]]; then
  filename=$(echo "$query" | awk '{print $2}')
  content=$(echo "$query" | cut -d' ' -f3-)
  echo "$content" > "$filename"
  echo "Saved to $filename"
  exit 0
fi

"$CORE" -p "$query"
EOF
chmod +x "$AI_WRAPPER"

# ===== STEP 6: Confirm CLI working =====
if command -v ai >/dev/null; then
  echo "[DONE] AI CLI is globally available."
else
  echo 'export PATH="$HOME/.ai_cli_offline/bin:$PATH"' >> "$HOME/.bashrc"
  export PATH="$HOME/.ai_cli_offline/bin:$PATH"
  echo "[DONE] Added AI CLI to PATH. Restart terminal or source ~/.bashrc."
fi

echo "✅ Setup complete. You can now run:"
echo "   ai \"what ports are open\""
echo "   ai \"run netstat -tuln\""
echo "   ai \"save test.sh echo hello world\""
