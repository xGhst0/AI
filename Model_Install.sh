#!/bin/bash
set -euo pipefail

LOG_FILE="${HOME}/install_model.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "$(date '+%F %T') - $1"; }
status() { echo -e "$1"; }

MODELS=(
  "1) TheBloke/llama2_7b_chat_uncensored-GGUF:q2_K (1B)"
  "2) mradermacher/Qwen2.5-0.5B-Instruct-uncensored-GGUF:q3_K (3B)"
  "3) TheBloke/WizardLM-7B-uncensored-GGUF:q4_K_M (7B)"
)

echo "Choose a model to install:"
for m in "${MODELS[@]}"; do
  echo "  $m"
done

read -rp "Enter 1, 2 or 3: " CHOICE
case "$CHOICE" in
  1) REPO="TheBloke/llama2_7b_chat_uncensored-GGUF"; FILE="llama2_7b_chat_uncensored.q2_K.gguf"; ;;
  2) REPO="mradermacher/Qwen2.5-0.5B-Instruct-uncensored-GGUF"; FILE="qwen2.5-0.5B-Instruct-uncensored.Q3_K.gguf"; ;;
  3) REPO="https://huggingface.co/TheBloke/WizardLM-7B-uncensored-GGUF/resolve/main/"; FILE="WizardLM-7B-uncensored.Q3_K_M.gguf"; ;;
  *) status "❌ Invalid choice. Exiting."; exit 1 ;;
esac

log "User selected $REPO / $FILE"
status "⬇️ Downloading model..."

download_with_retry() {
  local retries=3
  for ((i=1;i<=retries;i++)); do
    huggingface-cli download "$REPO" "$FILE" --local-dir . && return 0
    log "Attempt $i to download failed."
    sleep 2
  done
  return 1
}

if download_with_retry; then
  status "✅ Download complete"
  log "Model downloaded successfully"
else
  status "❌ Download failed after retries"
  log "ERROR: Model download failed"
  exit 1
fi

status "🔍 Verifying file integrity..."
if [[ -s "./$FILE" ]]; then
  status "✅ File exists and non-zero size"
  log "File integrity check passed"
else
  status "⚠️ File is missing or empty, retrying..."
  log "File check failed"
  rm -f "./$FILE"
  if download_with_retry; then
    status "✅ Retry download success"
    log "Retry succeeded"
  else
    status "❌ Retry failed. Exiting."
    log "ERROR: Retry download failed"
    exit 1
  fi
fi

status "🧪 Testing model load with llama.cpp..."
if ./main -m "$FILE" -n 1 -p "Hello" &> test_output.txt; then
  status "✅ Test inference OK"
  log "Model load test succeeded"
else
  status "⚠️ Test inference failed"
  log "ERROR: Model load test failed, attempting redownload"
  rm -f "./$FILE"
  if download_with_retry; then
    status "🔁 Downloading again..."
    if ./main -m "$FILE" -n 1 -p "Hello"; then
      status "✅ Second load test OK"
      log "Model load succeeded on retry"
    else
      status "❌ Load fails again. Please investigate."
      log "FATAL: Model test failed twice"
      exit 1
    fi
  else
    status "❌ Redownload failed. Exiting."
    log "FATAL: Redownload failed"
    exit 1
  fi
fi

status "🎉 Model installed and verified!"
log "Installation completed successfully."

exit 0
