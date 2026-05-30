#!/usr/bin/env sh
# ReplyVoice — Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/kedimuzafer/replyvoice/main/install.sh | sh

set -e

REPO="kedimuzafer/replyvoice"
APP_NAME="ReplyVoice"
BINARY_NAME="replyvoice"

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${BOLD}==> %s${NC}\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC}  %s\n" "$*"; }
die()  { printf "${RED}✗${NC}  %s\n" "$*" >&2; exit 1; }

# Downloader
if command -v curl >/dev/null 2>&1; then
  fetch()      { curl -fsSL --progress-bar "$1" -o "$2"; }
  fetch_text() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch()      { wget -q --show-progress -O "$2" "$1"; }
  fetch_text() { wget -qO- "$1"; }
else
  die "curl or wget is required"
fi

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  ;;
  Darwin) ;;
  *)      die "Unsupported OS: $OS. On Windows download the .exe from: https://github.com/${REPO}/releases" ;;
esac

case "$ARCH" in
  x86_64|amd64)  ARCH_KEY="x86_64" ;;
  arm64|aarch64) ARCH_KEY="arm64" ;;
  *)             die "Unsupported architecture: $ARCH" ;;
esac

# Detect Linux package manager
PKG_FORMAT="tar"
PKG_MGR=""
if [ "$OS" = "Linux" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    PKG_FORMAT="deb"; PKG_MGR="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_FORMAT="rpm"; PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_FORMAT="rpm"; PKG_MGR="yum"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_FORMAT="rpm"; PKG_MGR="zypper"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_FORMAT="tar"; PKG_MGR="pacman"
  fi
fi

# Resolve asset name
if [ "$OS" = "Darwin" ]; then
  ASSET="${APP_NAME}-macos-${ARCH_KEY}.dmg"
elif [ "$PKG_FORMAT" = "deb" ]; then
  ASSET="${APP_NAME}-linux-x86_64.deb"
elif [ "$PKG_FORMAT" = "rpm" ]; then
  ASSET="${APP_NAME}-linux-x86_64.rpm"
else
  ASSET="${APP_NAME}-linux-x86_64.tar.gz"
fi

echo ""
info "Installing ReplyVoice"
echo ""

# Resolve latest version
VERSION="latest"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

# Download
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Downloading $ASSET..."
fetch "$DOWNLOAD_URL" "$TMP_DIR/$ASSET" || die "Download failed. Check: https://github.com/${REPO}/releases"

# Install
if [ "$OS" = "Darwin" ]; then
  info "Mounting disk image..."
  MOUNT="$(mktemp -d)"
  hdiutil attach "$TMP_DIR/$ASSET" -mountpoint "$MOUNT" -quiet -nobrowse
  APP="$(find "$MOUNT" -name "*.app" -maxdepth 1 | head -1)"
  [ -z "$APP" ] && { hdiutil detach "$MOUNT" -quiet; die "No .app found in DMG"; }
  info "Copying to /Applications..."
  cp -R "$APP" /Applications/
  hdiutil detach "$MOUNT" -quiet
  DEST="/Applications/$(basename "$APP")"
  xattr -d com.apple.quarantine "$DEST" 2>/dev/null || true
  ok "Installed: $DEST"

elif [ "$PKG_FORMAT" = "deb" ]; then
  info "Installing .deb package..."
  if [ "$(id -u)" -eq 0 ]; then
    apt-get install -y "$TMP_DIR/$ASSET"
  else
    sudo apt-get install -y "$TMP_DIR/$ASSET"
  fi
  ok "Installed via apt"

elif [ "$PKG_FORMAT" = "rpm" ]; then
  info "Installing .rpm package..."
  if [ "$PKG_MGR" = "dnf" ]; then
    sudo dnf install -y "$TMP_DIR/$ASSET"
  elif [ "$PKG_MGR" = "yum" ]; then
    sudo yum install -y "$TMP_DIR/$ASSET"
  elif [ "$PKG_MGR" = "zypper" ]; then
    sudo zypper install -y "$TMP_DIR/$ASSET"
  else
    sudo rpm -i "$TMP_DIR/$ASSET"
  fi
  ok "Installed via rpm"

else
  # Generic tarball install
  if [ "$(id -u)" -eq 0 ]; then
    OPT_DIR="/opt/${APP_NAME}"; BIN_DIR="/usr/local/bin"
    DESK_DIR="/usr/share/applications"
    ICON_DIR="/usr/share/icons/hicolor/128x128/apps"
  else
    OPT_DIR="$HOME/.local/opt/${APP_NAME}"; BIN_DIR="$HOME/.local/bin"
    DESK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/128x128/apps"
  fi

  info "Installing to $OPT_DIR..."
  mkdir -p "$TMP_DIR/extract"
  tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR/extract"
  rm -rf "$OPT_DIR"
  mkdir -p "$(dirname "$OPT_DIR")"
  mv "$TMP_DIR/extract/${APP_NAME}" "$OPT_DIR"

  mkdir -p "$BIN_DIR" "$DESK_DIR" "$ICON_DIR"
  printf '#!/bin/sh\nexec "%s/bin/%s-bin" "$@"\n' "$OPT_DIR" "$BINARY_NAME" > "$BIN_DIR/$BINARY_NAME"
  chmod +x "$BIN_DIR/$BINARY_NAME"

  [ -f "$OPT_DIR/share/applications/${APP_NAME}.desktop" ] && \
    sed "s|Exec=.*|Exec=${BIN_DIR}/${BINARY_NAME}|" \
      "$OPT_DIR/share/applications/${APP_NAME}.desktop" \
      > "$DESK_DIR/${APP_NAME}.desktop"

  [ -f "$OPT_DIR/share/icons/hicolor/128x128/apps/${BINARY_NAME}.png" ] && \
    cp "$OPT_DIR/share/icons/hicolor/128x128/apps/${BINARY_NAME}.png" \
       "$ICON_DIR/${BINARY_NAME}.png"

  command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$DESK_DIR" 2>/dev/null || true

  ok "Installed: $OPT_DIR"
  ok "Binary: $BIN_DIR/$BINARY_NAME"

  case ":$PATH:" in
    *":${BIN_DIR}:"*) ;;
    *)
      echo ""
      warn "$BIN_DIR is not in PATH. Add to your shell config:"
      printf "  ${BOLD}export PATH=\"\$PATH:$BIN_DIR\"${NC}\n"
      ;;
  esac
fi

echo ""
printf "${GREEN}${BOLD}ReplyVoice $VERSION installed successfully.${NC}\n\n"
