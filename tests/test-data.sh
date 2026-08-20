#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME" "$XDG_STATE_HOME/omarchy/notifications/history" "$TMP/bin"

# clear-all talks to Omarchy before clearing the independent archive.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/omarchy-shell"
chmod +x "$TMP/bin/omarchy-shell"
export PATH="$TMP/bin:$PATH"

fixture_timestamp=1787088873395
cp "$ROOT/tests/fixtures/whatsapp-web.json" \
  "$XDG_STATE_HOME/omarchy/notifications/history/${fixture_timestamp}-3.json"

output="$(bash "$ROOT/scripts/notification-data" 200)"
jq -e '.unread == 1 and .maxTimestamp == 1787088873395' >/dev/null <<<"$output"
jq -e '.notifications | length == 1' >/dev/null <<<"$output"
jq -e '.notifications[0].summary == "Project Team"' >/dev/null <<<"$output"
jq -e '.notifications[0]._ritechoiceFile == "1787088873395-3.json"' >/dev/null <<<"$output"

# Malformed source files are ignored without poisoning the complete result.
printf '{broken\n' > "$XDG_STATE_HOME/omarchy/notifications/history/broken.json"
output="$(bash "$ROOT/scripts/notification-data" 200)"
jq -e '.notifications | length == 1' >/dev/null <<<"$output"

# Seen watermarks only move forward.
bash "$ROOT/scripts/mark-seen" "$fixture_timestamp"
bash "$ROOT/scripts/mark-seen" 100
[[ "$(<"$XDG_STATE_HOME/ritechoice23-omarchy-notification/last-seen")" == "$fixture_timestamp" ]]
output="$(bash "$ROOT/scripts/notification-data" 200)"
jq -e '.unread == 0' >/dev/null <<<"$output"

# File-backed media is copied into the plugin-owned cache.
printf 'image bytes' > "$TMP/avatar.png"
jq -cn --arg icon "file://$TMP/avatar.png" '{
  id: 4, app: "Example", appIcon: $icon, summary: "With image", body: "",
  urgency: 1, timestamp: 1787088874000
}' > "$XDG_STATE_HOME/omarchy/notifications/history/1787088874000-4.json"
output="$(bash "$ROOT/scripts/notification-data" 200)"
cached_icon="$(jq -r '.notifications[] | select(.id == 4) | .appIcon' <<<"$output")"
[[ "$cached_icon" == file://"$XDG_STATE_HOME"/ritechoice23-omarchy-notification/images/* ]]
[[ -f "${cached_icon#file://}" ]]

# Pruning keeps the newest timestamp, not the lexically newest filename.
jq -cn '{id:5,app:"Example",summary:"Newest",timestamp:1787088875000}' \
  > "$XDG_STATE_HOME/omarchy/notifications/history/a.json"
output="$(bash "$ROOT/scripts/notification-data" 2)"
jq -e '.notifications | length == 2' >/dev/null <<<"$output"
jq -e '.notifications[0].summary == "Newest"' >/dev/null <<<"$output"

# Concurrent per-monitor refreshes leave only valid JSON records behind.
for _ in 1 2 3 4; do bash "$ROOT/scripts/notification-data" 20 > /dev/null & done
wait
find "$XDG_STATE_HOME/ritechoice23-omarchy-notification/history" -type f -name '*.json' -print0 |
  xargs -0 -r -n1 jq -e 'type == "object"' >/dev/null

# Dismiss supports batches and rejects path traversal before making changes.
mapfile -t archived < <(find "$XDG_STATE_HOME/ritechoice23-omarchy-notification/history" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | head -n 2)
(( ${#archived[@]} == 2 ))
bash "$ROOT/scripts/dismiss-one" "${archived[@]}"
for file in "${archived[@]}"; do
  [[ ! -e "$XDG_STATE_HOME/ritechoice23-omarchy-notification/history/$file" ]]
  [[ -e "$XDG_STATE_HOME/ritechoice23-omarchy-notification/dismissed/$file" ]]
done
if bash "$ROOT/scripts/dismiss-one" ../outside.json 2>/dev/null; then
  echo "dismiss-one accepted an unsafe filename" >&2
  exit 1
fi

# Clear cannot resurrect source records even when the shell IPC is ineffective.
bash "$ROOT/scripts/notification-data" 200 >/dev/null
bash "$ROOT/scripts/clear-all"
output="$(bash "$ROOT/scripts/notification-data" 200)"
jq -e '.notifications == [] and .unread == 0 and .maxTimestamp == 0' >/dev/null <<<"$output"

echo "All RiteChoice23 Notification data tests passed."
