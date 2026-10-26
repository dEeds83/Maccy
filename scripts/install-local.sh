#!/usr/bin/env bash
# Build the fork (Release, ad-hoc signed) and install it over /Applications/Maccy.app.
# Backs up the original app and its sandbox container once, before the first install.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DEST="/Applications/Maccy.app"
APP_BACKUP="$HOME/Applications/Maccy-2.7.1-backup.app"
CONTAINER="$HOME/Library/Containers/org.p0deje.Maccy"
CONTAINER_BACKUP="$HOME/Applications/Maccy-container-backup"
BUILT_APP="$REPO_DIR/build/Build/Products/Release/Maccy.app"

cd "$REPO_DIR"

echo "==> Building Release"
xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- build | tail -n 5

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build product not found: $BUILT_APP" >&2
  exit 1
fi

mkdir -p "$HOME/Applications"

echo "==> Quitting running Maccy"
osascript -e 'quit app "Maccy"' || true
sleep 2

if [[ -d "$APP_DEST" && ! -e "$APP_BACKUP" ]]; then
  echo "==> Backing up original app to $APP_BACKUP"
  ditto "$APP_DEST" "$APP_BACKUP"
fi

if [[ -d "$CONTAINER" && ! -e "$CONTAINER_BACKUP" ]]; then
  echo "==> Backing up sandbox container to $CONTAINER_BACKUP"
  ditto "$CONTAINER" "$CONTAINER_BACKUP"
fi

echo "==> Installing to $APP_DEST"
rm -rf "$APP_DEST"
ditto "$BUILT_APP" "$APP_DEST"

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
