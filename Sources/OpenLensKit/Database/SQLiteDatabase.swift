import Foundation
import SQLite3

/// A tiny, dependency-free wrapper around the system SQLite3 library.
///
/// Aperture stores its catalog in several SQLite databases inside the
/// `Database/apdb/` folder of the library package. We only need read access
/// for browsing, plus narrow, well-controlled writes for ratings/flags.
///
/// This wrapper intentionally exposes a minimal surface. It is not a general
/// ORM — it is just enough to run parameterised queries and read rows.
public final class SQLiteDatabase {

    public enum DBError: Error, CustomStringConvertible {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)

        public var description: String {
            switch self {
            case .openFailed(let m): return "SQLite open failed: \(m)"
            case .prepareFailed(let m): return "SQLite prepare failed: \(m)"
            case .stepFailed(let m): return "SQLite step failed: \(m)"
            }
        }
    }

    /// A single column value read from a row.
    public enum Value {
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
        case null

        public var intValue: Int? {
            if case .integer(let v) = self { return Int(v) }
            return nil
        }
        public var doubleValue: Double? {
            switch self {
            case .real(let v): return v
            case .integer(let v): return Double(v)
            default: return nil
            }
        }
        public var stringValue: String? {
            if case .text(let v) = self { return v }
            return nil
        }
        public var dataValue: Data? {
            if case .blob(let v) = self { return v }
            return nil
        }
    }

    public typealias Row = [String: Value]

    private var handle: OpaquePointer?
    public let path: String

    /// Opens the database. Pass `readOnly: true` for browsing to avoid any
    /// risk of mutating the catalog.
    public init(path: String, readOnly: Bool = true) throws {
        self.path = path
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE)
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DBError.openFailed(msg)
        }
    }

    deinit {
        if handle != nil { sqlite3_close(handle) }
    }

    /// Runs a query and returns all rows. `params` are bound positionally.
    @discardableResult
    public func query(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }

        try bind(params, to: stmt)

        var rows: [Row] = []
        let columnCount = sqlite3_column_count(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var row: Row = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    row[name] = readColumn(stmt, i)
                }
                rows.append(row)
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DBError.stepFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
        return rows
    }

    /// Executes a statement that returns no rows (UPDATE/INSERT/DELETE/PRAGMA).
    public func execute(_ sql: String, _ params: [Value] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(params, to: stmt)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DBError.stepFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    // MARK: - Private

    private func bind(_ params: [Value], to stmt: OpaquePointer?) throws {
        // SQLite bind indices are 1-based.
        for (idx, value) in params.enumerated() {
            let i = Int32(idx + 1)
            switch value {
            case .integer(let v): sqlite3_bind_int64(stmt, i, v)
            case .real(let v): sqlite3_bind_double(stmt, i, v)
            case .text(let v): sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case .blob(let d):
                _ = d.withUnsafeBytes { raw in
                    sqlite3_bind_blob(stmt, i, raw.baseAddress, Int32(d.count), SQLITE_TRANSIENT)
                }
            case .null: sqlite3_bind_null(stmt, i)
            }
        }
    }

    private func readColumn(_ stmt: OpaquePointer?, _ i: Int32) -> Value {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, i))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(stmt, i)))
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(stmt, i) {
                let count = Int(sqlite3_column_bytes(stmt, i))
                return .blob(Data(bytes: bytes, count: count))
            }
            return .blob(Data())
        default:
            return .null
        }
    }
}

// SQLite needs SQLITE_TRANSIENT so it copies bound text/blob buffers.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
