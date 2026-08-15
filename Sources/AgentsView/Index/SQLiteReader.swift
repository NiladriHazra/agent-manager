import Foundation
import SQLite3

/// Minimal read-only SQLite access for databases owned by other tools.
///
/// Opened with `mode=ro` and a short busy timeout so a live OpenCode session
/// holding a write lock degrades to a stale value instead of blocking the UI.
/// Nothing here ever writes.
enum SQLiteReader {
    static func queryRow(path: String, sql: String) -> [String]? {
        var db: OpaquePointer?
        let uri = "file:\(path)?mode=ro&immutable=0"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (0..<sqlite3_column_count(statement)).map { column in
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        }
    }
}
