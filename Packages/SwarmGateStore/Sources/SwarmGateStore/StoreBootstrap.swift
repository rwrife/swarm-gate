import GRDB

/// Opens an empty local SQLite database; ledger migrations arrive in M3.
public enum StoreBootstrap {
    public static func open(at path: String) throws -> DatabaseQueue {
        try DatabaseQueue(path: path)
    }
}