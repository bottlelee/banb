banb_ini_file() {
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

  for arg in "$@"; do
    case $arg in
      --path=*) PATH_TO_FILE="${arg#*=}" ;;
      --section=*) SECTION="${arg#*=}" ;;
      --option=*) OPTION="${arg#*=}" ;;
      --value=*) VALUE="${arg#*=}" ;;
      --state=*) STATE="${arg#*=}" ;;
      --backup=*) BACKUP="${arg#*=}" ;;
      --mode=*) MODE="${arg#*=}" ;;
      --owner=*) OWNER="${arg#*=}" ;;
      --group=*) GROUP="${arg#*=}" ;;
      --no_extra_spaces=*) NO_EXTRA_SPACES="${arg#*=}" ;;
      --help)
        cat <<EOF
Simulated Ansible 'ini_file' module in Bash function

Usage:
  banb_ini_file --path=FILE --section=SECTION --option=KEY
                [--value=VAL] [--state=present|absent]
                [--backup=true] [--mode=MODE]
                [--owner=USER] [--group=GROUP]
                [--no_extra_spaces=true]

EOF
        return 0
        ;;
      *) echo "Unknown option: $arg"; return 1 ;;
    esac
  done

  if [[ -z "$PATH_TO_FILE" || -z "$SECTION" || -z "$OPTION" ]]; then
    echo "❌ Error: --path, --section, and --option are required"
    return 1
  fi

  if [[ "$STATE" == "present" && -z "$VALUE" ]]; then
    echo "❌ Error: --value is required when state=present"
    return 1
  fi

  [[ "$BACKUP" == "true" && -e "$PATH_TO_FILE" ]] && {
    cp -p "$PATH_TO_FILE" "${PATH_TO_FILE}.bak.$(date +%s)"
    echo "🔁 Backup created: ${PATH_TO_FILE}.bak.$(date +%s)"
  }

  grep -q "^

\[$SECTION\]

" "$PATH_TO_FILE" || echo -e "\n[$SECTION]" >> "$PATH_TO_FILE"

  local LINE
  [[ "$NO_EXTRA_SPACES" == "true" ]] && LINE="${OPTION}=${VALUE}" || LINE="${OPTION} = ${VALUE}"

  if [[ "$STATE" == "present" ]]; then
    awk -v section="$SECTION" -v key="$OPTION" -v line="$LINE" '
      BEGIN { found=0; updated=0 }
      $0 ~ "^

\[" section "\]

" { print; found=1; next }
      found && $0 ~ "^" key "[[:space:]]*=" {
        print line; updated=1; found=0; next
      }
      { print }
      END {
        if (found && !updated) print line
      }
    ' "$PATH_TO_FILE" > "${PATH_TO_FILE}.tmp" && mv "${PATH_TO_FILE}.tmp" "$PATH_TO_FILE"
    echo "✅ Set [$SECTION] $OPTION=$VALUE"
  elif [[ "$STATE" == "absent" ]]; then
    awk -v section="$SECTION" -v key="$OPTION" '
      BEGIN { found=0 }
      $0 ~ "^

\[" section "\]

" { print; found=1; next }
      found && $0 ~ "^" key "[[:space:]]*=" { next }
      { print }
    ' "$PATH_TO_FILE" > "${PATH_TO_FILE}.tmp" && mv "${PATH_TO_FILE}.tmp" "$PATH_TO_FILE"
    echo "🗑️ Removed [$SECTION] $OPTION"
  fi

  [[ -n "$MODE" ]] && chmod "$MODE" "$PATH_TO_FILE" && echo "🔐 Permissions set to $MODE"
  [[ -n "$OWNER" || -n "$GROUP" ]] && chown "${OWNER}:${GROUP}" "$PATH_TO_FILE" && echo "👤 Ownership set to ${OWNER}:${GROUP}"

  echo "✅ INI modification completed."
}
