# @function banb_service
# @description Ansible-like service management for systemd
# @param --name=STRING Service name(s). For multiple, use commas (e.g., nginx,sshd).
# @param --state=STRING One of: started, stopped, restarted, reloaded.
# @param --enabled=true|false Enable/disable service at boot.
# @param --daemon_reload=true|false Run 'systemctl daemon-reload' before applying state/enabled.
# @param --dry-run Print commands without executing.
# @param --become Execute commands via 'sudo' (system-wide).
# @param --user=USERNAME Run service in user session (systemctl --user). If USERNAME is given, run as that user.
# @param --verbose Print extra context (unit status hints).
# @return 0 on success, 1 on error
banb_service() {
  local name="" state="" enabled="" daemon_reload="" user_target=""
  local -a actions

  # Reset global variables for this function call
  _banb_reset_globals

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

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?
  
  # Parse module-specific args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) printf "%s\n" "$_help"; return 0 ;;
      --name=*) name="${1#*=}" ;;
      --state=*) state="${1#*=}" ;;
      --enabled=*) enabled="${1#*=}" ;;
      --daemon_reload=*) daemon_reload="${1#*=}" ;;
      --user=*) user_target="${1#*=}" ;;
      *) _banb_error "Unknown option: $1" 1 ;;
    esac
    shift
  done

  # Validate prereqs
  command -v systemctl >/dev/null 2>&1 || { printf "banb_service: systemctl not found.\n" >&2; return 2; }

  # Check permissions for system-wide operations
  if $BANB_BECOME && [[ "$EUID" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      _banb_error "sudo not available for privilege escalation"
      return 2
    fi
  fi

  # Validate required args
  if [[ -z "$name" || -z "$state" ]]; then
    _banb_error "--name and --state are required"
    return 1
  fi

  # Normalize booleans
  case "${enabled,,}" in ""|true|false) ;; *) _banb_error "--enabled must be true or false"; return 1 ;; esac
  case "${daemon_reload,,}" in ""|true|false) ;; *) _banb_error "--daemon_reload must be true or false"; return 1 ;; esac

  # Helper: run command with dry-run/become/user handling
  _run_systemctl() {
    local subcmd="$1" svc="$2"
    local -a cmd_array
    
    if $BANB_BECOME; then
      cmd_array=(sudo systemctl "$subcmd" "$svc")
    elif [[ -n "$user_target" ]]; then
      if [[ "$user_target" == "$(whoami)" ]]; then
        cmd_array=(systemctl --user "$subcmd" "$svc")
      else
        cmd_array=(sudo -u "$user_target" systemctl --user "$subcmd" "$svc")
      fi
    else
      cmd_array=(systemctl "$subcmd" "$svc")
    fi

    if $BANB_DRY_RUN; then
      printf "[DRY-RUN] %s\n" "${cmd_array[*]}"
      actions+=("${cmd_array[*]}")
      return 0
    fi

    "${cmd_array[@]}" || return 1
    actions+=("${cmd_array[*]}")
    return 0
  }

  # Optional daemon-reload first
  if [[ "${daemon_reload,,}" == "true" ]]; then
    _run_systemctl daemon-reload "" || { _banb_error "daemon-reload failed"; return 3; }
  fi

  # Process each service
  local IFS=','; read -r -a svcs <<< "$name"; IFS=$' \t\n'

  for svc in "${svcs[@]}"; do
    svc="${svc//[[:space:]]/}"  # Trim whitespace

    # Validate service name format
    if [[ ! "$svc" =~ ^[a-zA-Z0-9@_.-]+$ ]] || [[ -z "$svc" ]]; then
      _banb_error "invalid service name '$svc'"
      return 1
    fi

    local subcmd=""
    case "$state" in
      started)   subcmd="start" ;;
      stopped)   subcmd="stop" ;;
      restarted) subcmd="restart" ;;
      reloaded)  subcmd="reload" ;;
      *) _banb_error "invalid --state '$state'. See --help."; return 1 ;;
    esac

    $BANB_VERBOSE && _banb_info "Managing '$svc' with state '$state'..."
    if ! _run_systemctl "$subcmd" "$svc"; then
      _banb_error "state '$state' failed for '$svc'"
      # Check if service exists
      if ! systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
        _banb_warning "service '$svc' may not exist"
      fi
      return 3
    fi

    if [[ -n "$enabled" ]]; then
      case "${enabled,,}" in
        true)  _run_systemctl enable "$svc" || { _banb_error "enable failed for '$svc'"; return 3; } ;;
        false) _run_systemctl disable "$svc" || { _banb_error "disable failed for '$svc'"; return 3; } ;;
      esac
    fi

    if $BANB_VERBOSE && ! $BANB_DRY_RUN; then
      if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        _banb_info "  enabled: yes"
      else
        _banb_warning "  enabled: no/unknown"
      fi
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        _banb_info "  active:  yes"
      else
        _banb_warning "  active:  no"
      fi
    fi
  done

  if $dry_run; then
    printf "Planned actions (%d):\n" "${#actions[@]}"
    for a in "${actions[@]}"; do printf "  - %s\n" "$a"; done
  fi

  return 0
}
