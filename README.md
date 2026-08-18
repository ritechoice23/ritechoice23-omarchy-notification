# RiteChoice23 Notification

A clean notification center for the Omarchy top bar.

RiteChoice23 Notification adds a bell icon to the right side of Omarchy's
Quickshell bar. Clicking it opens a native Omarchy panel containing recent
notifications in a clean, scrollable list.

## Features

- Native Omarchy bar widget
- Bell icon with unread-count badge
- Popup anchored to the Omarchy bar
- Recent notifications in newest-first order
- App icon or fallback initial
- App/source name, title, body and relative time
- Detects common browser notification sources such as WhatsApp Web
- Removes noisy browser-origin lines such as `web.whatsapp.com`
- Hover-to-dismiss individual entries
- Clear-all action
- Empty state
- Automatically follows the current Omarchy theme, font and spacing
- Keeps an independent archive of up to 200 recent notifications
- Preserves file-backed notification icons/images in its own state directory
- Does not replace or patch Omarchy's built-in notification daemon

## Requirements

- Omarchy with the Quickshell plugin system
- `jq`

## Install from GitHub

After this folder has been published as a public GitHub repository:

```bash
omarchy plugin add https://github.com/ritechoice23/ritechoice23-omarchy-notification.git --enable --yes
```

Then place the bell before the standard battery/power widget:

```bash
omarchy bar move ritechoice23.omarchy.notification --before omarchy.power
```

If `omarchy.power` is not on your bar:

```bash
omarchy bar move ritechoice23.omarchy.notification right
```

## Update

```bash
omarchy plugin update ritechoice23.omarchy.notification
```

## Remove

```bash
omarchy plugin remove ritechoice23.omarchy.notification
```

The plugin's saved notification archive is intentionally not removed with the
plugin. To remove that too:

```bash
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/ritechoice23-omarchy-notification"
```

## Local install before publishing

From this repository directory:

```bash
bash install-local.sh
```

## Demo notifications

```bash
bash scripts/demo-notifications
```

Then wait for the normal notification to appear and click the bell icon.

## Validate

Before publishing or releasing:

```bash
omarchy plugin validate .
```

The included data-layer test can also be run anywhere with Bash and `jq`:

```bash
bash tests/test-data.sh
```

## Publish to GitHub

Create an empty public repository named:

```text
ritechoice23-omarchy-notification
```

Then run from this directory:

```bash
git init -b main
git add .
git commit -m "Initial release of RiteChoice23 Notification"
git remote add origin https://github.com/ritechoice23/ritechoice23-omarchy-notification.git
git push -u origin main
```

After that, anyone can install it with:

```bash
omarchy plugin add https://github.com/ritechoice23/ritechoice23-omarchy-notification.git --enable --yes
omarchy bar move ritechoice23.omarchy.notification --before omarchy.power
```

## How it works

Omarchy remains the Freedesktop notification daemon. RiteChoice23 Notification
does not start a second notification daemon.

The widget reads the JSON notification state Omarchy already writes under:

```text
~/.local/state/omarchy/notifications/
```

It mirrors those records into:

```text
~/.local/state/ritechoice23-omarchy-notification/
├── history/
├── images/
├── dismissed/
└── last-seen
```

This independent archive lets RiteChoice23 keep up to 200 recent entries even
though Omarchy itself may retain a shorter built-in history.

The widget polls while loaded on the bar, so notifications are archived even
when the panel is closed.

## Repository layout

```text
ritechoice23-omarchy-notification/
├── manifest.json
├── Panel.qml
├── scripts/
│   ├── notification-data
│   ├── mark-seen
│   ├── dismiss-one
│   ├── clear-all
│   └── demo-notifications
├── tests/
│   ├── fixtures/
│   │   └── whatsapp-web.json
│   └── test-data.sh
├── install-local.sh
├── uninstall-local.sh
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Security

Omarchy shell plugins run as unsandboxed code as your user. Review any plugin
before installing it from GitHub.

This plugin only reads notification state, maintains its own local archive,
and invokes Omarchy's notification-clear IPC when you use Clear All.

## License

MIT
