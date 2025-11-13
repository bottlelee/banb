# @function banb_copy
# @description Ansible-like 'copy' module in Bash
# @param --src=PATH Source file to copy
# @param --dest=PATH Destination path (required)
# @param --content=STRING Inline content to write instead of copying a file
# @param --owner=USER Set file owner
# @param --group=GROUP Set file group
# @param --mode=MODE Set file permissions (e.g. 0644)
# @param --backup=true Backup existing destination file before overwrite
# @param --dry-run Print intended actions without executing
# @param --become Run actions with sudo
# @return 0 on success, 1 on error
banb_copy() {
  local SRC="" DEST="" OWNER="" GROUP="" MODE="" CONTENT=""
  local BACKUP=false

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?

  local _help="Usage:
  banb_copy --dest=DEST [--src=SRC | --content=STRING]
            [--owner=USER] [--group=GROUP] [--mode=MODE]
            [--backup=true] [--dry-run] [--become]

Description:
  Simulates Ansible's 'copy' module. Copies a file or writes inline content.
  Supports ownership, permissions, backup, dry-run, and privilege escalation.

Options:
  --src=PATH        Source file to copy
  --dest=PATH       Destination path (required)
  --content=STRING  Inline content to write instead of copying a file
  --owner=USER      Set file owner
  --group=GROUP     Set file group
  --mode=MODE       Set file permissions (e.g. 0644)
  --backup=true     Backup existing destination file before overwrite
  --dry-run         Print intended actions without executing
  --become          Run actions with sudo
  --help            Show this help message and exit

Notes:
  - Either --src or --content must be provided.
  - Backup and overwrite only occur if content differs.
"

  # Parse module-specific args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --src=*) SRC="${1#*=}" ;;
      --dest=*) DEST="${1#*=}" ;;
      --owner=*) OWNER="${1#*=}" ;;
      --group=*) GROUP="${1#*=}" ;;
      --mode=*) MODE="${1#*=}" ;;
      --backup=*)
        case "${1#*=}" in
          true|false) BACKUP="${1#*=}" ;;
          *) _banb_error "--backup must be true or false"; return 1 ;;
        esac
        ;;
      --content=*) CONTENT="${1#*=}" ;;
      --help) echo "$_help"; return 0 ;;
      *) _banb_error "Unknown option: $1"; return 1 ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$DEST" ]]; then
    _banb_error "--dest is required"
    return 1
  fi

  # Check for mutually exclusive parameters
  if [[ -n "$SRC" && -n "$CONTENT" ]]; then
    _banb_error "--src and --content are mutually exclusive"
    return 1
  fi

  if [[ -z "$SRC" && -z "$CONTENT" ]]; then
    _banb_error "Either --src or --content must be provided"
    return 1
  fi

  # Use common path validation function
  if [[ -n "$SRC" ]] && ! _banb_validate_path "$SRC" "source"; then
    return 1
  fi

  if ! _banb_validate_path "$DEST" "destination"; then
    return 1
  fi

  # Use common run function for safe command execution

  # Compare files/content
  files_differ() {
    [[ ! -e "$DEST" ]] && return 0
    if [[ -n "$SRC" ]]; then
      if [[ ! -f "$SRC" ]]; then
        _banb_error "Source file '$SRC' does not exist or is not a regular file"
        return 1
      fi
      ! cmp -s "$SRC" "$DEST"
    elif [[ -n "$CONTENT" ]]; then
      local tmpfile
      tmpfile=$(mktemp -t .banb_copy.XXXXXXXXXX)
      chmod 600 "$tmpfile"  # Secure permissions first
      echo "$CONTENT" > "$tmpfile" || { rm -f "$tmpfile"; _banb_error "Failed to write to temp file"; return 1; }
      ! cmp -s "$tmpfile" "$DEST"
      local result=$?
      rm -f "$tmpfile"
      return $result
    else
      return 1
    fi
  }

  # Apply changes
  if files_differ; then
    if [[ "$BACKUP" == "true" && -e "$DEST" ]]; then
      local backup_file="${DEST}.bak.$(date +%s)"
      _banb_run cp -p "$DEST" "$backup_file"
      _banb_info "Backup created: $backup_file"
    fi

    if [[ -n "$SRC" ]]; then
      if ! _banb_run cp "$SRC" "$DEST"; then
        _banb_error "Failed to copy from $SRC to $DEST"
        return 1
      fi
      _banb_info "Copied file from $SRC to $DEST"
    elif [[ -n "$CONTENT" ]]; then
      local tmpfile
      tmpfile=$(mktemp -t .banb_copy.XXXXXXXXXX)
      chmod 600 "$tmpfile"  # Secure permissions first
      echo "$CONTENT" > "$tmpfile" || { rm -f "$tmpfile"; _banb_error "Failed to write to temp file"; return 1; }
      if ! _banb_run cp "$tmpfile" "$DEST"; then
        rm -f "$tmpfile"
        _banb_error "Failed to write content to $DEST"
        return 1
      fi
      rm -f "$tmpfile"
      _banb_info "Wrote inline content to $DEST"
    fi
  else
    _banb_info "Files are identical — skipping backup and copy."
  fi

  if [[ -n "$OWNER" || -n "$GROUP" ]]; then
    local owner_spec=""
    if [[ -n "$OWNER" && -n "$GROUP" ]]; then
      owner_spec="${OWNER}:${GROUP}"
    elif [[ -n "$OWNER" ]]; then
      owner_spec="$OWNER"
    elif [[ -n "$GROUP" ]]; then
      owner_spec=":$GROUP"
    fi
    _banb_run chown "$owner_spec" "$DEST"
    _banb_info "Ownership set to $owner_spec"
  fi

  if [[ -n "$MODE" ]]; then
    _banb_run chmod "$MODE" "$DEST"
    _banb_info "Permissions set to $MODE"
  fi

  _banb_info "Copy operation completed."
  return 0
}
