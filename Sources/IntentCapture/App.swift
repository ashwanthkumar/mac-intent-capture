import SwiftUI

@main
struct IntentCaptureApp: App {
    @StateObject private var tracker: AccessibilityTracker
    @Environment(\.openWindow) private var openWindow

    private let dbManager: DatabaseManager

    init() {
        let db = DatabaseManager()
        db.purgeOldRecords()
        self.dbManager = db
        _tracker = StateObject(wrappedValue: AccessibilityTracker(dbManager: db))
    }

    var body: some Scene {
        MenuBarExtra("IntentCapture", systemImage: "eye.circle") {
            VStack(alignment: .leading, spacing: 4) {
                if tracker.isTracking {
                    Label("Tracking Active", systemImage: "circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)

                    Divider()

                    if !tracker.lastAppName.isEmpty {
                        Text("App: \(tracker.lastAppName)")
                            .font(.system(.body, design: .monospaced))
                    }
                    if !tracker.lastWindowTitle.isEmpty {
                        Text("Window: \(tracker.lastWindowTitle)")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                    }
                    if !tracker.lastFocusedElement.isEmpty {
                        Text("Focus: \(tracker.lastFocusedElement)")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                    }

                    Divider()

                    Button("Stop Tracking") {
                        tracker.stopTracking()
                    }
                    .keyboardShortcut("s")
                } else {
                    Label("Tracking Off", systemImage: "circle")
                        .font(.headline)

                    Divider()

                    Button("Start Tracking") {
                        tracker.startTracking()
                    }
                    .keyboardShortcut("s")
                }

                Divider()

                Button("View Activity Log") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "activity-log")
                }
                .keyboardShortcut("l")

                Button("Open Database Folder") {
                    let url = DatabaseManager.databaseURL().deletingLastPathComponent()
                    NSWorkspace.shared.open(url)
                }

                Button("Quit IntentCapture") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(4)
        }

        Window("Activity Log", id: "activity-log") {
            ActivityLogView(dbManager: dbManager)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
