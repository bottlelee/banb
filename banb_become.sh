banb_become() {
  local BECOME=false

  for arg in "$@"; do
    case $arg in
      --become=*)
        BECOME="${arg#*=}"
        # Validate boolean value
        if [[ "$BECOME" != "true" && "$BECOME" != "false" ]]; then
          echo "Error: --become must be 'true' or 'false'"
          return 1
        fi
        ;;
      --help)
        cat <<EOF
Simulated Ansible 'become' check in Bash

Usage:
  banb_become --become=true|false

Options:
  --become=true     Require root privileges (simulate Ansible become)
  --become=false    Require non-root execution (simulate unprivileged task)
EOF
        return 0
        ;;
      *) echo "Unknown option: $arg"; return 1 ;;
    esac
  done

  # Check if become parameter was provided
  if [[ -z "$BECOME" ]]; then
    echo "Error: --become parameter is required"
    echo "Usage: banb_become --become=true|false"
    return 1
  fi

  if [[ "$BECOME" == "true" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
      echo "🚫 This operation requires root privileges."
      echo "👉 Please run the command with sudo privileges"
      return 1
    else
      echo "✅ Running as root (become=true)"
    fi
  else
    if [[ "$EUID" -eq 0 ]]; then
      echo "🚫 This operation must be run as a non-root user."
      echo "👉 Please switch to a regular user and run: $0"
      return 1
    else
      echo "✅ Running as non-root (become=false)"
    fi
  fi
}
