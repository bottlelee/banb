# @function banb_podman
# @description Ansible-compatible Podman container management module
# @param name=STRING Container name (required).
# @param state=STRING Container state: started, stopped, absent, killed, restarted, reloaded, present.
# @param image=STRING Image to use for the container.
# @param command=STRING Command to run in the container.
# @param detach=yes|no Run container in detached mode. Default: yes.
# @param privileged=yes|no Give extended privileges to the container. Default: no.
# @param restart_policy=STRING Restart policy: no, on-failure, always, unless-stopped.
# @param restart_retries=INT Number of retries for restart policy. Default: 10.
# @param user=STRING Username or UID to run the container as.
# @param volumes=STRING Volume mounts in format "host_path:container_path:mode".
# @param ports=STRING Port mappings in format "host_port:container_port/protocol".
# @param env=STRING Environment variables in format "VAR=value".
# @param env_file=STRING Path to environment file.
# @param network=STRING Connect container to network.
# @param dns=STRING Set custom DNS servers.
# @param dns_search=STRING Set custom DNS search domains.
# @param hostname=STRING Container hostname.
# @param cap_add=STRING Add capabilities to the container.
# @param cap_drop=STRING Drop capabilities from the container.
# @param security_opts=STRING Security options.
# @param sysctls=STRING Sysctl options.
# @param publish_all=yes|no Publish all exposed ports to random ports. Default: no.
# @param force_restart=yes|no Force restart even if container is already running. Default: no.
# @param recreate=yes|no Recreate container when image changes. Default: no.
# @param pull=yes|no Pull image before running. Default: yes.
# @param debug=yes|no Enable debug output. Default: no.
# @return 0 on success, 1 on error
banb_podman() {
  local name="" state="" image="" command="" detach="yes" privileged="no" restart_policy="" restart_retries="10"
  local user="" volumes="" ports="" env="" env_file="" network="" dns="" dns_search="" hostname=""
  local cap_add="" cap_drop="" security_opts="" sysctls="" publish_all="no" force_restart="no"
  local recreate="no" pull="yes" debug="no"
  local -a actions

  # Reset global variables for this function call
  _banb_reset_globals

  # Print help and exit
  local _help="Usage:
  banb_podman name=<container_name> state=<state> [image=<image>] [command=<command>]
               [detach=<yes|no>] [privileged=<yes|no>] [restart_policy=<policy>]
               [restart_retries=<number>] [user=<user>] [volumes=<mounts>] [ports=<mappings>]
               [env=<variables>] [env_file=<path>] [network=<network>] [dns=<servers>]
               [dns_search=<domains>] [hostname=<hostname>] [cap_add=<capabilities>]
               [cap_drop=<capabilities>] [security_opts=<options>] [sysctls=<sysctls>]
               [publish_all=<yes|no>] [force_restart=<yes|no>] [recreate=<yes|no>]
               [pull=<yes|no>] [debug=<yes|no>]

Description:
  Manage Podman containers in an Ansible-compatible way. Supports container lifecycle management,
  image management, and various container configuration options.

Parameters:
  name=STRING              Container name (required).
  state=STRING             Container state: started, stopped, absent, killed, restarted, reloaded, present.
  image=STRING             Image to use for the container.
  command=STRING           Command to run in the container.
  detach=yes|no            Run container in detached mode. Default: yes.
  privileged=yes|no        Give extended privileges to the container. Default: no.
  restart_policy=STRING    Restart policy: no, on-failure, always, unless-stopped.
  restart_retries=INT       Number of retries for restart policy. Default: 10.
  user=STRING              Username or UID to run the container as.
  volumes=STRING           Volume mounts in format \"host_path:container_path:mode\".
  ports=STRING             Port mappings in format \"host_port:container_port/protocol\".
  env=STRING               Environment variables in format \"VAR=value\".
  env_file=STRING          Path to environment file.
  network=STRING           Connect container to network.
  dns=STRING               Set custom DNS servers.
  dns_search=STRING        Set custom DNS search domains.
  hostname=STRING          Container hostname.
  cap_add=STRING           Add capabilities to the container.
  cap_drop=STRING          Drop capabilities from the container.
  security_opts=STRING     Security options.
  sysctls=STRING           Sysctl options.
  publish_all=yes|no       Publish all exposed ports to random ports. Default: no.
  force_restart=yes|no     Force restart even if container is already running. Default: no.
  recreate=yes|no          Recreate container when image changes. Default: no.
  pull=yes|no              Pull image before running. Default: yes.
  debug=yes|no             Enable debug output. Default: no.
  --help                   Show this message.

Examples:
  banb_podman name=nginx state=started image=nginx:latest
  banb_podman name=redis state=stopped
  banb_podman name=app state=absent
  banb_podman name=web state=started image=nginx ports=80:80 volumes=/data:/var/www
  banb_podman name=db state=started image=postgres env=POSTGRES_PASSWORD=secret
"

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?

  # Parse module-specific args (Ansible-style key=value without -- prefix)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      help) printf "%s\n" "$_help"; return 0 ;;
      name=*) name="${1#*=}" ;;
      state=*) state="${1#*=}" ;;
      image=*) image="${1#*=}" ;;
      command=*) command="${1#*=}" ;;
      detach=*) detach="${1#*=}" ;;
      privileged=*) privileged="${1#*=}" ;;
      restart_policy=*) restart_policy="${1#*=}" ;;
      restart_retries=*) restart_retries="${1#*=}" ;;
      user=*) user="${1#*=}" ;;
      volumes=*) volumes="${1#*=}" ;;
      ports=*) ports="${1#*=}" ;;
      env=*) env="${1#*=}" ;;
      env_file=*) env_file="${1#*=}" ;;
      network=*) network="${1#*=}" ;;
      dns=*) dns="${1#*=}" ;;
      dns_search=*) dns_search="${1#*=}" ;;
      hostname=*) hostname="${1#*=}" ;;
      cap_add=*) cap_add="${1#*=}" ;;
      cap_drop=*) cap_drop="${1#*=}" ;;
      security_opts=*) security_opts="${1#*=}" ;;
      sysctls=*) sysctls="${1#*=}" ;;
      publish_all=*) publish_all="${1#*=}" ;;
      force_restart=*) force_restart="${1#*=}" ;;
      recreate=*) recreate="${1#*=}" ;;
      pull=*) pull="${1#*=}" ;;
      debug=*) debug="${1#*=}" ;;
      *) _banb_error "Invalid parameter format: $1 (should be key=value)"; return 1 ;;
    esac
    shift
  done

  # Validate required args
  if [[ -z "$name" ]]; then
    _banb_error "name parameter is required"
    return 1
  fi

  if [[ -z "$state" ]]; then
    _banb_error "state parameter is required"
    return 1
  fi

  # Validate parameter values
  case "${state,,}" in
    started|stopped|absent|killed|restarted|reloaded|present) ;;
    *) _banb_error "state must be one of: started, stopped, absent, killed, restarted, reloaded, present"; return 1 ;;
  esac

  # Validate boolean parameters
  for param in detach privileged publish_all force_restart recreate pull debug; do
    case "${!param,,}" in ""|yes|no) ;; *) _banb_error "$param must be yes or no"; return 1 ;; esac
  done

  # Check Podman availability
  command -v podman >/dev/null 2>&1 || { _banb_error "podman not found"; return 2; }

  # Helper: run podman command with dry-run/become handling
  _run_podman_cmd() {
    local -a cmd_array=(podman "$@")

    if $BANB_DRY_RUN; then
      printf "[DRY-RUN] %s\n" "${cmd_array[*]}"
      actions+=("${cmd_array[*]}")
      return 0
    fi

    "${cmd_array[@]}" || return 1
    actions+=("${cmd_array[*]}")
    return 0
  }

  # Helper: check if container exists
  _container_exists() {
    local container_name="$1"
    podman ps -a --format "table {{.Names}}" 2>/dev/null | grep -q "^$container_name$"
  }

  # Helper: check container status
  _container_status() {
    local container_name="$1"
    if _container_exists "$container_name"; then
      if podman ps --format "table {{.Names}}" 2>/dev/null | grep -q "^$container_name$"; then
        echo "running"
      else
        echo "stopped"
      fi
    else
      echo "absent"
    fi
  }

  # Helper: build podman run command
  _build_run_command() {
    local -a cmd_array=(run)

    # Basic options
    [[ "${detach,,}" == "yes" ]] && cmd_array+=(--detach)
    [[ "${privileged,,}" == "yes" ]] && cmd_array+=(--privileged)
    [[ -n "$restart_policy" ]] && cmd_array+=(--restart="$restart_policy")
    [[ -n "$restart_retries" ]] && cmd_array+=(--restart-retries="$restart_retries")
    [[ -n "$user" ]] && cmd_array+=(--user="$user")
    [[ -n "$hostname" ]] && cmd_array+=(--hostname="$hostname")
    [[ "${publish_all,,}" == "yes" ]] && cmd_array+=(--publish-all)

    # Network options
    [[ -n "$network" ]] && cmd_array+=(--network="$network")
    [[ -n "$dns" ]] && cmd_array+=(--dns="$dns")
    [[ -n "$dns_search" ]] && cmd_array+=(--dns-search="$dns_search")

    # Security options
    [[ -n "$cap_add" ]] && cmd_array+=(--cap-add="$cap_add")
    [[ -n "$cap_drop" ]] && cmd_array+=(--cap-drop="$cap_drop")
    [[ -n "$security_opts" ]] && cmd_array+=(--security-opt="$security_opts")
    [[ -n "$sysctls" ]] && cmd_array+=(--sysctl="$sysctls")

    # Volume mounts
    if [[ -n "$volumes" ]]; then
      IFS=',' read -r -a volume_array <<< "$volumes"
      for volume in "${volume_array[@]}"; do
        cmd_array+=(--volume="$volume")
      done
    fi

    # Port mappings
    if [[ -n "$ports" ]]; then
      IFS=',' read -r -a port_array <<< "$ports"
      for port in "${port_array[@]}"; do
        cmd_array+=(--publish="$port")
      done
    fi

    # Environment variables
    if [[ -n "$env" ]]; then
      IFS=',' read -r -a env_array <<< "$env"
      for env_var in "${env_array[@]}"; do
        cmd_array+=(--env="$env_var")
      done
    fi

    # Environment file
    [[ -n "$env_file" ]] && cmd_array+=(--env-file="$env_file")

    # Container name and image
    cmd_array+=(--name="$name")
    cmd_array+=("$image")

    # Command
    [[ -n "$command" ]] && cmd_array+=("$command")

    echo "${cmd_array[@]}"
  }

  # Main logic based on state
  local current_status
  current_status=$(_container_status "$name")

  $BANB_VERBOSE && _banb_info "Container '$name' current status: $current_status"

  case "${state,,}" in
    started)
      if [[ "$current_status" == "running" && "${force_restart,,}" != "yes" ]]; then
        $BANB_VERBOSE && _banb_info "Container '$name' is already running"
        return 0
      fi

      if [[ "$current_status" == "absent" && -z "$image" ]]; then
        _banb_error "image parameter is required to start a new container"
        return 1
      fi

      # Pull image if needed
      if [[ "${pull,,}" == "yes" && -n "$image" ]]; then
        if ! _run_podman_cmd pull "$image"; then
          _banb_error "failed to pull image '$image'"
          return 3
        fi
      fi

      # Stop existing container if running
      if [[ "$current_status" == "running" ]]; then
        if ! _run_podman_cmd stop "$name"; then
          _banb_error "failed to stop container '$name'"
          return 3
        fi
      fi

      # Remove existing container if recreate is enabled or image changed
      if [[ "$current_status" != "absent" && ( "${recreate,,}" == "yes" || -n "$image" ) ]]; then
        if ! _run_podman_cmd rm "$name"; then
          _banb_error "failed to remove container '$name'"
          return 3
        fi
      fi

      # Start or create container
      if [[ "$current_status" == "absent" || "${recreate,,}" == "yes" ]]; then
        local run_cmd
        run_cmd=$(_build_run_command)
        if ! _run_podman_cmd $run_cmd; then
          _banb_error "failed to start container '$name'"
          return 3
        fi
      else
        if ! _run_podman_cmd start "$name"; then
          _banb_error "failed to start container '$name'"
          return 3
        fi
      fi
      ;;

    stopped)
      if [[ "$current_status" == "absent" ]]; then
        $BANB_VERBOSE && _banb_info "Container '$name' does not exist"
        return 0
      fi

      if [[ "$current_status" == "stopped" ]]; then
        $BANB_VERBOSE && _banb_info "Container '$name' is already stopped"
        return 0
      fi

      if ! _run_podman_cmd stop "$name"; then
        _banb_error "failed to stop container '$name'"
        return 3
      fi
      ;;

    absent)
      if [[ "$current_status" == "absent" ]]; then
        $BANB_VERBOSE && _banb_info "Container '$name' does not exist"
        return 0
      fi

      # Stop if running
      if [[ "$current_status" == "running" ]]; then
        if ! _run_podman_cmd stop "$name"; then
          _banb_error "failed to stop container '$name'"
          return 3
        fi
      fi

      # Remove container
      if ! _run_podman_cmd rm "$name"; then
        _banb_error "failed to remove container '$name'"
        return 3
      fi
      ;;

    killed)
      if [[ "$current_status" == "absent" ]]; then
        $BANB_VERBOSE && _banb_info "Container '$name' does not exist"
        return 0
      fi

      if ! _run_podman_cmd kill "$name"; then
        _banb_error "failed to kill container '$name'"
        return 3
      fi
      ;;

    restarted)
      if [[ "$current_status" == "absent" ]]; then
        _banb_error "Container '$name' does not exist, cannot restart"
        return 1
      fi

      if ! _run_podman_cmd restart "$name"; then
        _banb_error "failed to restart container '$name'"
        return 3
      fi
      ;;

    reloaded)
      if [[ "$current_status" == "absent" ]]; then
        _banb_error "Container '$name' does not exist, cannot reload"
        return 1
      fi

      # For containers that support reload (like nginx)
      if ! _run_podman_cmd exec "$name" sh -c 'kill -HUP 1'; then
        _banb_error "failed to reload container '$name'"
        return 3
      fi
      ;;

    present)
      # Ensure container exists and is in desired state
      if [[ "$current_status" == "absent" && -z "$image" ]]; then
        _banb_error "image parameter is required to create container"
        return 1
      fi

      if [[ "$current_status" == "absent" ]]; then
        # Pull image if needed
        if [[ "${pull,,}" == "yes" ]]; then
          if ! _run_podman_cmd pull "$image"; then
            _banb_error "failed to pull image '$image'"
            return 3
          fi
        fi

        # Create container
        local run_cmd
        run_cmd=$(_build_run_command)
        # Remove --detach flag for present state
        run_cmd=${run_cmd//--detach/}
        if ! _run_podman_cmd $run_cmd; then
          _banb_error "failed to create container '$name'"
          return 3
        fi
      else
        $BANB_VERBOSE && _banb_info "Container '$name' already exists"
      fi
      ;;
  esac

  # Dry-run summary
  if $BANB_DRY_RUN; then
    printf "Planned actions (%d):\n" "${#actions[@]}"
    for a in "${actions[@]}"; do printf "  - %s\n" "$a"; done
  fi

  return 0
}