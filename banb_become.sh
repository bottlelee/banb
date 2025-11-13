banb_become() {
  local BECOME=false

  for arg in "$@"; do
    case $arg in
      --become=*) BECOME="${arg#*=}" ;;
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

  if [[ "$BECOME" == "true" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
      echo "🚫 This operation requires root privileges."
      echo "👉 Please run: sudo $0"
      exit 1
    else
      echo "✅ Running as root (become=true)"
    fi
  else
    if [[ "$EUID" -eq 0 ]]; then
      echo "🚫 This operation must be run as a non-root user."
      echo "👉 Please switch to a regular user and run: $0"
      exit 1
    else
      echo "✅ Running as non-root (become=false)"
    fi
  fi
}
