# @function banb_package
# @description Simulated Ansible 'package' module in Bash function
# @param name=PKG Package name (required)
# @param state=present|absent|latest Package state (default: present)
# @param use=TOOL Specific package manager to use
# @param update_cache=true Update package cache
# @param allow_downgrade=true Allow package downgrade
# @param download_only=true Download packages only
# @param download_dir=PATH Download directory (default: pkgs)
# @return 0 on success, 1 on error
banb_package() {
  local PKG_NAME=""
  local PKG_STATE="present"
  local PKG_USE=""
  local UPDATE_CACHE=false
  local ALLOW_DOWNGRADE=false
  local DOWNLOAD_ONLY=false
  local DOWNLOAD_DIR="pkgs"

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?

  # Parse module-specific args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      name=*) PKG_NAME="${1#*=}" ;;
      state=*) PKG_STATE="${1#*=}" ;;
      use=*) PKG_USE="${1#*=}" ;;
      update_cache=*)
        case "${1#*=}" in
          true|false) UPDATE_CACHE="${1#*=}" ;;
          *) _banb_error "update_cache must be true or false"; return 1 ;;
        esac
        ;;
      allow_downgrade=*)
        case "${1#*=}" in
          true|false) ALLOW_DOWNGRADE="${1#*=}" ;;
          *) _banb_error "allow_downgrade must be true or false"; return 1 ;;
        esac
        ;;
      download_only=*)
        case "${1#*=}" in
          true|false) DOWNLOAD_ONLY="${1#*=}" ;;
          *) _banb_error "download_only must be true or false"; return 1 ;;
        esac
        ;;
      download_dir=*) DOWNLOAD_DIR="${1#*=}" ;;
      help)
        cat <<EOF
Simulated Ansible 'package' module in Bash function

Usage:
  banb_package name=PKG [state=present|absent|latest]
                  [use=TOOL] [update_cache=true]
                  [allow_downgrade=true]
                  [download_only=true]
                  [download_dir=PATH]

EOF
        return 0
        ;;
      *) _banb_error "Unknown option: $1"; return 1 ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$PKG_NAME" ]]; then
    _banb_error "name is required"
    return 1
  fi

  # Create download directory if specified
  if [[ -n "$DOWNLOAD_DIR" ]]; then
    banb_file path="$DOWNLOAD_DIR" state=directory owner="${OWNER:-}" group="${GROUP:-}" mode="${MODE:-0755}" || return 1
  fi

  # Use common package manager detection function
  local PKG_TOOL="${PKG_USE:-$(_banb_detect_package_manager)}" || return $?
  _banb_info "Using package manager: $PKG_TOOL"

  if [[ "$UPDATE_CACHE" == "true" ]]; then
    case $PKG_TOOL in
      apt) _banb_run sudo apt update ;;
      dnf|yum) _banb_run sudo "$PKG_TOOL" makecache ;;
      pacman) _banb_run sudo pacman -Sy --noconfirm ;;
      zypper) _banb_run sudo zypper refresh ;;
      apk) _banb_run sudo apk update ;;
    esac
    _banb_info "Package cache updated"
  fi

  case $PKG_STATE in
    present)
      if [[ "$DOWNLOAD_ONLY" == "true" ]]; then
        case $PKG_TOOL in
          apt)
            _banb_run sudo apt-get download "$PKG_NAME"
            local DEB_FILE
            DEB_FILE=$(find . -maxdepth 1 -name "$PKG_NAME*.deb" 2>/dev/null | head -n1)
            [[ -n "$DEB_FILE" ]] && _banb_run mv "$DEB_FILE" "$DOWNLOAD_DIR"/ || _banb_warning "Could not locate downloaded .deb file"
            ;;
          dnf)
            _banb_run sudo dnf download --destdir="${DOWNLOAD_DIR:-.}" "$PKG_NAME"
            ;;
          yum)
            _banb_run sudo yum install --downloadonly --downloaddir="${DOWNLOAD_DIR:-.}" "$PKG_NAME" \
              || _banb_run sudo yum reinstall --downloadonly --downloaddir="${DOWNLOAD_DIR:-.}" "$PKG_NAME"
            ;;
          pacman)
            _banb_warning "pacman does not support --download_dir directly. Use 'pacman -Sw' and move manually."
            ;;
          zypper|apk)
            _banb_warning "$PKG_TOOL does not support download-only with directory specification."
            ;;
        esac
        _banb_info "Downloaded (only): $PKG_NAME to ${DOWNLOAD_DIR:-current dir}"
        return 0
      else
        case $PKG_TOOL in
          apt) 
            if ! _banb_run sudo apt install -y "$PKG_NAME"; then
              _banb_error "Failed to install package: $PKG_NAME"
              return 1
            fi
            ;;
          dnf|yum)
            if [[ "$ALLOW_DOWNGRADE" == "true" ]]; then
              if ! _banb_run sudo "$PKG_TOOL" install --allowerasing -y "$PKG_NAME"; then
                _banb_error "Failed to install package: $PKG_NAME"
                return 1
              fi
            else
              if ! _banb_run sudo "$PKG_TOOL" install -y "$PKG_NAME"; then
                _banb_error "Failed to install package: $PKG_NAME"
                return 1
              fi
            fi
            ;;
          pacman) _banb_run sudo pacman -S --noconfirm "$PKG_NAME" ;;
          zypper) _banb_run sudo zypper install -y "$PKG_NAME" ;;
          apk) _banb_run sudo apk add "$PKG_NAME" ;;
        esac
        _banb_info "Installed: $PKG_NAME"
      fi
      ;;
    absent)
      case $PKG_TOOL in
        apt) _banb_run sudo apt remove -y "$PKG_NAME" ;;
        dnf|yum) _banb_run sudo "$PKG_TOOL" remove -y "$PKG_NAME" ;;
        pacman) _banb_run sudo pacman -Rns --noconfirm "$PKG_NAME" ;;
        zypper) _banb_run sudo zypper remove -y "$PKG_NAME" ;;
        apk) _banb_run sudo apk del "$PKG_NAME" ;;
      esac
      _banb_info "Removed: $PKG_NAME"
      ;;
    latest)
      case $PKG_TOOL in
        apt) _banb_run sudo apt install -y --only-upgrade "$PKG_NAME" ;;
        dnf|yum) _banb_run sudo "$PKG_TOOL" upgrade -y "$PKG_NAME" ;;
        pacman) _banb_run sudo pacman -Syu --noconfirm "$PKG_NAME" ;;
        zypper) _banb_run sudo zypper update -y "$PKG_NAME" ;;
        apk) _banb_run sudo apk upgrade "$PKG_NAME" ;;
      esac
      _banb_info "Upgraded to latest: $PKG_NAME"
      ;;
    *)
      _banb_error "Invalid state: $PKG_STATE"
      return 1
      ;;
  esac

  return 0
}
