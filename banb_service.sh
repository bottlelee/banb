# @function banb_service
# @description Ansible-compatible service management module
# @param name=STRING Service name(s). For multiple, use commas (e.g., nginx,sshd).
# @param state=STRING One of: started, stopped, restarted, reloaded.
# @param enabled=yes|no Enable/disable service at boot.
# @param daemon_reload=yes|no Run 'systemctl daemon-reload' before applying state/enabled.
# @param use=STRING Service manager to use (systemd, sysvinit, upstart). Default: systemd.
# @param scope=STRING Service scope: system (default) or user.
# @param user=STRING Username for user scope services.
# @param sleep=INT Seconds to sleep between restart/stop and start operations.
# @param pattern=STRING Pattern to search for in process list when using pattern mode.
# @param arguments=STRING Additional arguments to pass to service manager.
# @param runlevel=STRING Runlevel to target (sysvinit only).
# @return 0 on success, 1 on error
banb_service() {
  local name="" state="" enabled="" daemon_reload="" use="systemd" scope="system" user="" sleep="" pattern="" arguments="" runlevel=""
  local -a actions

  # Reset global variables for this function call
  _banb_reset_globals

  # Print help and exit
  local _help="Usage:
  banb_service name=<svc[,svc2,...]> state=<started|stopped|restarted|reloaded>
               [enabled=<yes|no>] [daemon_reload=<yes|no>] [use=<systemd|sysvinit|upstart>]
               [sleep=<seconds>] [pattern=<pattern>] [arguments=<args>] [runlevel=<runlevel>]

Description:
  Manage system services in an Ansible-compatible way. Supports multiple services via comma-separated names.
  Idempotent intent, with explicit service manager calls mapped from 'state'.

Parameters:
  name=STRING              Service name(s). For multiple, use commas (e.g., nginx,sshd).
  state=STRING             One of: started, stopped, restarted, reloaded.
  enabled=yes|no           Enable/disable service at boot.
  daemon_reload=yes|no     Run 'systemctl daemon-reload' before applying state/enabled.
  use=STRING               Service manager to use (systemd, sysvinit, upstart). Default: systemd.
  sleep=INT                Seconds to sleep between restart/stop and start operations.
  pattern=STRING           Pattern to search for in process list when using pattern mode.
  arguments=STRING         Additional arguments to pass to service manager.
  runlevel=STRING          Runlevel to target (sysvinit only).
  --help                   Show this message.

Examples:
  banb_service name=nginx state=started enabled=yes
  banb_service name=nginx,sshd state=restarted daemon_reload=yes
  banb_service name=apache2 state=stopped enabled=no
  banb_service name=myapp state=started use=sysvinit
"

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?

  # Parse module-specific args (Ansible-style key=value)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) printf "%s\n" "$_help"; return 0 ;;
      name=*) name="${1#*=}" ;;
      state=*) state="${1#*=}" ;;
      enabled=*) enabled="${1#*=}" ;;
      daemon_reload=*) daemon_reload="${1#*=}" ;;
      use=*) use="${1#*=}" ;;
      scope=*) scope="${1#*=}" ;;
      user=*) user="${1#*=}" ;;
      sleep=*) sleep="${1#*=}" ;;
      pattern=*) pattern="${1#*=}" ;;
      arguments=*) arguments="${1#*=}" ;;
      runlevel=*) runlevel="${1#*=}" ;;
      *) _banb_error "Unknown parameter: $1" 1 ;;
    esac
    shift
  done

  # Validate required args
  if [[ -z "$name" || -z "$state" ]]; then
    _banb_error "name and state are required parameters"
    return 1
  fi

  # Validate parameter values
  case "${state,,}" in
    started|stopped|restarted|reloaded) ;;
    *) _banb_error "state must be one of: started, stopped, restarted, reloaded"; return 1 ;;
  esac

  case "${enabled,,}" in ""|yes|no) ;; *) _banb_error "enabled must be yes or no"; return 1 ;; esac
  case "${daemon_reload,,}" in ""|yes|no) ;; *) _banb_error "daemon_reload must be yes or no"; return 1 ;; esac
  case "${use,,}" in systemd|sysvinit|upstart) ;; *) _banb_error "use must be one of: systemd, sysvinit, upstart"; return 1 ;; esac
  case "${scope,,}" in ""|system|user) ;; *) _banb_error "scope must be system or user"; return 1 ;; esac

  # Validate user scope requirements
  if [[ "${scope,,}" == "user" && "${use,,}" != "systemd" ]]; then
    _banb_error "user scope is only supported with systemd service manager"
    return 1
  fi

  # Check service manager availability
  case "${use,,}" in
    systemd)
      command -v systemctl >/dev/null 2>&1 || { _banb_error "systemctl not found"; return 2; }
      ;;
    sysvinit)
      command -v service >/dev/null 2>&1 || { _banb_error "service command not found"; return 2; }
      ;;
    upstart)
      command -v initctl >/dev/null 2>&1 || { _banb_error "initctl not found"; return 2; }
      ;;
  esac

  # Helper: run command with dry-run/become/user handling
  _run_service_cmd() {
    local cmd="$1" svc="$2"
    local -a cmd_array

    case "${use,,}" in
      systemd)
        # Handle user scope
        if [[ "${scope,,}" == "user" ]]; then
          if [[ -n "$user" ]]; then
            # Run as specific user
            if $BANB_BECOME; then
              cmd_array=(sudo -u "$user" systemctl --user "$cmd" "$svc")
            else
              cmd_array=(systemctl --user "$cmd" "$svc")
            fi
          else
            # Run as current user
            if $BANB_BECOME; then
              cmd_array=(sudo systemctl --user "$cmd" "$svc")
            else
              cmd_array=(systemctl --user "$cmd" "$svc")
            fi
          fi
        else
          # System scope
          if $BANB_BECOME; then
            cmd_array=(sudo systemctl "$cmd" "$svc")
          else
            cmd_array=(systemctl "$cmd" "$svc")
          fi
        fi
        ;;
      sysvinit)
        if $BANB_BECOME; then
          cmd_array=(sudo service "$svc" "$cmd")
        else
          cmd_array=(service "$svc" "$cmd")
        fi
        ;;
      upstart)
        if $BANB_BECOME; then
          cmd_array=(sudo initctl "$cmd" "$svc")
        else
          cmd_array=(initctl "$cmd" "$svc")
        fi
        ;;
    esac

    # Add additional arguments if provided
    if [[ -n "$arguments" ]]; then
      IFS=' ' read -r -a extra_args <<< "$arguments"
      cmd_array+=("${extra_args[@]}")
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

  # Helper: check service status
  _check_service_status() {
    local svc="$1"

    case "${use,,}" in
      systemd)
        local status_cmd="systemctl"
        if $BANB_BECOME; then
          status_cmd="sudo systemctl"
        fi

        # Handle user scope
        if [[ "${scope,,}" == "user" ]]; then
          if [[ -n "$user" ]]; then
            if $BANB_BECOME; then
              status_cmd="sudo -u $user systemctl --user"
            else
              status_cmd="systemctl --user"
            fi
          else
            if $BANB_BECOME; then
              status_cmd="sudo systemctl --user"
            else
              status_cmd="systemctl --user"
            fi
          fi
        fi

        if $status_cmd is-active "$svc" >/dev/null 2>&1; then
          echo "active"
        else
          echo "inactive"
        fi
        ;;
      sysvinit)
        # Simple check for sysvinit services
        if pgrep -f "$svc" >/dev/null 2>&1; then
          echo "active"
        else
          echo "inactive"
        fi
        ;;
      upstart)
        local status_cmd="initctl"
        if $BANB_BECOME; then
          status_cmd="sudo initctl"
        fi

        if $status_cmd status "$svc" 2>/dev/null | grep -q running; then
          echo "active"
        else
          echo "inactive"
        fi
        ;;
    esac
  }

  # Optional daemon-reload first (systemd only)
  if [[ "${daemon_reload,,}" == "yes" && "${use,,}" == "systemd" ]]; then
    if $BANB_BECOME; then
      cmd_array=(sudo systemctl daemon-reload)
    else
      cmd_array=(systemctl daemon-reload)
    fi

    if $BANB_DRY_RUN; then
      printf "[DRY-RUN] %s\n" "${cmd_array[*]}"
      actions+=("${cmd_array[*]}")
    else
      "${cmd_array[@]}" || { _banb_error "daemon-reload failed"; return 3; }
      actions+=("${cmd_array[*]}")
    fi
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

    $BANB_VERBOSE && _banb_info "Managing '$svc' with state '$state' using $use..."

    # Map state to service manager commands
    local subcmd=""
    case "$state" in
      started)
        case "${use,,}" in
          systemd) subcmd="start" ;;
          sysvinit) subcmd="start" ;;
          upstart) subcmd="start" ;;
        esac
        ;;
      stopped)
        case "${use,,}" in
          systemd) subcmd="stop" ;;
          sysvinit) subcmd="stop" ;;
          upstart) subcmd="stop" ;;
        esac
        ;;
      restarted)
        case "${use,,}" in
          systemd) subcmd="restart" ;;
          sysvinit) subcmd="restart" ;;
          upstart) subcmd="restart" ;;
        esac
        ;;
      reloaded)
        case "${use,,}" in
          systemd) subcmd="reload" ;;
          sysvinit) subcmd="reload" ;;
          upstart) subcmd="reload" ;;
        esac
        ;;
    esac

    # Handle restart with sleep if specified
    if [[ "$state" == "restarted" && -n "$sleep" ]]; then
      if ! _run_service_cmd "stop" "$svc"; then
        _banb_error "stop failed for '$svc' during restart"
        return 3
      fi

      $BANB_VERBOSE && _banb_info "Sleeping for $sleep seconds..."
      if ! $BANB_DRY_RUN; then
        sleep "$sleep"
      fi

      if ! _run_service_cmd "start" "$svc"; then
        _banb_error "start failed for '$svc' during restart"
        return 3
      fi
    else
      # Normal operation
      if ! _run_service_cmd "$subcmd" "$svc"; then
        _banb_error "state '$state' failed for '$svc'"
        return 3
      fi
    fi

    # Handle enabled/disabled state
    if [[ -n "$enabled" ]]; then
      case "${use,,}" in
        systemd)
          case "${enabled,,}" in
            yes) _run_service_cmd "enable" "$svc" || { _banb_error "enable failed for '$svc'"; return 3; } ;;
            no) _run_service_cmd "disable" "$svc" || { _banb_error "disable failed for '$svc'"; return 3; } ;;
          esac
          ;;
        sysvinit)
          if [[ -n "$runlevel" ]]; then
            case "${enabled,,}" in
              yes)
                if $BANB_BECOME; then
                  cmd_array=(sudo update-rc.d "$svc" enable "$runlevel")
                else
                  cmd_array=(update-rc.d "$svc" enable "$runlevel")
                fi
                ;;
              no)
                if $BANB_BECOME; then
                  cmd_array=(sudo update-rc.d "$svc" disable)
                else
                  cmd_array=(update-rc.d "$svc" disable)
                fi
                ;;
            esac

            if $BANB_DRY_RUN; then
              printf "[DRY-RUN] %s\n" "${cmd_array[*]}"
              actions+=("${cmd_array[*]}")
            else
              "${cmd_array[@]}" || { _banb_error "${enabled,,} failed for '$svc'"; return 3; }
              actions+=("${cmd_array[*]}")
            fi
          fi
          ;;
      esac
    fi

    # Verbose status output
    if $BANB_VERBOSE && ! $BANB_DRY_RUN; then
      local current_status
      current_status=$(_check_service_status "$svc")
      _banb_info "  current status: $current_status"

      if [[ -n "$enabled" && "${use,,}" == "systemd" ]]; then
        local enabled_status
        if systemctl is-enabled "$svc" >/dev/null 2>&1; then
          enabled_status="enabled"
        else
          enabled_status="disabled"
        fi
        _banb_info "  enabled status: $enabled_status"
      fi
    fi
  done

  # Dry-run summary
  if $BANB_DRY_RUN; then
    printf "Planned actions (%d):\n" "${#actions[@]}"
    for a in "${actions[@]}"; do printf "  - %s\n" "$a"; done
  fi

  return 0
}