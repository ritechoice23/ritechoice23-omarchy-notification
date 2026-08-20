#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/state"
export RITECHOICE_DESKTOP_DIRS="$TMP/applications"
export RITECHOICE_HYPRCTL_BIN="$TMP/bin/hyprctl"
mkdir -p "$HOME" "$XDG_STATE_HOME/ritechoice23-omarchy-notification/history" "$TMP/applications" "$TMP/bin"

clients_file="$TMP/clients.json"
dispatch_log="$TMP/dispatch.log"
export TEST_CLIENTS_FILE="$clients_file"
export TEST_DISPATCH_LOG="$dispatch_log"

apply_patch_placeholder=unused
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ ${1:-} == -j && ${2:-} == clients ]]; then' \
  '  cat "$TEST_CLIENTS_FILE"' \
  '  exit 0' \
  'fi' \
  'printf "%s\\n" "$*" >> "$TEST_DISPATCH_LOG"' \
  'exit 0' > "$TMP/bin/hyprctl"
chmod +x "$TMP/bin/hyprctl"

write_record() {
  local file="$1" app="$2" body="$3" action="${4:-}"
  jq -cn --arg app "$app" --arg body "$body" --arg action "$action" '{
    app: $app, body: $body, summary: "Test", exec: $action, timestamp: 1787088875000
  }' > "$XDG_STATE_HOME/ritechoice23-omarchy-notification/history/$file"
}

# The web origin outranks a generic browser window and focuses the PWA address.
write_record whatsapp.json "Google Chrome" '<a href="https://web.whatsapp.com/">web.whatsapp.com</a>'
jq -cn '[
  {address:"0xchrome",class:"google-chrome",initialClass:"google-chrome",title:"Browser"},
  {address:"0xwhatsapp",class:"chrome-web.whatsapp.com__-Default",initialClass:"chrome-web.whatsapp.com__-Default",title:"web.whatsapp.com"}
]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" whatsapp.json)"
jq -e '.ok and .method == "window" and .address == "0xwhatsapp"' >/dev/null <<<"$result"
grep -q 'address:0xwhatsapp' "$dispatch_log"

# Desktop StartupWMClass resolves a native application's window identity.
printf '%s\n' '[Desktop Entry]' 'Name=Slack' 'StartupWMClass=Slack' > "$TMP/applications/slack.desktop"
write_record slack.json "Slack" "Message"
jq -cn '[{address:"0xslack",class:"Slack",initialClass:"Slack",title:"General - Slack"}]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" slack.json)"
jq -e '.ok and .address == "0xslack"' >/dev/null <<<"$result"

# Normalization maps a display name containing spaces to a hyphenated class.
write_record chrome.json "Google Chrome" "Download complete"
jq -cn '[{address:"0xchrome",class:"google-chrome",initialClass:"google-chrome",title:"Downloads"}]' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" chrome.json)"
jq -e '.ok and .address == "0xchrome"' >/dev/null <<<"$result"

# Omarchy's persisted action contract takes priority over window matching.
action_marker="$TMP/action-ran"
write_record action.json "Installer" "Ready" "printf done > '$action_marker'"
printf '[]\n' > "$clients_file"
result="$(bash "$ROOT/scripts/activate-notification" action.json)"
jq -e '.ok and .method == "action"' >/dev/null <<<"$result"
for _ in 1 2 3 4 5; do [[ -f "$action_marker" ]] && break; sleep 0.05; done
[[ "$(<"$action_marker")" == done ]]

# Missing targets and unsafe filenames fail without dispatching or launching.
write_record missing.json "Not Running" "Message"
printf '[]\n' > "$clients_file"
if bash "$ROOT/scripts/activate-notification" missing.json > "$TMP/missing-result"; then
  echo "activation unexpectedly succeeded without a target" >&2
  exit 1
fi
jq -e '.ok == false and .error == "app-window-unavailable"' >/dev/null < "$TMP/missing-result"
if bash "$ROOT/scripts/activate-notification" ../outside.json >/dev/null 2>&1; then
  echo "activation accepted an unsafe filename" >&2
  exit 1
fi

echo "All RiteChoice23 Notification activation tests passed."
