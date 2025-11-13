# @function banb_ini_file
# @description Ansible-style INI file management module
# @reference https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ini_file_module.html
# @param --path=FILE Path to the INI-style file (required)
# @param --section=SECTION Section name in the INI file (required)
# @param --option=KEY The key in the INI file (required)
# @param --value=VAL The value to set (required when state=present)
# @param --state=present|absent Whether the option should be present or absent (default: present)
# @param --backup=true|false Create a backup file including timestamp (default: false)
# @param --mode=MODE The permissions the resulting file or directory should get
# @param --owner=USER Name of the user that should own the file/directory
# @param --group=GROUP Name of the group that should own the file/directory
# @param --no_extra_spaces=true|false Do not insert spaces around '=' (default: false)
# @param --create=true|false If set to false, the file will only be modified if it exists (default: false)
# @param --follow=true|false Whether to follow symlinks (default: false)
# @param --unsafe_writes=true|false Use atomic operations to prevent data corruption (default: false)
# @param --validate=COMMAND Validation command to run before copying into place
# @return 0 on success, 1 on error
banb_ini_file() {
  # Ansible-style INI file management module
  # Reference: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ini_file_module.html

  local PATH_TO_FILE=""
  local SECTION=""
  local OPTION=""
  local VALUE=""
  local STATE="present"
  local BACKUP=false
  local MODE=""
  local OWNER=""
  local GROUP=""
  local NO_EXTRA_SPACES=false
  local CREATE=false
  local FOLLOW=false
  local UNSAFE_WRITES=false
  local VALIDATE=""

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?

  # Parse module-specific args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path=*) PATH_TO_FILE="${1#*=}" ;;
      --section=*) SECTION="${1#*=}" ;;
      --option=*) OPTION="${1#*=}" ;;
      --value=*) VALUE="${1#*=}" ;;
      --state=*) STATE="${1#*=}" ;;
      --backup=*)
        case "${1#*=}" in
          true|false) BACKUP="${1#*=}" ;;
          *) _banb_error "--backup must be true or false"; return 1 ;;
        esac
        ;;
      --mode=*) MODE="${1#*=}" ;;
      --owner=*) OWNER="${1#*=}" ;;
      --group=*) GROUP="${1#*=}" ;;
      --no_extra_spaces=*)
        case "${1#*=}" in
          true|false) NO_EXTRA_SPACES="${1#*=}" ;;
          *) _banb_error "--no_extra_spaces must be true or false"; return 1 ;;
        esac
        ;;
      --create=*)
        case "${1#*=}" in
          true|false) CREATE="${1#*=}" ;;
          *) _banb_error "--create must be true or false"; return 1 ;;
        esac
        ;;
      --follow=*)
        case "${1#*=}" in
          true|false) FOLLOW="${1#*=}" ;;
          *) _banb_error "--follow must be true or false"; return 1 ;;
        esac
        ;;
      --unsafe_writes=*)
        case "${1#*=}" in
          true|false) UNSAFE_WRITES="${1#*=}" ;;
          *) _banb_error "--unsafe_writes must be true or false"; return 1 ;;
        esac
        ;;
      --validate=*) VALIDATE="${1#*=}" ;;
      --help)
        cat <<'EOF'
Ansible-style INI file management module

Usage:
  banb_ini_file --path=FILE --section=SECTION --option=KEY
                [--value=VAL] [--state=present|absent]
                [--backup=true] [--mode=MODE]
                [--owner=USER] [--group=GROUP]
                [--no_extra_spaces=true] [--create=true]
                [--follow=true] [--unsafe_writes=true]
                [--validate=COMMAND] [--dry-run] [--verbose]

Description:
  Tweak settings in INI-style files. Supports comments, sections, and key-value pairs.
  Idempotent: will only make changes when necessary.

Parameters:
  --path=FILE              Path to the INI-style file (required)
  --section=SECTION        Section name in the INI file (required)
  --option=KEY             The key in the INI file (required)
  --value=VAL              The value to set (required when state=present)
  --state=present|absent   Whether the option should be present or absent (default: present)
  --backup=true|false      Create a backup file including timestamp (default: false)
  --mode=MODE              The permissions the resulting file or directory should get
  --owner=USER             Name of the user that should own the file/directory
  --group=GROUP            Name of the group that should own the file/directory
  --no_extra_spaces=true|false  Do not insert spaces around '=' (default: false)
  --create=true|false      If set to false, the file will only be modified if it exists (default: false)
  --follow=true|false      Whether to follow symlinks (default: false)
  --unsafe_writes=true|false  Use atomic operations to prevent data corruption (default: false)
  --validate=COMMAND       Validation command to run before copying into place
  --dry-run                Show what would be changed without making changes
  --verbose                Provide more verbose output

Examples:
  banb_ini_file --path=/etc/ssh/sshd_config --section=Match --option=User --value=ansible
  banb_ini_file --path=/etc/my.cnf --section=mysqld --option=bind-address --value=127.0.0.1
  banb_ini_file --path=/tmp/test.ini --section=defaults --option=some_option --state=absent

EOF
        return 0
        ;;
      *) _banb_error "Unknown option: $1"; return 1 ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$PATH_TO_FILE" || -z "$SECTION" || -z "$OPTION" ]]; then
    _banb_error "--path, --section, and --option are required"
    return 1
  fi

  # Handle symlinks if FOLLOW is true
  local real_path="$PATH_TO_FILE"
  if [[ "$FOLLOW" == "true" && -L "$PATH_TO_FILE" ]]; then
    real_path="$(readlink -f "$PATH_TO_FILE" 2>/dev/null || echo "$PATH_TO_FILE")"
  fi

  # Check if file should be created
  if [[ "$CREATE" == "false" && ! -e "$real_path" ]]; then
    _banb_error "File '$real_path' does not exist and create=false"
    return 1
  fi

  # Create file if it doesn't exist
  if [[ ! -e "$real_path" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would create file: $real_path"
    else
      local parent_dir
      parent_dir="$(dirname "$real_path")"
      if [[ ! -w "$parent_dir" ]]; then
        _banb_error "Cannot create file: directory '$parent_dir' is not writable"
        return 1
      fi
      mkdir -p "$parent_dir" || { _banb_error "Failed to create directory: $parent_dir"; return 1; }
      touch "$real_path" || { _banb_error "Failed to create file: $real_path"; return 1; }
      _banb_info "Created file: $real_path"
    fi
  fi

  # Check if file is writable
  if [[ -e "$real_path" && ! -w "$real_path" ]]; then
    _banb_error "File '$real_path' is not writable"
    return 1
  fi

  # Validate section and option names
  if [[ ! "$SECTION" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    _banb_error "Invalid section name '$SECTION'"
    return 1
  fi

  if [[ ! "$OPTION" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    _banb_error "Invalid option name '$OPTION'"
    return 1
  fi

  # Validate path for security
  if ! _banb_validate_path "$real_path"; then
    _banb_error "Path '$real_path' is invalid or restricted for security reasons"
    return 1
  fi

  if [[ "$STATE" == "present" && -z "$VALUE" ]]; then
    _banb_error "--value is required when state=present"
    return 1
  fi

  # Create backup if requested
  if [[ "$BACKUP" == "true" && -e "$real_path" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would create backup: ${real_path}.bak.$(date +%s)"
    else
      cp -p "$real_path" "${real_path}.bak.$(date +%s)"
      _banb_info "Backup created: ${real_path}.bak.$(date +%s)"
    fi
  fi

  # Check if section exists, add if not present (only for present state)
  if [[ "$STATE" == "present" ]]; then
    if ! grep -q "^\[$SECTION\]" "$real_path" 2>/dev/null; then
      if $BANB_DRY_RUN; then
        _banb_info "[DRY-RUN] Would add section: [$SECTION]"
      else
        echo -e "\n[$SECTION]" >> "$real_path"
      fi
    fi
  fi

  local LINE
  [[ "$NO_EXTRA_SPACES" == "true" ]] && LINE="${OPTION}=${VALUE}" || LINE="${OPTION} = ${VALUE}"

  # Validation command if specified
  if [[ -n "$VALIDATE" && "$STATE" == "present" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would validate with: $VALIDATE"
    else
      # Safe command execution using _banb_run
      if ! _banb_run "$VALIDATE" < "$real_path"; then
        _banb_error "Validation failed with command: $VALIDATE"
        return 1
      fi
      _banb_info "Validation passed: $VALIDATE"
    fi
  fi

  if [[ "$STATE" == "present" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would set [$SECTION] $OPTION=$VALUE"
      return 0
    fi

    # Use atomic operations if unsafe_writes is false
    local tmp_file
    if [[ "$UNSAFE_WRITES" == "false" ]]; then
      tmp_file="$(mktemp "${real_path}.tmp.XXXXXX")"
    else
      tmp_file="${real_path}.tmp.$$"
    fi

    awk -v section="$SECTION" -v key="$OPTION" -v line="$LINE" '
      BEGIN { in_section=0; updated=0; section_found=0 }
      /^\[.*\]$/ {
        if (in_section && !updated) {
          # Reached next section without updating, add the option
          print line
          updated=1
        }
        in_section = ($0 == "[" section "]")
        if (in_section) section_found=1
        print
        next
      }
      in_section && /^[[:space:]]*[#;]/ { print; next }  # Skip comments
      in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        print line
        updated=1
        in_section=0
        next
      }
      { print }
      END {
        if (!updated) {
          if (in_section) {
            # Still in target section, add at end
            print line
          } else if (!section_found) {
            # Section not found, add section and option
            print "[" section "]"
            print line
          }
        }
      }
    ' "$real_path" > "$tmp_file"

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      _banb_error "Failed to update INI file (exit code: $exit_code)"
      rm -f "$tmp_file"
      return 1
    fi

    # Move temp file to final location
    if ! mv "$tmp_file" "$real_path"; then
      _banb_error "Failed to move temporary file to $real_path"
      rm -f "$tmp_file"
      return 1
    fi

    _banb_info "Set [$SECTION] $OPTION=$VALUE"

  elif [[ "$STATE" == "absent" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would remove [$SECTION] $OPTION"
      return 0
    fi

    # Use atomic operations if unsafe_writes is false
    local tmp_file
    if [[ "$UNSAFE_WRITES" == "false" ]]; then
      tmp_file="$(mktemp "${real_path}.tmp.XXXXXX")"
    else
      tmp_file="${real_path}.tmp.$$"
    fi

    awk -v section="$SECTION" -v key="$OPTION" '
      BEGIN { found=0 }
      $0 ~ "^\\[" section "\\]" { print; found=1; next }
      found && $0 ~ "^" key "[[:space:]]*=" { next }
      { print }
    ' "$real_path" > "$tmp_file"

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      _banb_error "Failed to update INI file (exit code: $exit_code)"
      rm -f "$tmp_file"
      return 1
    fi

    # Move temp file to final location
    if ! mv "$tmp_file" "$real_path"; then
      _banb_error "Failed to move temporary file to $real_path"
      rm -f "$tmp_file"
      return 1
    fi

    _banb_info "Removed [$SECTION] $OPTION"
  fi

  # Set file permissions if specified
  if [[ -n "$MODE" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would set permissions to $MODE on $real_path"
    else
      if chmod "$MODE" "$real_path"; then
        _banb_info "Permissions set to $MODE"
      else
        _banb_warning "Failed to set permissions to $MODE"
      fi
    fi
  fi

  # Set file ownership if specified
  if [[ -n "$OWNER" || -n "$GROUP" ]]; then
    local owner_spec=""
    if [[ -n "$OWNER" && -n "$GROUP" ]]; then
      owner_spec="${OWNER}:${GROUP}"
    elif [[ -n "$OWNER" ]]; then
      owner_spec="$OWNER"
    elif [[ -n "$GROUP" ]]; then
      owner_spec=":$GROUP"
    fi

    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would set ownership to $owner_spec on $real_path"
    else
      if chown "$owner_spec" "$real_path"; then
        _banb_info "Ownership set to $owner_spec"
      else
        _banb_warning "Failed to set ownership to $owner_spec"
      fi
    fi
  fi

  # Final validation if specified
  if [[ -n "$VALIDATE" ]]; then
    if $BANB_DRY_RUN; then
      _banb_info "[DRY-RUN] Would validate with: $VALIDATE"
    else
      # Safe command execution using _banb_run
      if ! _banb_run "$VALIDATE" < "$real_path"; then
        _banb_error "Final validation failed with command: $VALIDATE"
        return 1
      fi
      _banb_info "Final validation passed: $VALIDATE"
    fi
  fi

  _banb_info "INI modification completed successfully."
  return 0
}
