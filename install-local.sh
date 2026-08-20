#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="ritechoice23.omarchy.notification"

SOURCE_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
TARGET_PARENT="$(dirname "$TARGET_DIR")"
STAGING_DIR=""

cleanup() {
  [[ -z "$STAGING_DIR" || ! -e "$STAGING_DIR" ]] || rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT

command -v omarchy \
  >/dev/null 2>&1 || {
    echo "Omarchy was not found in PATH." >&2
    exit 1
  }

command -v jq \
  >/dev/null 2>&1 || {
    echo "jq is required." >&2
    exit 1
  }

mkdir -p "$TARGET_PARENT"

if [[ "$SOURCE_DIR" != "$TARGET_DIR" ]]; then
  STAGING_DIR="$(mktemp -d "$TARGET_PARENT/.${PLUGIN_ID}.staging.XXXXXX")"

  cp -a \
    "$SOURCE_DIR/manifest.json" \
    "$SOURCE_DIR/Panel.qml" \
    "$SOURCE_DIR/NotificationCard.qml" \
    "$SOURCE_DIR/README.md" \
    "$SOURCE_DIR/LICENSE" \
    "$SOURCE_DIR/CHANGELOG.md" \
    "$SOURCE_DIR/scripts" \
    "$STAGING_DIR/"

  omarchy plugin validate "$STAGING_DIR"
  rm -rf -- "$TARGET_DIR"
  mv -- "$STAGING_DIR" "$TARGET_DIR"
  STAGING_DIR=""
fi

omarchy plugin validate "$TARGET_DIR"

omarchy plugin enable "$PLUGIN_ID"

# Place the bell before the standard power widget when it exists. The put verb
# is idempotent: it places the widget if not already on the bar, and leaves one
# that is already there where it is.
omarchy bar put "$PLUGIN_ID" --before omarchy.power

# A complete restart guarantees Quickshell drops compiled components from a
# previous local build. File-by-file hot reload can otherwise retain stale QML.
omarchy restart shell

echo
echo "RiteChoice23 Notification is installed."
echo "Click the bell icon on the right side of the Omarchy bar."
