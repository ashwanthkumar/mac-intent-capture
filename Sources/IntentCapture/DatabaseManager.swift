import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager {
    private var db: OpaquePointer?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        let url = Self.databaseURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if sqlite3_open(url.path, &db) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("Error opening database: \(errmsg)")
            return
        }

        exec("PRAGMA journal_mode=WAL")
        createTable()
        migrateIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Location

    static func databaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("IntentCapture", isDirectory: true)
            .appendingPathComponent("activity.db")
    }

    // MARK: - Schema

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS activity_log (
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
            url TEXT NOT NULL DEFAULT '',
            window_hierarchy TEXT NOT NULL DEFAULT ''
        );
        """
        exec(sql)
        exec("CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON activity_log(timestamp)")
    }

    private func migrateIfNeeded() {
        let existing = existingColumns(table: "activity_log")
        let newColumns = [
            "focused_role", "focused_title", "focused_value",
            "selected_text", "document_path", "window_hierarchy"
        ]
        for col in newColumns where !existing.contains(col) {
            exec("ALTER TABLE activity_log ADD COLUMN \(col) TEXT NOT NULL DEFAULT ''")
        }
    }

    private func existingColumns(table: String) -> Set<String> {
        var columns = Set<String>()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            return columns
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    // MARK: - Insert

    func insertRecord(_ record: ActivityRecord) {
        let sql = """
        INSERT INTO activity_log
            (timestamp, app_name, bundle_id, window_title, focused_role, focused_title,
             focused_value, selected_text, document_path, url, window_hierarchy)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let iso = dateFormatter.string(from: record.timestamp)
        sqlite3_bind_text(stmt, 1, iso, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.appName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.bundleId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.windowTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, record.focusedRole, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, record.focusedTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, record.focusedValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, record.selectedText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, record.documentPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 10, record.url, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 11, record.windowHierarchy, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("Insert failed: \(errmsg)")
        }
    }

    // MARK: - Deduplication

    func shouldInsert(appName: String, bundleId: String, windowTitle: String,
                      focusedRole: String, focusedTitle: String) -> Bool {
        let sql = """
        SELECT app_name, bundle_id, window_title, focused_role, focused_title
        FROM activity_log ORDER BY id DESC LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return true }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let lastApp = String(cString: sqlite3_column_text(stmt, 0))
            let lastBundle = String(cString: sqlite3_column_text(stmt, 1))
            let lastTitle = String(cString: sqlite3_column_text(stmt, 2))
            let lastRole = String(cString: sqlite3_column_text(stmt, 3))
            let lastFocusedTitle = String(cString: sqlite3_column_text(stmt, 4))
            return !(lastApp == appName && lastBundle == bundleId &&
                     lastTitle == windowTitle && lastRole == focusedRole &&
                     lastFocusedTitle == focusedTitle)
        }
        return true
    }

    // MARK: - Fetch Records

    func fetchRecords(limit: Int = 500, searchQuery: String = "") -> [ActivityRecord] {
        var records: [ActivityRecord] = []
        let hasSearch = !searchQuery.isEmpty

        let sql: String
        if hasSearch {
            sql = """
            SELECT id, timestamp, app_name, bundle_id, window_title, focused_role,
                   focused_title, focused_value, selected_text, document_path, url, window_hierarchy
            FROM activity_log
            WHERE app_name LIKE ? OR window_title LIKE ? OR focused_title LIKE ?
                  OR focused_value LIKE ? OR url LIKE ? OR document_path LIKE ?
            ORDER BY id DESC LIMIT ?
            """
        } else {
            sql = """
            SELECT id, timestamp, app_name, bundle_id, window_title, focused_role,
                   focused_title, focused_value, selected_text, document_path, url, window_hierarchy
            FROM activity_log
            ORDER BY id DESC LIMIT ?
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return records }
        defer { sqlite3_finalize(stmt) }

        if hasSearch {
            let pattern = "%\(searchQuery)%"
            for i: Int32 in 1...6 {
                sqlite3_bind_text(stmt, i, pattern, -1, SQLITE_TRANSIENT)
            }
            sqlite3_bind_int(stmt, 7, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let record = ActivityRecord(
                id: sqlite3_column_int64(stmt, 0),
                timestamp: dateFormatter.date(from: columnString(stmt, 1)) ?? Date(),
                appName: columnString(stmt, 2),
                bundleId: columnString(stmt, 3),
                windowTitle: columnString(stmt, 4),
                focusedRole: columnString(stmt, 5),
                focusedTitle: columnString(stmt, 6),
                focusedValue: columnString(stmt, 7),
                selectedText: columnString(stmt, 8),
                documentPath: columnString(stmt, 9),
                url: columnString(stmt, 10),
                windowHierarchy: columnString(stmt, 11)
            )
            records.append(record)
        }
        return records
    }

    func recordCount() -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM activity_log", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - TTL Purge

    func purgeOldRecords(olderThanDays days: Int = 15) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        let iso = dateFormatter.string(from: cutoff)
        let sql = "DELETE FROM activity_log WHERE timestamp < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, iso, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_DONE {
            let deleted = sqlite3_changes(db)
            if deleted > 0 {
                print("Purged \(deleted) records older than \(days) days")
            }
        }
    }

    // MARK: - Helpers

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        if let text = sqlite3_column_text(stmt, index) {
            return String(cString: text)
        }
        return ""
    }

    private func exec(_ sql: String) {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            if let errmsg = errmsg {
                print("SQL error: \(String(cString: errmsg))")
                sqlite3_free(errmsg)
            }
        }
    }
}
