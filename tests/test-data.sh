#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  pwd
)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/state"

mkdir -p \
  "$HOME" \
  "$XDG_STATE_HOME/omarchy/notifications/history"

cp \
  "$ROOT/tests/fixtures/whatsapp-web.json" \
  "$XDG_STATE_HOME/omarchy/notifications/history/1787088873395-3.json"

output="$(
  bash \
    "$ROOT/scripts/notification-data" \
    200
)"

jq -e \
  '.unread == 1' \
  >/dev/null \
  <<<"$output"

jq -e \
  '.notifications | length == 1' \
  >/dev/null \
  <<<"$output"

jq -e \
  '.notifications[0].summary == "Project Team"' \
  >/dev/null \
  <<<"$output"

jq -e \
  '.notifications[0]._ritechoiceFile == "1787088873395-3.json"' \
  >/dev/null \
  <<<"$output"

bash "$ROOT/scripts/mark-seen"

output="$(
  bash \
    "$ROOT/scripts/notification-data" \
    200
)"

jq -e \
  '.unread == 0' \
  >/dev/null \
  <<<"$output"

bash \
  "$ROOT/scripts/dismiss-one" \
  "1787088873395-3.json"

output="$(
  bash \
    "$ROOT/scripts/notification-data" \
    200
)"

jq -e \
  '.notifications | length == 0' \
  >/dev/null \
  <<<"$output"

echo "All RiteChoice23 Notification data tests passed."
