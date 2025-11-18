# @function banb_local_pkg
# @description Simulated air-gapped package installer
# @param pkgs_path=DIR Directory containing local packages (default: pkgs)
# @param pkgs_name=LIST Space-separated list of packages to download if missing
# @param download_only=yes Download packages only (requires banb_package)
# @return 0 on success, 1 on error
banb_local_pkg() {
  local PKGS_PATH="pkgs"
  local PKGS_NAME=""
  local PKG_TOOL=""
  local DOWNLOAD_ONLY=no

  # Parse common args and set global variables
  _banb_parse_common_args "$@" || return $?

  # Parse module-specific args (Ansible-style key=value)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      pkgs_path=*) PKGS_PATH="${1#*=}" ;;
      pkgs_name=*) PKGS_NAME="${1#*=}" ;;
      download_only=*)
        case "${1#*=}" in
          yes|no) DOWNLOAD_ONLY="${1#*=}" ;;
          *) _banb_error "download_only must be yes or no"; return 1 ;;
        esac
        ;;
      help)
        cat <<EOF
Simulated air-gapped package installer

Usage:
  banb_local_pkg [pkgs_path=DIR] [pkgs_name="pkg1 pkg2 ..."] [download_only=yes]

Options:
  pkgs_path=DIR       Directory containing local packages (default: pkgs)
  pkgs_name=LIST      Space-separated list of packages to download if missing
  download_only=yes   Download packages only (requires banb_package)
EOF
        return 0
        ;;
      *) _banb_error "Unknown option: $1"; return 1 ;;
    esac
    shift
  done

  if [[ ! -d "$PKGS_PATH" ]]; then
    _banb_error "Package directory not found: $PKGS_PATH"
    return 1
  fi

  # Detect package manager using common function
  PKG_TOOL="$(_banb_detect_package_manager)" || return $?
  _banb_info "Detected package manager: $PKG_TOOL"
  _banb_info "Looking for packages in: $PKGS_PATH"

  # Install local packages
  case $PKG_TOOL in
    apt)
      local DEBS=("$PKGS_PATH"/*.deb)
      if [[ -e "${DEBS[0]}" ]]; then
        _banb_run sudo dpkg -i "${DEBS[@]}" || _banb_run sudo apt -f install -y
        _banb_info "Installed .deb packages from $PKGS_PATH"
      else
        _banb_warning "No .deb packages found in $PKGS_PATH"
        _banb_warning "You can add '--download_only=true' to the script"
        _banb_warning "and run again when you have internet access"
      fi
      ;;
    dnf|yum)
      local RPMS=("$PKGS_PATH"/*.rpm)
      if [[ -e "${RPMS[0]}" ]]; then
        _banb_run sudo "$PKG_TOOL" install -y "${RPMS[@]}"
        _banb_info "Installed .rpm packages from $PKGS_PATH"
      else
        _banb_warning "No .rpm packages found in $PKGS_PATH"
        _banb_warning "You can add '--download_only=true' to the script"
        _banb_warning "and run again when you have internet access"
      fi
      ;;
    pacman)
      local PKGS=("$PKGS_PATH"/*.pkg.tar.zst)
      if [[ -e "${PKGS[0]}" ]]; then
        _banb_run sudo pacman -U --noconfirm "${PKGS[@]}"
        _banb_info "Installed local packages from $PKGS_PATH"
      else
        _banb_warning "No pacman packages found in $PKGS_PATH"
        _banb_warning "You can add '--download_only=true' to the script"
        _banb_warning "and run again when you have internet access"
      fi
      ;;
    zypper)
      _banb_warning "zypper does not support local install directly. Use 'rpm -i' manually if needed."
      ;;
    apk)
      _banb_warning "apk does not support local install from directory. Use 'apk add --allow-untrusted' manually."
      ;;
  esac

  # If no packages found or install failed, fallback to download
  if [[ -n "$PKGS_NAME" && "$DOWNLOAD_ONLY" == "yes" ]]; then
    _banb_info "Attempting to download missing packages: $PKGS_NAME"
    for pkg in $PKGS_NAME; do
      banb_package name="$pkg" download_only=true download_dir="$PKGS_PATH"
    done
    _banb_info "Download completed. You can now transfer these to the air-gapped system."
  fi

  return 0
}
