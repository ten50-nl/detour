import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let description: String
}

enum SQLiteReader {
    static func strings(dbPath: URL, sql: String, bind: Int64) throws -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw SQLiteError(description: "open failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError(description: "prepare failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, bind)
        var result: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                result.append(String(cString: text))
            }
        }
        return result
    }
}
