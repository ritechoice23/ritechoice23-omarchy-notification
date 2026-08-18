#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="ritechoice23.omarchy.notification"
TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

omarchy plugin disable "$PLUGIN_ID" \
  >/dev/null 2>&1 || true

rm -rf "$TARGET_DIR"

omarchy-shell shell rescanPlugins \
  >/dev/null 2>&1 || true

echo "RiteChoice23 Notification has been removed."
echo
echo "Saved notification history was kept at:"
echo "  ${XDG_STATE_HOME:-$HOME/.local/state}/ritechoice23-omarchy-notification"
echo
echo "Delete that directory manually if you also want to remove its history."
