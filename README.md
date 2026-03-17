# IntentCapture

A macOS menu bar app that tracks your activity across all applications using the Accessibility API and logs it to a local SQLite database.

## What it does

- Runs as a menu bar utility (no Dock icon)
- Polls every 5 seconds and captures the full active window context via the macOS Accessibility API:
  - Window title
  - Focused UI element (role, title/description, value)
  - Selected text
  - Document file path (if exposed by the app)
  - Browser URL (Safari, Chrome, Arc, Firefox, Edge, Brave, etc.)
- Skips password fields (AXSecureTextField) automatically
- Deduplicates entries — only logs when the active app, window, or focused element changes
- Stores activity in a local SQLite database at `~/Library/Application Support/IntentCapture/activity.db`
- Automatically purges records older than 15 days

## Requirements

- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
brew install xcodegen   # if not already installed
xcodegen generate
open IntentCapture.xcodeproj
# Build & Run (Cmd+R)
```

## Setup

On first launch:

1. Click the eye icon in the menu bar
2. Click **Start Tracking**
3. macOS will prompt you to grant Accessibility permission in **System Settings > Privacy & Security > Accessibility**
4. Toggle the switch for IntentCapture, then click **Start Tracking** again

See [DESIGN.md](DESIGN.md) for database schema, example queries, and project structure.
