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

## Database Schema

```sql
CREATE TABLE activity_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    app_name TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    window_title TEXT NOT NULL,
    focused_role TEXT NOT NULL DEFAULT '',
    focused_title TEXT NOT NULL DEFAULT '',
    focused_value TEXT NOT NULL DEFAULT '',
    selected_text TEXT NOT NULL DEFAULT '',
    document_path TEXT NOT NULL DEFAULT '',
    url TEXT NOT NULL DEFAULT ''
);
```

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

## Querying the database

```bash
sqlite3 ~/Library/Application\ Support/IntentCapture/activity.db

-- Recent activity with full context
SELECT timestamp, app_name, window_title, focused_role, focused_title, focused_value
FROM activity_log ORDER BY id DESC LIMIT 20;

-- Time spent per app today
SELECT app_name, COUNT(*) as switches
FROM activity_log
WHERE timestamp >= date('now', 'start of day')
GROUP BY app_name
ORDER BY switches DESC;

-- What files were you editing?
SELECT timestamp, app_name, document_path, window_title
FROM activity_log
WHERE document_path != ''
ORDER BY id DESC LIMIT 20;

-- Browser history
SELECT timestamp, url, window_title
FROM activity_log
WHERE url != ''
ORDER BY id DESC LIMIT 20;
```

## Project Structure

```
├── project.yml                          # XcodeGen project spec
├── Sources/IntentCapture/
│   ├── App.swift                        # SwiftUI entry point, MenuBarExtra UI
│   ├── AccessibilityTracker.swift       # AX API polling engine
│   ├── DatabaseManager.swift            # SQLite C API wrapper
│   └── Models.swift                     # ActivityRecord data model
└── Resources/
    ├── Info.plist                        # LSUIElement=true for menu-bar-only mode
    └── IntentCapture.entitlements        # App Sandbox disabled for AX access
```
