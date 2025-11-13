# banb_service: Ansible-like service management for systemd
# Supports: --name, --state, --enabled, --daemon_reload, --dry-run, --become, --user, --verbose, --help
banb_service() {
  local name="" state="" enabled="" daemon_reload=""
  local dry_run=false become=false verbose=false user_target=""
  local -a actions

  # Print help and exit
  local _help="Usage:
  banb_service --name=<svc[,svc2,...]> --state=<started|stopped|restarted|reloaded>
               [--enabled=<true|false>] [--daemon_reload=<true|false>]
               [--dry-run] [--become] [--user=<username>] [--verbose]

Description:
  Manage systemd services in an Ansible-like way. Supports multiple services via comma-separated names.
  Idempotent intent, with explicit systemctl calls mapped from 'state'. Optionally reloads systemd daemon.

Parameters:
  --name=STRING            Service name(s). For multiple, use commas (e.g., nginx,sshd).
  --state=STRING           One of: started, stopped, restarted, reloaded.
  --enabled=true|false     Enable/disable service at boot.
  --daemon_reload=true|false  Run 'systemctl daemon-reload' before applying state/enabled.
  --dry-run                Print commands without executing.
  --become                 Execute commands via 'sudo' (system-wide).
  --user=USERNAME          Run service in user session (systemctl --user). If USERNAME is given, run as that user.
  --verbose                Print extra context (unit status hints).
  --help                   Show this message.

Examples:
  banb_service --name=nginx --state=started --enabled=true --become
  banb_service --name=myapp --state=started --user=$(whoami)
  banb_service --name=myapp --state=restarted --user=alice
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
      --user=*) user_target="${1#*=}" ;;
      --verbose) verbose=true ;;
      *) printf "banb_service: unknown option: %s\nTry --help for usage.\n" "$1" >&2; return 1 ;;
    esac
    shift
  done

  # Validate prereqs
  command -v systemctl >/dev/null 2>&1 || { printf "banb_service: systemctl not found.\n" >&2; return 2; }

  # Check permissions for system-wide operations
  if $become && [[ "$EUID" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      printf "banb_service: sudo not available for privilege escalation.\n" >&2
      return 2
    fi
  fi

  # Validate required args
  [[ -z "$name" || -z "$state" ]] && { printf "banb_service: --name and --state are required.\n" >&2; return 1; }

  # Normalize booleans
  case "${enabled,,}" in ""|true|false) ;; *) printf "banb_service: --enabled must be true or false.\n" >&2; return 1 ;; esac
  case "${daemon_reload,,}" in ""|true|false) ;; *) printf "banb_service: --daemon_reload must be true or false.\n" >&2; return 1 ;; esac

  # Helper: run command with dry-run/become/user handling
  _run_systemctl() {
    local subcmd="$1" svc="$2"
    local cmd=""
    if $become; then
      cmd="sudo systemctl $subcmd $svc"
    elif [[ -n "$user_target" ]]; then
      if [[ "$user_target" == "$(whoami)" ]]; then
        cmd="systemctl --user $subcmd $svc"
      else
        cmd="sudo -u $user_target systemctl --user $subcmd $svc"
      fi
    else
      cmd="systemctl $subcmd $svc"
    fi

    if $dry_run; then
      printf "[DRY-RUN] %s\n" "$cmd"
      actions+=("$cmd")
      return 0
    fi

    # Split command into array for safe execution
    local -a cmd_array
    IFS=' ' read -r -a cmd_array <<< "$cmd"
    "${cmd_array[@]}" || return 1
    actions+=("$cmd")
    return 0
  }

  # Optional daemon-reload first
  if [[ "${daemon_reload,,}" == "true" ]]; then
    _run_systemctl daemon-reload "" || { printf "banb_service: daemon-reload failed.\n" >&2; return 3; }
  fi

  # Process each service
  local IFS=','; read -r -a svcs <<< "$name"; IFS=$' \t\n'

  for svc in "${svcs[@]}"; do
    svc="${svc//[[:space:]]/}"  # Trim whitespace

    # Validate service name format
    if [[ ! "$svc" =~ ^[a-zA-Z0-9@_.-]+$ ]] || [[ -z "$svc" ]]; then
      printf "banb_service: invalid service name '%s'.\n" "$svc" >&2
      return 1
    fi

    local subcmd=""
    case "$state" in
      started)   subcmd="start" ;;
      stopped)   subcmd="stop" ;;
      restarted) subcmd="restart" ;;
      reloaded)  subcmd="reload" ;;
      *) printf "banb_service: invalid --state '%s'. See --help.\n" "$state" >&2; return 1 ;;
    esac

    $verbose && printf "Managing '%s' with state '%s'...\n" "$svc" "$state"
    if ! _run_systemctl "$subcmd" "$svc"; then
      printf "banb_service: state '%s' failed for '%s'.\n" "$state" "$svc" >&2
      # Check if service exists
      if ! systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
        printf "  Hint: service '%s' may not exist.\n" "$svc" >&2
    fi
      return 3
    fi

    if [[ -n "$enabled" ]]; then
      case "${enabled,,}" in
        true)  _run_systemctl enable "$svc" || { printf "banb_service: enable failed for '%s'.\n" "$svc" >&2; return 3; } ;;
        false) _run_systemctl disable "$svc" || { printf "banb_service: disable failed for '%s'.\n" "$svc" >&2; return 3; } ;;
      esac
    fi

    if $verbose && ! $dry_run; then
      if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        printf "  enabled: yes\n"
      else
        printf "  enabled: no/unknown\n"
      fi
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        printf "  active:  yes\n"
      else
        printf "  active:  no\n"
      fi
    fi
  done

  if $dry_run; then
    printf "Planned actions (%d):\n" "${#actions[@]}"
    for a in "${actions[@]}"; do printf "  - %s\n" "$a"; done
  fi

  return 0
}
