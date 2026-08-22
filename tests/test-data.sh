#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'jobs -pr | xargs -r kill 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
CLI="$TEST_ROOT/notification-center"
ln -s "$ROOT/bin/notification-center" "$CLI"

export XDG_STATE_HOME="$TEST_ROOT/state"
export RITECHOICE_NOTIFICATION_SOURCE="$TEST_ROOT/source"
export RITECHOICE_NOTIFICATION_STATE="$TEST_ROOT/store"
export RITECHOICE_KEEP_DAYS=30
export RITECHOICE_HISTORY_LIMIT=100
export RITECHOICE_KEEP_PREVIEWS=1
mkdir -p "$RITECHOICE_NOTIFICATION_SOURCE/history" "$RITECHOICE_NOTIFICATION_STATE/history" "$TEST_ROOT/bin"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_ROOT/bin/omarchy-shell"
chmod +x "$TEST_ROOT/bin/omarchy-shell"
export PATH="$TEST_ROOT/bin:$PATH"

now="$(date +%s%3N)"
tiny_png="$TEST_ROOT/tiny.png"
base64 -d > "$tiny_png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
PNG
file -b --mime-type "$tiny_png" | grep -q '^image/'

write_source() {
  local name="$1" timestamp="$2" app="$3" summary="$4" body="${5:-}" exec_value="${6:-}" app_icon="${7:-}" image="${8:-}"
  jq -cn \
    --arg app "$app" --arg summary "$summary" --arg body "$body" --arg exec "$exec_value" \
    --arg appIcon "$app_icon" --arg image "$image" --argjson timestamp "$timestamp" \
    '{id:1,app:$app,appIcon:$appIcon,summary:$summary,body:$body,image:$image,exec:$exec,urgency:1,timestamp:$timestamp}' \
    > "$RITECHOICE_NOTIFICATION_SOURCE/history/$name"
}

# First sync preserves content but strips sender-controlled actions.
marker="$TEST_ROOT/should-not-run"
legacy_name="$((now - 1))-2.json"
jq -cn --arg exec "touch $marker" --argjson timestamp "$((now - 1))" '{app:"Legacy",summary:"Still here",body:"Preserved",exec:$exec,timestamp:$timestamp,_ritechoiceFile:"legacy.json"}' \
  > "$RITECHOICE_NOTIFICATION_STATE/history/$legacy_name"
write_source "$now-1.json" "$now" "Slack" "Project ready" "Review the release" "touch $marker"
$CLI sync >/dev/null
result="$($CLI list 100)"
jq -e '.ok and .total == 2 and .unread == 2 and .notifications[0].summary == "Project ready"' >/dev/null <<< "$result"
jq -e '.notifications[0] | has("exec") | not' >/dev/null <<< "$result"
jq -e 'has("exec") | not' "$RITECHOICE_NOTIFICATION_STATE/history/$now-1.json" >/dev/null
[[ ! -e "$marker" ]]

# Existing v1 archives are migrated in place without losing notification data.
result="$($CLI list 100)"
jq -e '.notifications | map(select(.summary == "Still here")) | length == 1' >/dev/null <<< "$result"
jq -e 'has("exec") | not' "$RITECHOICE_NOTIFICATION_STATE/history/$legacy_name" >/dev/null
[[ ! -e "$marker" ]]

# Store permissions are private and repaired on every invocation.
chmod 755 "$RITECHOICE_NOTIFICATION_STATE" "$RITECHOICE_NOTIFICATION_STATE/history"
chmod 644 "$RITECHOICE_NOTIFICATION_STATE/history/$legacy_name"
$CLI list 100 >/dev/null
[[ "$(stat -c '%a' "$RITECHOICE_NOTIFICATION_STATE")" == 700 ]]
[[ "$(stat -c '%a' "$RITECHOICE_NOTIFICATION_STATE/history")" == 700 ]]
[[ "$(stat -c '%a' "$RITECHOICE_NOTIFICATION_STATE/history/$legacy_name")" == 600 ]]

# Malformed input is ignored and cannot poison the complete result.
printf '{broken\n' > "$RITECHOICE_NOTIFICATION_SOURCE/history/broken.json"
before="$(jq '.total' <<< "$($CLI list 100)")"
after="$(jq '.total' <<< "$($CLI list 100)")"
[[ "$before" == "$after" ]]

# Valid images are copied privately; fake and oversized images are rejected.
valid_name="$((now + 1))-3.json"
write_source "$valid_name" "$((now + 1))" "Camera" "Valid image" "" "" "file://$tiny_png"
fake_png="$TEST_ROOT/fake.png"
printf 'not an image' > "$fake_png"
fake_name="$((now + 2))-4.json"
write_source "$fake_name" "$((now + 2))" "Camera" "Fake image" "" "" "file://$fake_png"
large_png="$TEST_ROOT/large.png"
cp "$tiny_png" "$large_png"
truncate -s 5242881 "$large_png"
large_name="$((now + 3))-5.json"
write_source "$large_name" "$((now + 3))" "Camera" "Large image" "" "" "file://$large_png"
$CLI sync >/dev/null
result="$($CLI list 100)"
cached_icon="$(jq -r '.notifications[] | select(.summary == "Valid image") | .appIcon' <<< "$result")"
[[ "$cached_icon" == file://"$RITECHOICE_NOTIFICATION_STATE"/images/* ]]
[[ -f "${cached_icon#file://}" && "$(stat -c '%a' "${cached_icon#file://}")" == 600 ]]
jq -e '.notifications[] | select(.summary == "Fake image") | .appIcon == ""' >/dev/null <<< "$result"
jq -e '.notifications[] | select(.summary == "Large image") | .appIcon == ""' >/dev/null <<< "$result"

# A narrowly extracted image path becomes a validated preview; the command is discarded.
preview_name="$((now + 4))-6.json"
write_source "$preview_name" "$((now + 4))" "Screenshot" "Preview" "" "xdg-open $tiny_png"
$CLI sync >/dev/null
result="$($CLI list 100)"
preview_uri="$(jq -r '.notifications[] | select(.summary == "Preview") | .preview' <<< "$result")"
[[ "$preview_uri" == file://"$RITECHOICE_NOTIFICATION_STATE"/images/*-preview ]]
jq -e '.notifications[] | select(.summary == "Preview") | has("exec") | not' >/dev/null <<< "$result"

# Disabling previews removes cached pictures and clears their archive roles.
RITECHOICE_KEEP_PREVIEWS=0 $CLI list 100 > "$TEST_ROOT/no-previews.json"
jq -e '[.notifications[] | select((.image // "") != "" or (.preview // "") != "")] | length == 0' "$TEST_ROOT/no-previews.json" >/dev/null
if find "$RITECHOICE_NOTIFICATION_STATE/images" -maxdepth 1 -type f \( -name '*-image' -o -name '*-preview' \) | grep -q .; then
  echo "preview-disabled mode retained cached pictures" >&2
  exit 1
fi

# Seen watermarks are monotonic and unread survives separate CLI invocations.
$CLI seen "$((now + 2))" | jq -e ".ok and .seen == $((now + 2))" >/dev/null
$CLI seen 100 | jq -e ".seen == $((now + 2))" >/dev/null
$CLI unread | jq -e '.ok and .unread >= 1' >/dev/null

# Search covers app, title, and body without changing the archive.
$CLI search "release" 100 | jq -e '.notifications | length == 1 and .[0].summary == "Project ready"' >/dev/null
$CLI search "camera" 100 | jq -e '.notifications | length == 3' >/dev/null

# Count and age retention both apply, newest first.
RITECHOICE_HISTORY_LIMIT=2 $CLI prune | jq -e '.ok' >/dev/null
result="$(RITECHOICE_HISTORY_LIMIT=2 $CLI list 100)"
jq -e '.total == 2 and .notifications[0].timestamp >= .notifications[1].timestamp' >/dev/null <<< "$result"
old_timestamp=$((now - 31 * 86400000))
old_name="$old_timestamp-7.json"
write_source "$old_name" "$old_timestamp" "Old" "Expired" ""
$CLI sync >/dev/null
[[ ! -e "$RITECHOICE_NOTIFICATION_STATE/history/$old_name" ]]

# Concurrent syncs produce valid, deduplicated per-notification records.
for _ in 1 2 3 4; do $CLI sync >/dev/null & done
wait
find "$RITECHOICE_NOTIFICATION_STATE/history" -maxdepth 1 -type f -name '*.json' -print0 |
  xargs -0 -r -n1 jq -e 'type == "object" and (has("exec") | not)' >/dev/null

# The watcher streams a newly archived notification and remains restart-safe.
watch_log="$TEST_ROOT/watch.log"
timeout 5 "$CLI" watch > "$watch_log" 2> "$TEST_ROOT/watch.err" &
watch_pid=$!
watch_cli_pid=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  watch_cli_pid="$(pgrep -P "$watch_pid" -f 'notification-center watch' | head -n 1 || true)"
  [[ -n "$watch_cli_pid" ]] && pgrep -P "$watch_cli_pid" inotifywait >/dev/null 2>&1 && break
  sleep 0.05
done
[[ -n "$watch_cli_pid" ]]
pgrep -P "$watch_cli_pid" inotifywait >/dev/null
watch_timestamp=$((now + 10))
write_source "$watch_timestamp-8.json" "$watch_timestamp" "Signal" "Watcher event" "Arrived live"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  grep -q '"event":"changed"' "$watch_log" && break
  sleep 0.05
done
grep -q '"event":"changed"' "$watch_log"
$CLI list 100 | jq -e '.notifications | map(select(.summary == "Watcher event")) | length == 1' >/dev/null
kill "$watch_pid" 2>/dev/null || true
wait "$watch_pid" 2>/dev/null || true

# Orphaned media is swept and unsafe removal names are rejected.
printf 'orphan' > "$RITECHOICE_NOTIFICATION_STATE/images/orphan-image"
$CLI prune >/dev/null
[[ ! -e "$RITECHOICE_NOTIFICATION_STATE/images/orphan-image" ]]
first_file="$(find "$RITECHOICE_NOTIFICATION_STATE/history" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | head -n 1)"
[[ -n "$first_file" ]]
$CLI remove "$first_file" | jq -e '.ok and .removed == 1' >/dev/null
[[ ! -e "$RITECHOICE_NOTIFICATION_STATE/history/$first_file" ]]
[[ -e "$RITECHOICE_NOTIFICATION_STATE/dismissed/$first_file" ]]
if $CLI remove ../outside.json >/dev/null 2>&1; then
  echo "remove accepted path traversal" >&2
  exit 1
fi

# Clear cannot resurrect source records even when Omarchy IPC is a no-op.
$CLI clear | jq -e '.ok and .cleared' >/dev/null
result="$($CLI list 100)"
jq -e '.notifications == [] and .total == 0 and .unread == 0' >/dev/null <<< "$result"

echo "All RiteChoice23 Notification storage tests passed."
