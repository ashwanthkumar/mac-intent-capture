# Design

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

Database location: `~/Library/Application Support/IntentCapture/activity.db`

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
│   ├── ActivityLogView.swift            # Activity log viewer window
│   ├── DatabaseManager.swift            # SQLite C API wrapper
│   └── Models.swift                     # ActivityRecord and AXNode data models
└── Resources/
    ├── Info.plist                        # LSUIElement=true for menu-bar-only mode
    └── IntentCapture.entitlements        # App Sandbox disabled for AX access
```
