#!/usr/bin/env bash
# Build the fork (Release, ad-hoc signed) and install it over /Applications/Maccy.app.
# Backs up the original App Store app and its sandbox container once, before the first install.
# Asks for the admin password because the App Store app is owned by root.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DEST="/Applications/Maccy.app"
APP_STAGING="/Applications/.Maccy.new.app"
APP_OLD="/Applications/.Maccy.old.app"
APP_BACKUP="$HOME/Applications/Maccy-2.7.1-backup.app"
# Only the data part of the sandbox container: its root holds containermanagerd
# metadata that macOS refuses to copy ("Operation not permitted").
CONTAINER="$HOME/Library/Containers/org.p0deje.Maccy/Data/Library"
CONTAINER_BACKUP="$HOME/Applications/Maccy-container-backup"
BUILT_APP="$REPO_DIR/build/Build/Products/Release/Maccy.app"
BUILD_LOG="$REPO_DIR/build/xcodebuild.log"

cd "$REPO_DIR"

echo "==> Requesting admin rights (needed to replace $APP_DEST)"
sudo -v

echo "==> Building Release"
mkdir -p build
if ! xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO build >"$BUILD_LOG" 2>&1; then
  tail -n 20 "$BUILD_LOG" >&2
  echo "Build failed. Full log: $BUILD_LOG" >&2
  exit 1
fi
tail -n 5 "$BUILD_LOG"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build product not found: $BUILT_APP (log: $BUILD_LOG)" >&2
  exit 1
fi

echo "==> Quitting running Maccy"
osascript -e 'quit app "Maccy"' || true
for _ in $(seq 1 20); do
  pgrep -x Maccy >/dev/null || break
  sleep 0.5
done
if pgrep -x Maccy >/dev/null; then
  echo "Maccy is still running. Quit it manually and re-run. Nothing was changed." >&2
  exit 1
fi

mkdir -p "$HOME/Applications"

# Copy to a .tmp path first and move into place only after ditto succeeded,
# so an interrupted copy is never mistaken for a complete backup.
backup_once() {
  local src="$1" dest="$2"
  if [[ -e "$dest" ]]; then
    return 0
  fi
  echo "==> Backing up $src to $dest"
  rm -rf "$dest.tmp"
  ditto "$src" "$dest.tmp"
  mv "$dest.tmp" "$dest"
}

if [[ -d "$APP_DEST/Contents/_MASReceipt" ]]; then
  backup_once "$APP_DEST" "$APP_BACKUP"
else
  echo "==> $APP_DEST is not the App Store build (no _MASReceipt); skipping app backup"
fi

if [[ -d "$CONTAINER" ]]; then
  backup_once "$CONTAINER" "$CONTAINER_BACKUP"
fi

echo "==> Installing to $APP_DEST"
sudo rm -rf "$APP_STAGING"
sudo ditto "$BUILT_APP" "$APP_STAGING"
# Keep the old app until the new one is in place, so a failed move can be rolled back.
sudo rm -rf "$APP_OLD"
if [[ -e "$APP_DEST" ]]; then
  sudo mv "$APP_DEST" "$APP_OLD"
fi
if ! sudo mv "$APP_STAGING" "$APP_DEST"; then
  echo "Install failed; restoring the previous app." >&2
  if [[ -e "$APP_OLD" ]]; then
    sudo mv "$APP_OLD" "$APP_DEST"
  fi
  exit 1
fi
sudo rm -rf "$APP_OLD"

# Forget the build-directory copy so macOS launches /Applications/Maccy.app
# (its Accessibility grant is tied to that path).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$BUILT_APP" || true
"$LSREGISTER" -f "$APP_DEST" || true

echo "==> Launching"
open "$APP_DEST"

cat <<'MSG'

Installed. Next steps:
  1. System Settings > Privacy & Security > Accessibility: remove the Maccy entry
     (minus button) and add /Applications/Maccy.app again. The ad-hoc signature
     changes with every build, so this is needed after each install.
  2. If macOS asks whether Maccy may access data from other apps, allow it so the
     clipboard history is kept.
  3. Turn off automatic App Store updates for Maccy, or an update may overwrite the fork.
MSG
