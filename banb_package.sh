banb_package() {
  local PKG_NAME=""
  local PKG_STATE="present"
  local PKG_USE=""
  local UPDATE_CACHE=false
  local ALLOW_DOWNGRADE=false
  local DOWNLOAD_ONLY=false
  local DOWNLOAD_DIR="pkgs"

  for arg in "$@"; do
    case $arg in
      --name=*) PKG_NAME="${arg#*=}" ;;
      --state=*) PKG_STATE="${arg#*=}" ;;
      --use=*) PKG_USE="${arg#*=}" ;;
      --update_cache=*) UPDATE_CACHE="${arg#*=}" ;;
      --allow_downgrade=*) ALLOW_DOWNGRADE="${arg#*=}" ;;
      --download_only=*) DOWNLOAD_ONLY="${arg#*=}" ;;
      --download_dir=*) DOWNLOAD_DIR="${arg#*=}" ;;
      --help)
        cat <<EOF
Simulated Ansible 'package' module in Bash function

Usage:
  banb_package --name=PKG [--state=present|absent|latest]
                  [--use=TOOL] [--update_cache=true]
                  [--allow_downgrade=true]
                  [--download_only=true]
                  [--download_dir=PATH]

EOF
        return 0
        ;;
      *) echo "Unknown option: $arg"; return 1 ;;
    esac
  done

  if [[ -z "$PKG_NAME" ]]; then
    echo "❌ Error: --name is required"
    return 1
  fi

  [[ -n "$DOWNLOAD_DIR" ]] && mkdir -p "$DOWNLOAD_DIR"

  local detect_pkg_tool
  detect_pkg_tool() {
    for tool in pacman apt dnf yum zypper apk; do
      command -v "$tool" &>/dev/null && { echo "$tool"; return; }
    done
    echo "❌ No supported package manager found" >&2
    return 1
  }

  local PKG_TOOL="${PKG_USE:-$(detect_pkg_tool)}"
  echo "📦 Using package manager: $PKG_TOOL"

  if [[ "$UPDATE_CACHE" == "true" ]]; then
    case $PKG_TOOL in
      apt) sudo apt update ;;
      dnf|yum) sudo "$PKG_TOOL" makecache ;;
      pacman) sudo pacman -Sy --noconfirm ;;
      zypper) sudo zypper refresh ;;
      apk) sudo apk update ;;
    esac
    echo "🔄 Package cache updated"
  fi

  case $PKG_STATE in
    present)
      if [[ "$DOWNLOAD_ONLY" == "true" ]]; then
        case $PKG_TOOL in
          apt)
            sudo apt-get download "$PKG_NAME"
            local DEB_FILE
            DEB_FILE=$(ls "$PKG_NAME"*.deb 2>/dev/null | head -n1)
            [[ -n "$DEB_FILE" ]] && mv "$DEB_FILE" "$DOWNLOAD_DIR"/ || echo "⚠️ Could not locate downloaded .deb file"
            ;;
          dnf)
            sudo dnf download --destdir="${DOWNLOAD_DIR:-.}" "$PKG_NAME"
            ;;
          yum)
            sudo yum install --downloadonly --downloaddir="${DOWNLOAD_DIR:-.}" "$PKG_NAME" \
              || sudo yum reinstall --downloadonly --downloaddir="${DOWNLOAD_DIR:-.}" "$PKG_NAME"
            ;;
          pacman)
            echo "⚠️ pacman does not support --download_dir directly. Use 'pacman -Sw' and move manually."
            ;;
          zypper|apk)
            echo "⚠️ $PKG_TOOL does not support download-only with directory specification."
            ;;
        esac
        echo "📥 Downloaded (only): $PKG_NAME to ${DOWNLOAD_DIR:-current dir}"
        return 0
      else
        case $PKG_TOOL in
          apt) sudo apt install -y "$PKG_NAME" ;;
          dnf|yum)
            if [[ "$ALLOW_DOWNGRADE" == "true" ]]; then
              sudo "$PKG_TOOL" install --allowerasing -y "$PKG_NAME"
            else
              sudo "$PKG_TOOL" install -y "$PKG_NAME"
            fi
            ;;
          pacman) sudo pacman -S --noconfirm "$PKG_NAME" ;;
          zypper) sudo zypper install -y "$PKG_NAME" ;;
          apk) sudo apk add "$PKG_NAME" ;;
        esac
        echo "✅ Installed: $PKG_NAME"
      fi
      ;;
    absent)
      case $PKG_TOOL in
        apt) sudo apt remove -y "$PKG_NAME" ;;
        dnf|yum) sudo "$PKG_TOOL" remove -y "$PKG_NAME" ;;
        pacman) sudo pacman -Rns --noconfirm "$PKG_NAME" ;;
        zypper) sudo zypper remove -y "$PKG_NAME" ;;
        apk) sudo apk del "$PKG_NAME" ;;
      esac
      echo "🗑️ Removed: $PKG_NAME"
      ;;
    latest)
      case $PKG_TOOL in
        apt) sudo apt install -y --only-upgrade "$PKG_NAME" ;;
        dnf|yum) sudo "$PKG_TOOL" upgrade -y "$PKG_NAME" ;;
        pacman) sudo pacman -Syu --noconfirm "$PKG_NAME" ;;
        zypper) sudo zypper update -y "$PKG_NAME" ;;
        apk) sudo apk upgrade "$PKG_NAME" ;;
      esac
      echo "⬆️ Upgraded to latest: $PKG_NAME"
      ;;
    *)
      echo "❌ Invalid state: $PKG_STATE"
      return 1
      ;;
  esac
}
