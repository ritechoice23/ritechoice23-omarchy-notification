#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="ritechoice23.omarchy.notification"

SOURCE_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

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

mkdir -p \
  "$(dirname "$TARGET_DIR")"

if [[ "$SOURCE_DIR" != "$TARGET_DIR" ]]; then
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"

  cp -a \
    "$SOURCE_DIR/manifest.json" \
    "$SOURCE_DIR/Panel.qml" \
    "$SOURCE_DIR/README.md" \
    "$SOURCE_DIR/LICENSE" \
    "$SOURCE_DIR/CHANGELOG.md" \
    "$SOURCE_DIR/scripts" \
    "$TARGET_DIR/"
fi

omarchy plugin validate "$TARGET_DIR"

omarchy-shell shell rescanPlugins

omarchy plugin enable "$PLUGIN_ID"

# Place the bell before the standard power widget when it exists. The put verb
# is idempotent: it places the widget if not already on the bar, and leaves one
# that is already there where it is.
omarchy bar put "$PLUGIN_ID" --before omarchy.power

echo
echo "RiteChoice23 Notification is installed."
echo "Click the bell icon on the right side of the Omarchy bar."

