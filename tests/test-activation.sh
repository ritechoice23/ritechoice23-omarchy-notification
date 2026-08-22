#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export RITECHOICE_DESKTOP_DIRS="$TEST_ROOT/applications"
export RITECHOICE_HYPRCTL_BIN="$TEST_ROOT/bin/hyprctl"
export RITECHOICE_XDG_OPEN_BIN="$TEST_ROOT/bin/xdg-open"
STATE_DIR="$XDG_STATE_HOME/ritechoice23-omarchy-notification"
mkdir -p "$STATE_DIR/history" "$STATE_DIR/images" "$RITECHOICE_DESKTOP_DIRS" "$TEST_ROOT/bin"

clients_file="$TEST_ROOT/clients.json"
dispatch_log="$TEST_ROOT/dispatch.log"
open_log="$TEST_ROOT/open.log"
export TEST_CLIENTS_FILE="$clients_file"
export TEST_DISPATCH_LOG="$dispatch_log"
export TEST_OPEN_LOG="$open_log"

printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ ${1:-} == -j && ${2:-} == clients ]]; then' \
  '  cat "$TEST_CLIENTS_FILE"' \
  '  exit 0' \
  'fi' \
  'printf "%s\n" "$*" >> "$TEST_DISPATCH_LOG"' \
  '[[ ${TEST_DISPATCH_FAIL:-0} != 1 ]]' > "$RITECHOICE_HYPRCTL_BIN"
chmod +x "$RITECHOICE_HYPRCTL_BIN"

printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$1" >> "$TEST_OPEN_LOG"' \
  '[[ ${TEST_OPEN_FAIL:-0} != 1 ]]' > "$RITECHOICE_XDG_OPEN_BIN"
chmod +x "$RITECHOICE_XDG_OPEN_BIN"

write_record() {
  local file="$1" app="$2" body="$3" action="${4:-}" preview="${5:-}"
  jq -cn --arg app "$app" --arg body "$body" --arg action "$action" --arg preview "$preview" '{
    app:$app,body:$body,summary:"Test",exec:$action,preview:$preview,timestamp:1787088875000,_ritechoiceFile:"record.json"
  }' > "$STATE_DIR/history/$file"
}

# Auto opens only a validated image already inside the private archive.
safe_image="$STATE_DIR/images/safe-preview"
base64 -d > "$safe_image" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
PNG
write_record image.json "Screenshot" "Saved" "touch $TEST_ROOT/hostile" "file://$safe_image"
printf '[]\n' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" image.json Auto)"
jq -e '.ok and .method == "image"' >/dev/null <<< "$result"
grep -Fxq "$safe_image" "$open_log"
[[ ! -e "$TEST_ROOT/hostile" ]]

# Image-open failure is reported and does not fall through to an unrelated app.
export TEST_OPEN_FAIL=1
if bash "$ROOT/scripts/activate-notification" image.json Auto > "$TEST_ROOT/open-failed.json"; then
  echo "image activation succeeded despite opener failure" >&2
  exit 1
fi
jq -e '.error == "image-open-failed"' "$TEST_ROOT/open-failed.json" >/dev/null
unset TEST_OPEN_FAIL

# External and non-image paths are never opened.
external_image="$TEST_ROOT/external.png"
cp "$safe_image" "$external_image"
write_record external.json "Not Running" "Message" "" "file://$external_image"
if bash "$ROOT/scripts/activate-notification" external.json Auto > "$TEST_ROOT/external.json.result"; then
  echo "external image activation unexpectedly succeeded" >&2
  exit 1
fi
jq -e '.error == "app-window-unavailable"' "$TEST_ROOT/external.json.result" >/dev/null

# A planted stored command is ignored even when there is no other target.
marker="$TEST_ROOT/action-ran"
write_record hostile.json "Not Running" "Message" "printf done > $marker"
printf '[]\n' > "$clients_file"
if bash "$ROOT/scripts/activate-notification" hostile.json Auto > "$TEST_ROOT/hostile-result.json"; then
  echo "hostile notification unexpectedly activated" >&2
  exit 1
fi
[[ ! -e "$marker" ]]
jq -e '.error == "app-window-unavailable"' "$TEST_ROOT/hostile-result.json" >/dev/null

# Web origin outranks a generic browser window and focuses the exact PWA address.
write_record whatsapp.json "Google Chrome" '<a href="https://web.whatsapp.com/">web.whatsapp.com</a>'
jq -cn '[
  {address:"0xchrome",class:"google-chrome",initialClass:"google-chrome",title:"Browser"},
  {address:"0xwhatsapp",class:"chrome-web.whatsapp.com__-Default",initialClass:"chrome-web.whatsapp.com__-Default",title:"web.whatsapp.com"}
]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" whatsapp.json Auto)"
jq -e '.ok and .method == "window" and .address == "0xwhatsapp"' >/dev/null <<< "$result"
grep -q 'address:0xwhatsapp' "$dispatch_log"

# Desktop StartupWMClass resolves a native application's identity.
printf '%s\n' '[Desktop Entry]' 'Name=Slack' 'StartupWMClass=Slack' > "$RITECHOICE_DESKTOP_DIRS/slack.desktop"
write_record slack.json "Slack" "Message"
jq -cn '[{address:"0xslack",class:"Slack",initialClass:"Slack",title:"General - Slack"}]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" slack.json "Focus the app")"
jq -e '.ok and .address == "0xslack"' >/dev/null <<< "$result"

# Normalization maps display names with spaces to hyphenated classes.
write_record chrome.json "Google Chrome" "Download complete"
jq -cn '[{address:"0xchrome",class:"google-chrome",initialClass:"google-chrome",title:"Downloads"}]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" chrome.json Auto)"
jq -e '.ok and .address == "0xchrome"' >/dev/null <<< "$result"

# Equal-score ties resolve deterministically to the first compositor client.
write_record tie.json "Editor" "Ready"
jq -cn '[
  {address:"0xfirst",class:"editor",initialClass:"editor",title:"One"},
  {address:"0xsecond",class:"editor",initialClass:"editor",title:"Two"}
]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" tie.json Auto)"
jq -e '.ok and .address == "0xfirst"' >/dev/null <<< "$result"

# Dispatch failure is surfaced instead of being treated as successful focus.
export TEST_DISPATCH_FAIL=1
if bash "$ROOT/scripts/activate-notification" tie.json Auto > "$TEST_ROOT/focus-failed.json"; then
  echo "focus activation succeeded despite dispatch failure" >&2
  exit 1
fi
jq -e '.error == "focus-failed"' "$TEST_ROOT/focus-failed.json" >/dev/null
unset TEST_DISPATCH_FAIL

# Read-only mode and unsafe archive names fail without opening or dispatching.
if bash "$ROOT/scripts/activate-notification" tie.json Nothing > "$TEST_ROOT/disabled.json"; then
  echo "Nothing click policy unexpectedly activated" >&2
  exit 1
fi
jq -e '.error == "activation-disabled"' "$TEST_ROOT/disabled.json" >/dev/null
if bash "$ROOT/scripts/activate-notification" ../outside.json Auto >/dev/null 2>&1; then
  echo "activation accepted path traversal" >&2
  exit 1
fi

# The QML contract dismisses immediately and performs activation after the
# panel has closed. Background failure must not restore the card.
rg -U 'function activateOne\(entry\)[\s\S]*root\.dismissOne\(file\)[\s\S]*root\.close\(\)[\s\S]*activateProc\.command' "$ROOT/Panel.qml" >/dev/null
rg 'if \(!entry \|\| activationEntry \|\| clickAction === "Nothing"\) return' "$ROOT/Panel.qml" >/dev/null
if rg 'Opening…|root\.dismissOne\(file\)' "$ROOT/NotificationCard.qml" >/dev/null; then
  echo "notification card still exposes blocking activation UI" >&2
  exit 1
fi

echo "All RiteChoice23 Notification activation tests passed."
