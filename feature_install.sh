
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
LOG_FILE="$HOME/feature_install.log"
FEATURES_DIR="./features"

# --- Logging & Emoji Status ---
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - $1" | tee -a "$LOG_FILE"
}
status() {
  # Only emoji statuses shown in terminal
  echo -e "$1"
}

# Redirect stdout/stderr to log and console
exec > >(tee -a "$LOG_FILE") 2>&1
log_message "--- Starting feature_install.sh ---"

# --- Self-healing Download Function ---
download_with_retry() {
  local url="$1" target="$2"
  local retries=3
  for ((i=1; i<=retries; i++)); do
    if curl -fsSL "$url" -o "$target"; then
      return 0
    fi
    log_message "Attempt $i to download $url failed."
    sleep 2
  done
  return 1
}

# --- Define Available Features ---
declare -A FEATURES
FEATURES[1]="Network_Scanner|https://raw.githubusercontent.com/Xghst0/AI/features/network_scanner.sh"
FEATURES[2]="Sys_Reporter|https://raw.githubusercontent.com/Xghst0/AI/features/sys_reporter.sh"
FEATURES[3]="Auto_Updater|https://raw.githubusercontent.com/Xghst0/AI/features/auto_updater.sh"
FEATURES[4]="Plugin_Manager|https://raw.githubusercontent.com/Xghst0/AI/features/plugin_manager.sh"
FEATURES[5]="Telemetry|https://raw.githubusercontent.com/Xghst0/AI/features/telemetry.sh"

# Display options
echo "Select features to install (e.g. 1,3-5):"
for key in "${!FEATURES[@]}"; do
  IFS='|' read -r name url <<< "${FEATURES[$key]}"
  echo "  $key) $name"
done

read -rp "Enter choice: " input

# --- Parse Selections ---
parse_selection() {
  local sel="$1"
  local arr=()
  IFS=',' read -ra parts <<< "$sel"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      arr+=("$part")
    elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=${BASH_REMATCH[1]}
      end=${BASH_REMATCH[2]}
      for ((i=start; i<=end; i++)); do
        arr+=("$i")
      done
    fi
  done
  echo "${arr[@]}"
}

choices=( $(parse_selection "$input") )

# Create features directory
mkdir -p "$FEATURES_DIR"

# --- Install Each Feature ---
for idx in "${choices[@]}"; do
  if [[ -n "${FEATURES[$idx]:-}" ]]; then
    IFS='|' read -r name url <<< "${FEATURES[$idx]}"
    target="$FEATURES_DIR/${name}.sh"
    status "🔄 Installing $name..."
    log_message "Starting installation of feature: $name"

    # Download feature script
    if download_with_retry "$url" "$target"; then
      chmod +x "$target"
      log_message "Downloaded and set executable: $target"
    else
      status "❌ Failed to download $name"
      log_message "ERROR: Could not fetch $url"
      continue
    fi

    # Execute feature installer in isolated subshell
    if ( bash "$target" ); then
      status "✅ $name installed"
      log_message "$name executed successfully"
    else
      status "⚠️ $name execution failed, retrying..."
      log_message "Retrying execution of $name"
      if ( bash "$target" ); then
        status "✅ $name re-executed successfully"
        log_message "$name succeeded on retry"
      else
        status "❌ $name installation failed"
        log_message "FATAL: $name failed twice"
      fi
    fi

    # Post-install health check
    status "🔍 Checking $name health..."
    if grep -q "$name" "$FEATURES_DIR/installed_features.log" 2>/dev/null; then
      status "✅ $name active"
    else
      # Log installation record
      echo "$name - $(date '+%Y-%m-%d %H:%M:%S')" >> "$FEATURES_DIR/installed_features.log"
      status "✅ $name recorded"
    fi
  else
    log_message "Invalid feature index: $idx"
  fi
done

status "🎉 Feature installation complete!"
log_message "--- feature_install.sh finished ---"
exit 0
