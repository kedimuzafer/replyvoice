#!/usr/bin/env sh
# ReplyVoice — Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/kedimuzafer/ses/main/install.sh | sh

set -e

REPO="kedimuzafer/replyvoice"
APP_NAME="ReplyVoice"
BINARY_NAME="replyvoice"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { printf "${BOLD}==> %s${NC}\n" "$*"; }
ok()      { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}⚠${NC}  %s\n" "$*"; }
die()     { printf "${RED}✗${NC}  %s\n" "$*" >&2; exit 1; }

# OS & arch
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Linux)  PLATFORM="linux" ;;
  Darwin) PLATFORM="macos" ;;
  *)      die "Unsupported OS: $OS. On Windows use the .exe from: https://github.com/${REPO}/releases" ;;
esac
case "$ARCH" in
  x86_64|amd64)  ARCH_KEY="x86_64" ;;
  arm64|aarch64) ARCH_KEY="arm64" ;;
  *)             die "Unsupported architecture: $ARCH" ;;
esac

# Asset name
case "${PLATFORM}-${ARCH_KEY}" in
  linux-x86_64)  ASSET="${APP_NAME}-linux-x86_64.tar.gz" ;;
  macos-arm64)   ASSET="${APP_NAME}-macos-arm64.dmg" ;;
  macos-x86_64)  ASSET="${APP_NAME}-macos-x86_64.dmg" ;;
  linux-arm64)   die "Linux arm64 is not yet supported. Check https://github.com/${REPO}/releases" ;;
  *)             die "No binary for ${PLATFORM}-${ARCH_KEY}" ;;
esac

# Downloader
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2"; }
  fetch_text() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
  fetch_text() { wget -qO- "$1"; }
else
  die "curl or wget is required"
fi

# Resolve latest version
info "Fetching latest version..."
VERSION="$(fetch_text "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
[ -z "$VERSION" ] && die "Could not determine latest version. Check: https://github.com/${REPO}/releases"
ok "Version: $VERSION"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

# Download
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Downloading $ASSET..."
fetch "$DOWNLOAD_URL" "$TMP_DIR/$ASSET" || die "Download failed. Check: https://github.com/${REPO}/releases"

# Install
if [ "$PLATFORM" = "linux" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    OPT_DIR="/opt/${APP_NAME}"; BIN_DIR="/usr/local/bin"
    DESK_DIR="/usr/share/applications"; ICON_DIR="/usr/share/icons/hicolor/128x128/apps"
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
  ln -sf "$OPT_DIR/bin/${BINARY_NAME}" "$BIN_DIR/${BINARY_NAME}"

  [ -f "$OPT_DIR/share/applications/${APP_NAME}.desktop" ] && \
    sed "s|Exec=.*|Exec=${BIN_DIR}/${BINARY_NAME}|" \
      "$OPT_DIR/share/applications/${APP_NAME}.desktop" \
      > "$DESK_DIR/${APP_NAME}.desktop"

  [ -f "$OPT_DIR/share/icons/hicolor/128x128/apps/${BINARY_NAME}.png" ] && \
    cp "$OPT_DIR/share/icons/hicolor/128x128/apps/${BINARY_NAME}.png" "$ICON_DIR/${BINARY_NAME}.png"

  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESK_DIR" 2>/dev/null || true

  ok "Installed to $OPT_DIR"
  ok "Binary: $BIN_DIR/$BINARY_NAME"

  case ":$PATH:" in
    *":${BIN_DIR}:"*) ;;
    *)
      echo ""
      warn "$BIN_DIR is not in your PATH. Add to your shell config:"
      printf "  ${BOLD}export PATH=\"\$PATH:$BIN_DIR\"${NC}\n"
      ;;
  esac

elif [ "$PLATFORM" = "macos" ]; then
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
fi

echo ""
printf "${GREEN}${BOLD}ReplyVoice $VERSION installed successfully.${NC}\n\n"
