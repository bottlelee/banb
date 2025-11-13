# banb_copy: Ansible-like 'copy' module in Bash
# Supports: --src, --dest, --content, --owner, --group, --mode, --backup, --dry-run, --become, --help
banb_copy() {
  local SRC="" DEST="" OWNER="" GROUP="" MODE="" CONTENT=""
  local BACKUP=false DRY_RUN=false BECOME=false

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

  # Parse args
  for arg in "$@"; do
    case $arg in
      --src=*) SRC="${arg#*=}" ;;
      --dest=*) DEST="${arg#*=}" ;;
      --owner=*) OWNER="${arg#*=}" ;;
      --group=*) GROUP="${arg#*=}" ;;
      --mode=*) MODE="${arg#*=}" ;;
      --backup=*) BACKUP="${arg#*=}" ;;
      --content=*) CONTENT="${arg#*=}" ;;
      --dry-run) DRY_RUN=true ;;
      --become) BECOME=true ;;
      --help) echo "$_help"; return 0 ;;
      *) echo "Unknown option: $arg"; return 1 ;;
    esac
  done

  [[ -z "$DEST" ]] && { echo "❌ Error: --dest is required"; return 1; }

  # Helper: run command with dry-run/become
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

  # Compare files/content
  files_differ() {
    [[ ! -e "$DEST" ]] && return 0
    if [[ -n "$SRC" ]]; then
      ! cmp -s "$SRC" "$DEST"
    elif [[ -n "$CONTENT" ]]; then
      local tmpfile
      tmpfile=$(mktemp)
      echo "$CONTENT" > "$tmpfile"
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
      _run "cp -p '$DEST' '${DEST}.bak.$(date +%s)'"
      echo "🔁 Backup created: ${DEST}.bak.$(date +%s)"
    fi

    if [[ -n "$SRC" ]]; then
      _run "cp '$SRC' '$DEST'"
      echo "📄 Copied file from $SRC to $DEST"
    elif [[ -n "$CONTENT" ]]; then
      local tmpfile
      tmpfile=$(mktemp)
      echo "$CONTENT" > "$tmpfile"
      _run "cp '$tmpfile' '$DEST'"
      rm -f "$tmpfile"
      echo "📝 Wrote inline content to $DEST"
    fi
  else
    echo "⚖️ Files are identical — skipping backup and copy."
  fi

  if [[ -n "$OWNER" || -n "$GROUP" ]]; then
    _run "chown '${OWNER}:${GROUP}' '$DEST'"
    echo "👤 Ownership set to ${OWNER}:${GROUP}"
  fi

  if [[ -n "$MODE" ]]; then
    _run "chmod '$MODE' '$DEST'"
    echo "🔐 Permissions set to $MODE"
  fi

  echo "✅ Copy operation completed."
}
