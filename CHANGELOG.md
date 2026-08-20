# Changelog

## 1.1.0 - 2026-08-20

- Replaced collapsed app groups with a chronological, virtualized card list
- Added Today, Yesterday, and date sections while keeping every retained item visible
- Added macOS-inspired card hierarchy that follows Omarchy colors, spacing, and corner radius
- Added exact-address Hyprland activation with persisted-action, PWA, desktop-entry, and app-class resolution
- Successful activation now dismisses only the opened notification; failed activation remains visible
- Added serialized dismissals, coalesced refreshes, file watching, atomic archive writes, and cross-instance locking
- Made unread watermarks monotonic and tied them to notifications actually displayed
- Added activation, concurrency, pruning, malformed-record, image-cache, and input-safety tests

## 1.0.0 - 2026-08-18

- Initial public release
- Native Omarchy bell widget
- Unread count badge
- Native notification-center popup
- Independent 200-entry notification archive
- Preserves notification icon/image files
- WhatsApp Web source detection and body cleanup
- Individual dismiss
- Clear all
- Local install/uninstall helpers
- Demo notification generator
- Data-layer test fixture and test script
