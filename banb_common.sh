#!/bin/bash
# banb_common.sh - Common functions for banb modules
# Provides shared functionality to reduce code duplication across banb modules

# Global variables for common options
declare -g BANB_DRY_RUN=false
declare -g BANB_BECOME=false
declare -g BANB_VERBOSE=false

# Common error handling function
_banb_error() {
    local msg="$1"
    local code="${2:-1}"
    echo "❌ $msg" >&2
    return $code
}

# Common success message function
_banb_success() {
    local msg="$1"
    echo "✅ $msg"
}

# Common warning message function
_banb_warning() {
    local msg="$1"
    echo "⚠️ $msg"
}

# Common info message function
_banb_info() {
    local msg="$1"
    echo "ℹ️ $msg"
}

# Safe command execution with dry-run, become, and user support
_banb_run() {
    local cmd="$*"

    if $BANB_DRY_RUN; then
        echo "[DRY-RUN] $cmd"
        return 0
    fi

    # Split command into array for safe execution
    local -a cmd_array
    IFS=' ' read -r -a cmd_array <<< "$cmd"

    if $BANB_BECOME; then
        sudo "${cmd_array[@]}"
    else
        "${cmd_array[@]}"
    fi
}

# Parse common arguments and set global variables
_banb_parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) BANB_DRY_RUN=true ;;
            --become) BANB_BECOME=true ;;
            --verbose) BANB_VERBOSE=true ;;
            --help)
                _banb_show_help
                return 0
                ;;
            *)
                # Return unprocessed arguments
                echo "$1"
                ;;
        esac
        shift
    done
}

# Show common help message
_banb_show_help() {
    cat <<EOF
Common Options:
  --dry-run     Print commands without executing
  --become      Execute commands with sudo
  --verbose     Print extra context and information
  --help        Show this help message

EOF
}

# Validate boolean parameter
_banb_validate_bool() {
    local value="$1"
    local param_name="$2"

    case "${value,,}" in
        ""|true|false) return 0 ;;
        *) _banb_error "$param_name must be true or false" 1 ;;
    esac
}

# Validate file path for security
_banb_validate_path() {
    local path="$1"
    local type="$2"

    # Check for path traversal attempts
    if [[ "$path" =~ \.\./ || "$path" =~ /etc/passwd || "$path" =~ /etc/shadow ]]; then
        _banb_error "Invalid $type path '$path'" 1
        return 1
    fi

    # Check for absolute paths in sensitive locations
    if [[ "$path" =~ ^/(boot|sys|proc|dev) ]]; then
        _banb_error "$type path '$path' is in restricted system directory" 1
        return 1
    fi

    return 0
}

# Create secure temporary directory
_banb_create_tempdir() {
    local prefix="${1:-banb}"
    local tmpdir
    tmpdir=$(mktemp -d -t "${prefix}.XXXXXXXXXX")
    chmod 700 "$tmpdir"  # Restrict directory permissions
    echo "$tmpdir"
}

# Backup file with timestamp
_banb_backup_file() {
    local file="$1"
    local backup_file="${file}.bak.$(date +%s)"

    if [[ -e "$file" ]]; then
        _banb_run "cp -p '$file' '$backup_file'"
        _banb_info "Backup created: $backup_file"
    fi
}

# Check if command exists
_banb_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if user has sudo privileges
_banb_check_sudo() {
    if [[ "$EUID" -ne 0 ]] && ! _banb_command_exists sudo; then
        _banb_error "sudo not available for privilege escalation" 2
        return 1
    fi
    return 0
}

# Detect package manager with priority
_banb_detect_package_manager() {
    local -a tools=("pacman" "apt" "dnf" "yum" "zypper" "apk")

    for tool in "${tools[@]}"; do
        if _banb_command_exists "$tool"; then
            echo "$tool"
            return 0
        fi
    done

    _banb_error "No supported package manager found" 2
    return 1
}

# Reset global variables (for testing or reusing functions)
_banb_reset_globals() {
    BANB_DRY_RUN=false
    BANB_BECOME=false
    BANB_VERBOSE=false
}

# Load common functions
_banb_common_loaded=true