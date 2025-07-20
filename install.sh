#!/bin/bash

# --- Configuration ---

BASE_URL_MAIN="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main"
BASE_URL_SUB="https://raw.githubusercontent.com/xGhst0/AI/refs/heads/main"

INSTALL_SH_URL="${BASE_URL_MAIN}/install.sh"
MODEL_INSTALL_URL="${BASE_URL_SUB}/Model_Install.sh"
WRAPPER_INSTALL_URL="${BASE_URL_SUB}/Wrapper_Install.sh"
FEATURE_INSTALL_URL="${BASE_URL_SUB}/Feature_Install.sh"

# Local directories for dependent scripts and their requirements.txt
MODEL_INSTALL_DIR="./model_install"
WRAPPER_INSTALL_DIR="./wrapper_install"
FEATURE_INSTALL_DIR="./feature_install"

# Log file configuration
# Changed to user's home directory to avoid permission issues when running as non-root.
LOG_FILE="$HOME/install.log"

# --- Script Version (for self-update) ---
# This version string is embedded in the script for easy extraction and comparison.
SCRIPT_VERSION="1.0.3"

# --- Logging Functions ---
# Function to log messages with timestamps and levels
# Arguments: $1 = Log Level (INFO, WARN, ERROR, FATAL), $2 = Message
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" | tee -a "$LOG_FILE"
}

# Function to handle errors caught by trap
log_error() {
    local last_command="$BASH_COMMAND"
    local line_number="$LINENO"
    log_message "ERROR" "Script failed at line $line_number during command: '$last_command'. Exiting."
    exit 1
}

# Set up error trap: execute log_error function on any command failure
trap log_error ERR

# Redirect all stdout and stderr to the log file, and also to console via tee
# This ensures all output is captured for auditing and debugging.
# Ensure the log file can be created/written to before redirection.
mkdir -p "$(dirname "$LOG_FILE")" # Ensure the directory for the log file exists
touch "$LOG_FILE" # Create the log file if it doesn't exist and set initial permissions
chmod 644 "$LOG_FILE" # Ensure appropriate permissions for the log file

exec > >(tee -a "$LOG_FILE") 2>&1

log_message "INFO" "--- Script Started: install.sh (Version: $SCRIPT_VERSION) ---"

# --- Essential System Checks ---
# Function to check for required commands
check_command() {
    local cmd="$1"
    log_message "INFO" "Checking for required command: $cmd..."
    # Fix: Ensure space between 'if' and '!'
    if ! command -v "$cmd" &> /dev/null; then
        log_message "FATAL" "Error: '$cmd' is not installed. Please install it to proceed."
        exit 1
    fi
    log_message "INFO" "'$cmd' found."
}

# Perform checks for critical utilities
check_command "curl"
check_command "wget"
check_command "git"
check_command "pip"

# --- GitHub URL Transformation Function ---
# Converts a GitHub 'blob' URL to a 'raw' URL for direct download.
# Arguments: $1 = GitHub blob URL
get_raw_url() {
    local blob_url="$1"
    # Replace 'blob' with 'raw' and 'github.com' with 'raw.githubusercontent.com'
    # This is crucial for curl/wget to download the raw file content, not the HTML page.
    echo "$blob_url" | sed 's/github.com/raw.githubusercontent.com/' | sed 's/\/blob\//\/raw\//'
}

# --- Version Comparison Function ---
# Compares two dot-separated version strings (e.g., "1.2.3" vs "1.2.10").
# Returns: 0 if versions are equal, 1 if $1 > $2, 2 if $1 < $2.
# Adapted from [10]
vercomp() {
    if [[ "$1" == "$2" ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)

    # Fill empty fields in ver1 with zeros to match ver2's length
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    # Compare field-by-field
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # Fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        # Use 10# to force base-10 numeric comparison, preventing issues with leading zeros
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1 # ver1 is greater
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2 # ver1 is less
        fi
    done
    return 0 # versions are equal
}

# --- Self-Update Logic for install.sh ---
perform_self_update() {
    log_message "INFO" "Checking for updates for install.sh..."
    local current_script_path="$(readlink -f "$0")"
    local remote_install_sh_raw_url=$(get_raw_url "$INSTALL_SH_URL")

    # Extract current local version
    local local_version=$(grep -m 1 '^SCRIPT_VERSION=' "$current_script_path" | cut -d'"' -f2)
    if [ -z "$local_version" ]; then
        log_message "WARN" "Could not extract local SCRIPT_VERSION from $current_script_path. Skipping self-update check."
        return 0
    fi
    log_message "INFO" "Current local install.sh version: $local_version"

    # Download remote script content temporarily and extract its version
    local temp_remote_script="/tmp/install_remote.sh.$$"
    if command -v "curl" &> /dev/null; then
        curl -s -o "$temp_remote_script" "$remote_install_sh_raw_url"
    elif command -v "wget" &> /dev/null; then
        wget -qO "$temp_remote_script" "$remote_install_sh_raw_url"
    else
        log_message "WARN" "Neither curl nor wget found. Cannot check for remote updates."
        return 0
    fi

    # Fix: Ensure space between '[' and '!'
    if [ ! -f "$temp_remote_script" ]; then
        log_message "WARN" "Failed to download remote install.sh for update check."
        return 0
    fi

    local remote_version=$(grep -m 1 '^SCRIPT_VERSION=' "$temp_remote_script" | cut -d'"' -f2)
    rm -f "$temp_remote_script" # Clean up temporary file

    if [ -z "$remote_version" ]; then
        log_message "WARN" "Could not extract remote SCRIPT_VERSION from $remote_install_sh_raw_url. Skipping self-update."
        return 0
    fi
    log_message "INFO" "Remote install.sh version: $remote_version"

    vercomp "$local_version" "$remote_version"
    local comp_result=$?

    if [ "$comp_result" -eq 2 ]; then # local < remote
        log_message "INFO" "Newer version of install.sh available ($remote_version > $local_version). Updating..."
        local backup_file="${current_script_path}.$(date +%Y%m%d%H%M%S).bak"
        log_message "INFO" "Backing up current install.sh to $backup_file"
        cp "$current_script_path" "$backup_file"

        log_message "INFO" "Downloading new install.sh from $remote_install_sh_raw_url"
        if command -v "curl" &> /dev/null; then
            curl -s -o "$current_script_path" "$remote_install_sh_raw_url"
        else # wget must be available as checked earlier
            wget -qO "$current_script_path" "$remote_install_sh_raw_url"
        fi

        chmod +x "$current_script_path" # Ensure new script is executable

        log_message "INFO" "install.sh updated successfully. Re-executing with new version..."
        # Re-execute the script to use the newly downloaded version
        # This is critical for applying updates without manual intervention.
        exec "$current_script_path" "$@"
        log_message "FATAL" "Re-execution failed. This message should not be seen." # Should not reach here
    elif [ "$comp_result" -eq 1 ]; then # local > remote
        log_message "INFO" "Local install.sh version ($local_version) is newer than remote ($remote_version). No update needed."
    else # local == remote
        log_message "INFO" "install.sh is already up-to-date (Version: $local_version)."
    fi
}

# Run self-update check
perform_self_update

# --- Sub-Script Management (Download and Execute) ---
# Defines an associative array for sub-scripts: [script_name]="URL;Local_Path"
declare -A SUB_SCRIPTS
SUB_SCRIPTS["Model_Install.sh"]="${MODEL_INSTALL_URL};${MODEL_INSTALL_DIR}/Model_Install.sh"
# Fix: Corrected assignment for Wrapper_Install.sh to use associative array syntax
SUB_SCRIPTS["Wrapper_Install.sh"]="${WRAPPER_INSTALL_URL};${WRAPPER_INSTALL_DIR}/Wrapper_Install.sh"
SUB_SCRIPTS["Feature_Install.sh"]="${FEATURE_INSTALL_URL};${FEATURE_INSTALL_DIR}/Feature_Install.sh"

install_sub_script() {
    local script_name="$1"
    local script_info="${SUB_SCRIPTS[$script_name]}"
    local remote_blob_url=$(echo "$script_info" | cut -d';' -f1)
    local local_path=$(echo "$script_info" | cut -d';' -f2)
    local local_dir=$(dirname "$local_path")
    local remote_raw_url=$(get_raw_url "$remote_blob_url")

    log_message "INFO" "Processing sub-script: $script_name"
    log_message "INFO" "  Remote URL: $remote_raw_url"
    log_message "INFO" "  Local Path: $local_path"

    mkdir -p "$local_dir" # Ensure local directory exists

    log_message "INFO" "Downloading $script_name..."
    if command -v "curl" &> /dev/null; then
        curl -s -o "$local_path" "$remote_raw_url"
    else # wget must be available
        wget -qO "$local_path" "$remote_raw_url"
    fi

    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to download $script_name from $remote_raw_url."
        return 1
    fi
    chmod +x "$local_path" # Ensure downloaded script is executable
    log_message "INFO" "$script_name downloaded and made executable."

    # Execute the sub-script
    log_message "INFO" "Executing $script_name..."
    if bash "$local_path"; then
        log_message "INFO" "$script_name executed successfully."
    else
        log_message "ERROR" "$script_name execution failed."
        return 1
    fi

    # Check and install Python requirements for the sub-script
    local requirements_file="${local_dir}/requirements.txt"
    if [ -f "$requirements_file" ]; then
        log_message "INFO" "Found requirements.txt for $script_name. Installing Python dependencies..."
        # Prioritize pip3 if available, otherwise use pip
        local pip_cmd="pip"
        if command -v "pip3" &> /dev/null; then
            pip_cmd="pip3"
        fi

        if "$pip_cmd" install -r "$requirements_file"; then
            log_message "INFO" "Python dependencies for $script_name installed successfully."
        else
            log_message "ERROR" "Failed to install Python dependencies for $script_name from $requirements_file."
            return 1
        fi
    else
        log_message "INFO" "No requirements.txt found for $script_name. Skipping Python dependency installation."
    fi

    return 0
}

# Iterate and process each sub-script
for script_name in "${!SUB_SCRIPTS[@]}"; do
    install_sub_script "$script_name"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Aborting due to failure in processing $script_name."
        exit 1
    fi
done

# --- Automated Cron Job Setup ---
setup_daily_cron() {
    log_message "INFO" "Checking and setting up daily cron job for install.sh..."
    local current_script_path="$(readlink -f "$0")"
    local cron_entry="0 2 * * * $current_script_path >> $LOG_FILE 2>&1" # Daily at 2 AM, output to log

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -Fq "$current_script_path"; then
        log_message "INFO" "Daily cron job for install.sh already exists."
    else
        log_message "INFO" "Adding daily cron job for install.sh to run at 2:00 AM."
        # Add the cron job. (crontab -l; echo...) | crontab - is an idempotent way to add.
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        if [ $? -eq 0 ]; then
            log_message "INFO" "Cron job added successfully: '$cron_entry'"
        else
            log_message "ERROR" "Failed to add cron job for install.sh."
            return 1
        fi
    fi
    return 0
}

# Run cron setup
setup_daily_cron

# --- Post-Installation Validation and Reporting ---
run_validation_tests() {
    log_message "INFO" "Running post-installation validation tests..."
    # Placeholder for actual tests. Replace with your test commands.
    # Example: if you have a test script at./tests/run_all_tests.sh
    # Or a Python test suite: python -m pytest./tests/
    
    # Simulate a successful test
    log_message "INFO" "Simulating test: Component A functionality check..."
    sleep 1
    echo "Component A: All checks passed. SUCCESS"
    
    # Simulate a potentially failing test
    log_message "INFO" "Simulating test: Database connection check..."
    sleep 1
    local test_output="Database: Connection failed. ERROR" # Example of error output
    echo "$test_output"

    # Example of checking test output for success/failure keywords
    if echo "$test_output" | grep -q "ERROR"; then
        log_message "ERROR" "Validation test for Database connection failed."
        return 1
    else
        log_message "INFO" "Validation test for Database connection passed."
    fi

    # Add more actual test commands here
    # Example: /path/to/your/test_script.sh
    # if /path/to/your/test_script.sh; then
    #    log_message "INFO" "Custom test script executed successfully."
    # else
    #    log_message "ERROR" "Custom test script failed."
    #    return 1
    # fi

    log_message "INFO" "All validation tests completed."
    return 0
}

# Run validation tests
if run_validation_tests; then
    log_message "INFO" "Overall installation and validation: SUCCESS"
else
    log_message "ERROR" "Overall installation and validation: FAILED"
fi

log_message "INFO" "--- Script Finished: install.sh ---"

exit 0
