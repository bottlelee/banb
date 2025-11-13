# banb_service: Ansible-like service management for systemd
# Supports: --name, --state, --enabled, --daemon_reload, --dry-run, --become, --verbose, --help
banb_service() {
  local name="" state="" enabled="" daemon_reload=""
  local dry_run=false become=false verbose=false
  local -a actions

  # Print help and exit
  local _help="Usage:
  banb_service --name=<svc[,svc2,...]> --state=<started|stopped|restarted|reloaded> [--enabled=<true|false>] [--daemon_reload=<true|false>] [--dry-run] [--become] [--verbose]

Description:
  Manage systemd services in an Ansible-like way. Supports multiple services via comma-separated names.
  Idempotent intent, with explicit systemctl calls mapped from 'state'. Optionally reloads systemd daemon.

Parameters:
  --name=STRING            Service name(s). For multiple, use commas (e.g., nginx,sshd).
  --state=STRING           One of: started, stopped, restarted, reloaded.
  --enabled=true|false     Enable/disable service at boot.
  --daemon_reload=true|false  Run 'systemctl daemon-reload' before applying state/enabled.
  --dry-run                Print commands without executing.
  --become                 Execute commands via 'sudo'.
  --verbose                Print extra context (unit status hints).
  --help                   Show this message.

Examples:
  banb_service --name=nginx --state=started --enabled=true
  banb_service --name=nginx,sshd --state=restarted --dry-run
  banb_service --name=nginx --state=reloaded --daemon_reload=true --become
"

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) printf "%s\n" "$_help"; return 0 ;;
      --name=*) name="${1#*=}" ;;
      --state=*) state="${1#*=}" ;;
      --enabled=*) enabled="${1#*=}" ;;
      --daemon_reload=*) daemon_reload="${1#*=}" ;;
      --dry-run) dry_run=true ;;
      --become) become=true ;;
      --verbose) verbose=true ;;
      *) printf "banb_service: unknown option: %s\nTry --help for usage.\n" "$1" >&2; return 1 ;;
    esac
    shift
  done

  # Validate prereqs
  command -v systemctl >/dev/null 2>&1 || { printf "banb_service: systemctl not found.\n" >&2; return 2; }

  # Validate required args
  [[ -z "$name" || -z "$state" ]] && { printf "banb_service: --name and --state are required.\n" >&2; return 1; }

  # Normalize booleans
  case "${enabled,,}" in ""|true|false) ;; *) printf "banb_service: --enabled must be true or false.\n" >&2; return 1 ;; esac
  case "${daemon_reload,,}" in ""|true|false) ;; *) printf "banb_service: --daemon_reload must be true or false.\n" >&2; return 1 ;; esac

  # Helper: run command with dry-run/become handling
  _run() {
    local cmd="$*"
    if $dry_run; then
      printf "[DRY-RUN] %s\n" "$cmd"
      actions+=("$cmd")
      return 0
    fi
    if $become; then
      sudo bash -c "$cmd" || return 1
    else
      bash -c "$cmd" || return 1
    fi
    actions+=("$cmd")
    return 0
  }

  # Optional daemon-reload first
  if [[ "${daemon_reload,,}" == "true" ]]; then
    _run "systemctl daemon-reload" || { printf "banb_service: daemon-reload failed.\n" >&2; return 3; }
  fi

  # Process each service
  local IFS=','; read -r -a svcs <<< "$name"; IFS=$' \t\n'

  for svc in "${svcs[@]}"; do
    # Trim whitespace
    svc="${svc//[[:space:]]/}"

    # Map state to systemctl subcommand
    local subcmd=""
    case "$state" in
      started)   subcmd="start" ;;
      stopped)   subcmd="stop" ;;
      restarted) subcmd="restart" ;;
      reloaded)  subcmd="reload" ;;
      *) printf "banb_service: invalid --state '%s'. See --help.\n" "$state" >&2; return 1 ;;
    esac

    # Execute state
    $verbose && printf "Managing '%s' with state '%s'...\n" "$svc" "$state"
    _run "systemctl $subcmd '$svc'" || { printf "banb_service: state '%s' failed for '%s'.\n" "$state" "$svc" >&2; return 3; }

    # Enable/disable if requested
    if [[ -n "$enabled" ]]; then
      case "${enabled,,}" in
        true)  _run "systemctl enable '$svc'" || { printf "banb_service: enable failed for '%s'.\n" "$svc" >&2; return 3; } ;;
        false) _run "systemctl disable '$svc'" || { printf "banb_service: disable failed for '%s'.\n" "$svc" >&2; return 3; } ;;
      esac
    fi

    # Optional verbose status hint (non-fatal)
    if $verbose && ! $dry_run; then
      systemctl is-enabled "$svc" >/dev/null 2>&1 && printf "  enabled: yes\n" || printf "  enabled: no/unknown\n"
      systemctl is-active "$svc"  >/dev/null 2>&1 && printf "  active:  yes\n" || printf "  active:  no\n"
    fi
  done

  # Summary
  if $dry_run; then
    printf "Planned actions (%d):\n" "${#actions[@]}"
    for a in "${actions[@]}"; do printf "  - %s\n" "$a"; done
  fi

  return 0
}
