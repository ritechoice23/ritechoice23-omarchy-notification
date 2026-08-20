# Omarchy Notification

A polished, keyboard-driven notification center and history archive for the Omarchy top bar.

Omarchy Notification adds an unread-badged bell widget to Omarchy's Quickshell bar. Its chronological, macOS-inspired card list keeps every retained notification visible while following Omarchy's active palette, spacing, typography, control states, and window corner radius.

---

## Features

- **Native Omarchy v4 Bar Widget**: Built with Quickshell and Omarchy's shared UI, notification color, control-state, spacing, and radius tokens.
- **Chronological Cards**: Every retained notification is shown newest-first in Today, Yesterday, and older date sections—never hidden inside a collapsed app group.
- **Full Keyboard Navigation**: Navigate with Vim keys (`j`/`k`) or arrows, switch panels with `Tab`, focus apps with `Enter`, and dismiss with `x`.
- **Smart Click-to-Focus**: Runs preserved Omarchy actions first, otherwise resolves PWAs, desktop entries, and app classes before focusing the exact Hyprland window address.
- **Urgency Highlights**: Critical-priority notifications (`urgency == 2`) are outlined with `Color.urgent`.
- **Smart Web Origin Filtering**: Automatically cleans noisy browser prefixes (e.g. `web.whatsapp.com`, `mail.google.com`) and resolves clean labels like "WhatsApp" or "Gmail".
- **Independent History Archive**: Retains up to 200 recent notifications locally in `~/.local/state/` even after toasts dismiss.
- **Configurable Settings**: Custom archive limits and badge visibility configurable via GUI or `omarchy bar set`.
- **IPC & Hotkey Support**: Summon or toggle the panel from anywhere using `omarchy-shell` or Hyprland keybinds.
- **Responsive & Durable**: Watches Omarchy's notification state for immediate updates, falls back to low-frequency polling, and serializes archive work across monitors.

---

## Installation

### From GitHub

```bash
omarchy plugin add https://github.com/ritechoice23/ritechoice23-omarchy-notification.git --enable --yes
```

Place the bell before the standard power widget (or wherever you prefer on your bar):

```bash
omarchy bar put ritechoice23.omarchy.notification --before omarchy.power
```

### Local Development Install

From this repository directory:

```bash
bash install-local.sh
```

---

## Usage

### Mouse & Keyboard Controls

| Input | Action |
| :--- | :--- |
| **Left Click (Bar Icon)** | Toggle notification panel |
| **Left Click (Card)** | Run its preserved action or focus the best matching Hyprland window, then dismiss it on success |
| **Left Click (`×` Button)** | Dismiss individual notification from archive |
| `↓` or `j` | Move selection down |
| `↑` or `k` | Move selection up |
| `Enter` or `Space` | Activate the selected notification |
| `x` | Dismiss selected notification |
| `Escape` | Close panel |
| `Tab` / `Shift + Tab` | Switch to adjacent bar panel (e.g. Audio, Power) |

### Hyprland Hotkey

Add a keybinding in `~/.config/hypr/bindings.lua`:

```lua
-- Toggle notification center
o.bind("SUPER + N", "Notifications", "omarchy-shell shell toggle ritechoice23.omarchy.notification")
```

---

## IPC Commands

Control the notification center from scripts, keybinds, or the terminal:

```bash
# Toggle panel visibility
omarchy-shell shell toggle ritechoice23.omarchy.notification

# Summon (open) panel
omarchy-shell shell summon ritechoice23.omarchy.notification

# Hide (close) panel
omarchy-shell shell hide ritechoice23.omarchy.notification
```

---

## Configuration

Settings are declared via the Omarchy manifest schema and can be modified through the **Omarchy Bar Settings GUI** (`omarchy launch bar-settings`) or via the CLI:

| Setting | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `historyLimit` | `integer` | `200` | Maximum number of notifications to keep in archive (10–500) |
| `showBadge` | `boolean` | `true` | Show unread count badge on the bar icon |

### Changing Settings via CLI

```bash
# Set history archive limit to 100
omarchy bar set ritechoice23.omarchy.notification historyLimit 100 --json

# Hide the unread count badge on the bar
omarchy bar set ritechoice23.omarchy.notification showBadge false --json
```

---

## How It Works

Omarchy runs the system Freedesktop notification daemon and writes notifications to:

```text
~/.local/state/omarchy/notifications/
```

This plugin reads these records and maintains an archive under:

```text
~/.local/state/ritechoice23-omarchy-notification/
├── history/       # Mirrored notification JSON records
├── images/        # Cached notification avatars and icons
├── dismissed/     # List of dismissed notification IDs
└── last-seen      # Timestamp tracking unread state
```

- File events from Omarchy's notification directory are debounced into archive refreshes, with a 30-second polling fallback.
- When the panel opens, it marks only the newest notification it successfully displayed as seen.
- Archive writes, dismissals, pruning, clears, and seen watermarks are atomic and locked across per-monitor widget instances.

### Activation limits

Omarchy-specific notifications can preserve an `omarchy-exec` action, allowing the exact destination to reopen after archival. Standard Freedesktop default actions are live DBus callbacks and cannot be reconstructed after the sending application or notification-server generation is gone. For those historical entries, the plugin focuses the strongest matching existing app or web-app window and never launches an unavailable application.

---

## Testing & Validation

```bash
# Validate manifest against Omarchy standard
omarchy plugin validate .

# Run data and activation tests
bash tests/test-data.sh
bash tests/test-activation.sh

# Generate test notifications
bash scripts/demo-notifications
```

---

## Update

```bash
omarchy plugin update ritechoice23.omarchy.notification
```

---

## Removal

```bash
# Disable and remove plugin
omarchy plugin remove ritechoice23.omarchy.notification

# (Optional) Delete saved notification history archive
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/ritechoice23-omarchy-notification"
```

---

## License

[MIT](LICENSE)
