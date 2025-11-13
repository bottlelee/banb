banb_local_pkg() {
  local PKGS_PATH="pkgs"
  local PKGS_NAME=""
  local PKG_TOOL=""
  local DOWNLOAD_ONLY=false

  for arg in "$@"; do
    case $arg in
      --pkgs-path=*) PKGS_PATH="${arg#*=}" ;;
      --pkgs-name=*) PKGS_NAME="${arg#*=}" ;;
      --download_only=*) DOWNLOAD_ONLY="${arg#*=}" ;;
      --help)
        cat <<EOF
Simulated air-gapped package installer

Usage:
  banb_local_pkg [--pkgs-path=DIR] [--pkgs-name="pkg1 pkg2 ..."] [--download_only=true]

Options:
  --pkgs-path=DIR       Directory containing local packages (default: pkgs)
  --pkgs-name=LIST      Space-separated list of packages to download if missing
  --download_only=true  Download packages only (requires banb_package)
EOF
        return 0
        ;;
      *) echo "Unknown option: $arg"; return 1 ;;
    esac
  done

  [[ ! -d "$PKGS_PATH" ]] && {
    echo "❌ Package directory not found: $PKGS_PATH"
    return 1
  }

  # Detect package manager
  for tool in pacman apt dnf yum zypper apk; do
    if command -v "$tool" &>/dev/null; then
      PKG_TOOL="$tool"
      break
    fi
  done

  [[ -z "$PKG_TOOL" ]] && {
    echo "❌ No supported package manager found"
    return 1
  }

  echo "📦 Using package manager: $PKG_TOOL"
  echo "📁 Looking for packages in: $PKGS_PATH"

  # Install local packages
  case $PKG_TOOL in
    apt)
      local DEBS=("$PKGS_PATH"/*.deb)
      if [[ -e "${DEBS[0]}" ]]; then
        sudo dpkg -i "${DEBS[@]}" || sudo apt -f install -y
        echo "✅ Installed .deb packages from $PKGS_PATH"
      else
        echo "⚠️ No .deb packages found in $PKGS_PATH"
        echo "⚠️ You can add '--download_only=true' to the script"
        echo "     and run again when you have internet access"
      fi
      ;;
    dnf|yum)
      local RPMS=("$PKGS_PATH"/*.rpm)
      if [[ -e "${RPMS[0]}" ]]; then
        sudo "$PKG_TOOL" install -y "${RPMS[@]}"
        echo "✅ Installed .rpm packages from $PKGS_PATH"
      else
        echo "⚠️ No .rpm packages found in $PKGS_PATH"
        echo "⚠️ You can add '--download_only=true' to the script"
        echo "     and run again when you have internet access"
      fi
      ;;
    pacman)
      local PKGS=("$PKGS_PATH"/*.pkg.tar.zst)
      if [[ -e "${PKGS[0]}" ]]; then
        sudo pacman -U --noconfirm "${PKGS[@]}"
        echo "✅ Installed local packages from $PKGS_PATH"
      else
        echo "⚠️ No pacman packages found in $PKGS_PATH"
        echo "⚠️ You can add '--download_only=true' to the script"
        echo "     and run again when you have internet access"
      fi
      ;;
    zypper)
      echo "⚠️ zypper does not support local install directly. Use 'rpm -i' manually if needed."
      ;;
    apk)
      echo "⚠️ apk does not support local install from directory. Use 'apk add --allow-untrusted' manually."
      ;;
  esac

  # If no packages found or install failed, fallback to download
  if [[ -n "$PKGS_NAME" && "$DOWNLOAD_ONLY" == "true" ]]; then
    echo "📥 Attempting to download missing packages: $PKGS_NAME"
    for pkg in $PKGS_NAME; do
      banb_package --name="$pkg" --download_only=true --download_dir="$PKGS_PATH"
    done
    echo "✅ Download completed. You can now transfer these to the air-gapped system."
  fi
}
