banb_sysctl() {
  local DEST="/etc/sysctl.conf"
  local SYSCTL_DICT="" NAME="" VALUE="" STATE=""
  local BACKUP=false RELOAD=true

  local _help="Usage:
  banb_sysctl --name=KEY --value=VAL [--state=present|absent] [--reload=true|false]
              [--sysctl-dict=\"KEY1=VAL1 KEY2=VAL2\"] [--dest=PATH]
              [--backup=true] [--dry-run] [--become]

Description:
  Manage kernel parameters via sysctl. Updates a config file safely using a temp copy.
  Default dest is /etc/sysctl.conf, but you can set --dest=/etc/sysctl.d/99-elk.conf.

Examples:
  banb_sysctl --sysctl-dict=\"vm.swappiness=1 net.core.somaxconn=65535\" --dest=/etc/sysctl.d/99-elk.conf --backup=true --reload=true
"

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?
  
  # Parse module-specific args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) echo "$_help"; return 0 ;;
      --name=*) NAME="${1#*=}" ;;
      --value=*) VALUE="${1#*=}" ;;
      --sysctl-dict=*) SYSCTL_DICT="${1#*=}" ;;
      --state=*) STATE="${1#*=}" ;;
      --reload=*) RELOAD="${1#*=}" ;;
      --dest=*) DEST="${1#*=}" ;;
      --backup=*) BACKUP="${1#*=}" ;;
      *) _banb_error "Unknown option: $1" 1 ;;
    esac
    shift
  done

  # Validate path for security
  _banb_validate_path "$DEST" "destination" || return $?

  # Tempdir
  local tmpdir tmpfile
  tmpdir=$(_banb_create_tempdir "banb_sysctl")
  tmpfile="$tmpdir/$(basename "$DEST")"
  
  # Check if source file is readable
  if [[ -e "$DEST" && ! -r "$DEST" ]]; then
    _banb_error "Cannot read file '$DEST'"
    rm -rf "$tmpdir"
    return 1
  fi
  
  cp "$DEST" "$tmpfile" 2>/dev/null || touch "$tmpfile"

  # Apply k/v
  apply_kv() {
    local key="$1" val="$2"
    if grep -q "^$key" "$tmpfile"; then
      sed -i "s|^$key.*|$key = $val|" "$tmpfile"
    else
      echo "$key = $val" >> "$tmpfile"
    fi
  }
  [[ -n "$NAME" && -n "$VALUE" ]] && apply_kv "$NAME" "$VALUE"
  for kv in $SYSCTL_DICT; do
    apply_kv "${kv%%=*}" "${kv#*=}"
  done

  # Compare
  if cmp -s "$tmpfile" "$DEST"; then
    _banb_info "No changes needed — $(basename "$DEST") identical."
    rm -rf "$tmpdir"
    return 0
  fi

  # Validate tempfile
  if ! sysctl -p "$tmpfile" >/dev/null 2>&1; then
    _banb_error "Validation failed for $(basename "$tmpfile") — aborting."
    rm -rf "$tmpdir"
    return 1
  fi

  # Backup
  if [[ "$BACKUP" == "true" && -e "$DEST" ]]; then
    _banb_backup_file "$DEST"
  fi

  # Copy tempfile to dest
  _banb_run "cp '$tmpfile' '$DEST'"
  _banb_success "Updated $(basename "$DEST")"

  # Reload
  if [[ "${RELOAD,,}" == "true" ]]; then
    _banb_run "sysctl -p '$DEST'"
    _banb_success "Reloaded sysctl from $(basename "$DEST")"
  fi

  rm -rf "$tmpdir"
}