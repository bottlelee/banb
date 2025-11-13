banb_sysctl() {
  local DEST="/etc/sysctl.conf"
  local SYSCTL_DICT="" NAME="" VALUE=""
  local BACKUP=false DRY_RUN=false BECOME=false RELOAD=true

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

  # Parse args
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
      --dry-run) DRY_RUN=true ;;
      --become) BECOME=true ;;
      *) echo "Unknown option: $1"; return 1 ;;
    esac
    shift
  done

  # Runner
  _run() {
    local cmd="$*"
    if $DRY_RUN; then
      echo "[DRY-RUN] $cmd"
    elif $BECOME; then
      sudo bash -c "$cmd"
    else
      bash -c "$cmd"
    fi
  }

  # Tempdir
  local tmpdir tmpfile
  tmpdir=$(mktemp -d)
  tmpfile="$tmpdir/$(basename "$DEST")"
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
    echo "⚖️ No changes needed — $(basename "$DEST") identical."
    rm -rf "$tmpdir"
    return 0
  fi

  # Validate tempfile
  if ! sysctl -p "$tmpfile" >/dev/null 2>&1; then
    echo "❌ Validation failed for $(basename "$tmpfile") — aborting."
    rm -rf "$tmpdir"
    return 1
  fi

  # Backup
  if [[ "$BACKUP" == "true" && -e "$DEST" ]]; then
    _run "cp -p '$DEST' '${DEST}.bak.$(date +%s)'"
    echo "🔁 Backup created: ${DEST}.bak.$(date +%s)"
  fi

  # Copy tempfile to dest
  _run "cp '$tmpfile' '$DEST'"
  echo "📄 Updated $(basename "$DEST")"

  # Reload
  if [[ "${RELOAD,,}" == "true" ]]; then
    _run "sysctl -p '$DEST'"
    echo "🔄 Reloaded sysctl from $(basename "$DEST")"
  fi

  rm -rf "$tmpdir"
}
