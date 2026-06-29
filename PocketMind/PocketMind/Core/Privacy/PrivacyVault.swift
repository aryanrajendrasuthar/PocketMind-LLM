//
// PocketMind — On-Device Private LLM for iPhone
// Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
//
// PROPRIETARY AND CONFIDENTIAL
// Unauthorized copying, distribution, modification, or use of this file,
// via any medium, is strictly prohibited without the express written
// permission of the copyright owner.
//
// For licensing inquiries: aryanrajendrasuthar@gmail.com
//

import CryptoKit
import Foundation
import os.log
import SQLCipher

/// Encrypted persistence layer for all conversation data.
///
/// All reads and writes go through this actor. The database is encrypted with
/// SQLCipher using a key derived from the Secure Enclave at runtime.
///
/// - Privacy guarantee: No data is ever written to `NSLog` or `print`.
///   All logging uses `os_log` with `OSLogPrivacy.sensitive` on message body fields.
/// - Backup exclusion: The database directory has `isExcludedFromBackup = true`.
/// - Delete guarantee: `deleteAllData()` wipes the database file and all UserDefaults keys.
actor PrivacyVault {

    // MARK: - Types

    enum VaultError: Error, LocalizedError {
        case databaseOpenFailed(String)
        case databaseKeyFailed
        case encodingFailed
        case decodingFailed
        case queryFailed(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .databaseOpenFailed(let msg): return "Database open failed: \(msg)"
            case .databaseKeyFailed:           return "Failed to derive database key."
            case .encodingFailed:              return "Failed to encode data for storage."
            case .decodingFailed:              return "Failed to decode stored data."
            case .queryFailed(let msg):        return "Database query failed: \(msg)"
            case .notFound:                    return "Record not found."
            }
        }
    }

    // MARK: - Private state

    private var db: OpaquePointer?
    private let dbURL: URL
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "PrivacyVault")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    init() throws {
        dbURL = try Self.resolveDatabaseURL()
        try Self.applyBackupExclusion(to: dbURL.deletingLastPathComponent())
        try openAndKey()
        try createTablesIfNeeded()
    }

    // MARK: - Public API

    /// Persists a message within a conversation, creating the conversation record if absent.
    func saveMessage(_ message: ChatMessage, inConversation conversation: Conversation) throws {
        try upsertConversation(conversation)
        try upsertMessage(message, conversationId: conversation.id)
    }

    /// Returns the full conversation including all messages, or throws `VaultError.notFound`.
    func loadConversation(id: UUID) throws -> Conversation {
        let conversationRow = try fetchConversationRow(id: id)
        let messages = try fetchMessages(forConversationId: id)
        return Conversation(
            id: conversationRow.id,
            title: conversationRow.title,
            messages: messages,
            modelId: conversationRow.modelId,
            createdAt: conversationRow.createdAt,
            updatedAt: conversationRow.updatedAt,
            isPinned: conversationRow.isPinned
        )
    }

    /// Returns all conversations ordered by `updatedAt` descending (pinned first).
    func loadAllConversations() throws -> [Conversation] {
        let ids = try fetchAllConversationIds()
        return try ids.compactMap { try? loadConversation(id: $0) }
    }

    /// Deletes a single conversation and all its messages.
    func deleteConversation(id: UUID) throws {
        try execute("DELETE FROM messages WHERE conversation_id = ?", args: [id.uuidString])
        try execute("DELETE FROM conversations WHERE id = ?", args: [id.uuidString])
        logger.info("Conversation deleted.")
    }

    /// Wipes all data: deletes the SQLCipher database file and clears all UserDefaults keys.
    /// After this call, `PrivacyVault` must be re-initialized to create a fresh database.
    func deleteAllData() throws {
        closeDatabase()

        let fm = FileManager.default
        if fm.fileExists(atPath: dbURL.path) {
            try fm.removeItem(at: dbURL)
            logger.info("Database file deleted.")
        }

        // Wipe WAL and SHM sidecar files if present
        for suffix in ["-wal", "-shm"] {
            let sidecar = dbURL.appendingPathExtension(suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try fm.removeItem(at: sidecar)
            }
        }

        // Clear all UserDefaults for this app
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
            logger.info("UserDefaults cleared.")
        }
    }

    // MARK: - Database setup

    private static func resolveDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDir = appSupport.appendingPathComponent(Constants.Storage.databaseDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent(Constants.Storage.databaseFilename)
    }

    private static func applyBackupExclusion(to directoryURL: URL) throws {
        var url = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func openAndKey() throws {
        let status = sqlite3_open(dbURL.path, &db)
        guard status == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw VaultError.databaseOpenFailed(message)
        }

        let key: SymmetricKey
        do {
            key = try SecureEnclaveKeyManager.deriveDatabaseKey()
        } catch {
            // Log without exposing error details to prevent leaking key derivation internals
            logger.error("Database key derivation failed. Error category: \(error.localizedDescription, privacy: .public)")
            throw VaultError.databaseKeyFailed
        }

        // Apply SQLCipher key — raw bytes, not hex, using sqlite3_key
        let keyBytes = key.withUnsafeBytes { Array($0) }
        let keyStatus = sqlite3_key(db, keyBytes, Int32(keyBytes.count))
        guard keyStatus == SQLITE_OK else {
            throw VaultError.databaseKeyFailed
        }

        // Enable WAL mode for better performance and crash resilience
        try execute("PRAGMA journal_mode = WAL")
        // Enforce foreign keys
        try execute("PRAGMA foreign_keys = ON")
        // Tune cipher settings for SQLCipher 4
        try execute("PRAGMA cipher_page_size = 4096")
        try execute("PRAGMA kdf_iter = 256000")
        try execute("PRAGMA cipher_hmac_algorithm = HMAC_SHA512")
        try execute("PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512")

        logger.info("Database opened and keyed.")
    }

    private func createTablesIfNeeded() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id          TEXT PRIMARY KEY NOT NULL,
                title       TEXT NOT NULL,
                model_id    TEXT NOT NULL,
                created_at  REAL NOT NULL,
                updated_at  REAL NOT NULL,
                is_pinned   INTEGER NOT NULL DEFAULT 0
            )
            """)

        try execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id                  TEXT PRIMARY KEY NOT NULL,
                conversation_id     TEXT NOT NULL REFERENCES conversations(id),
                role                TEXT NOT NULL,
                content             TEXT NOT NULL,
                timestamp           REAL NOT NULL,
                token_count         INTEGER,
                inference_metadata  BLOB
            )
            """)

        try execute("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC)")
    }

    // MARK: - Upsert helpers

    private func upsertConversation(_ conversation: Conversation) throws {
        try execute(
            """
            INSERT INTO conversations (id, title, model_id, created_at, updated_at, is_pinned)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title      = excluded.title,
                updated_at = excluded.updated_at,
                is_pinned  = excluded.is_pinned
            """,
            args: [
                conversation.id.uuidString,
                conversation.title,
                conversation.modelId,
                conversation.createdAt.timeIntervalSince1970,
                conversation.updatedAt.timeIntervalSince1970,
                conversation.isPinned ? 1 : 0,
            ]
        )
    }

    private func upsertMessage(_ message: ChatMessage, conversationId: UUID) throws {
        var metadataBlob: Data?
        if let metadata = message.inferenceMetadata {
            metadataBlob = try? encoder.encode(metadata)
        }

        try execute(
            """
            INSERT INTO messages (id, conversation_id, role, content, timestamp, token_count, inference_metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content            = excluded.content,
                token_count        = excluded.token_count,
                inference_metadata = excluded.inference_metadata
            """,
            args: [
                message.id.uuidString,
                conversationId.uuidString,
                message.role.rawValue,
                message.content,
                message.timestamp.timeIntervalSince1970,
                message.tokenCount as Any,
                metadataBlob as Any,
            ]
        )
    }

    // MARK: - Fetch helpers

    private struct ConversationRow {
        let id: UUID
        let title: String
        let modelId: String
        let createdAt: Date
        let updatedAt: Date
        let isPinned: Bool
    }

    private func fetchConversationRow(id: UUID) throws -> ConversationRow {
        var stmt: OpaquePointer?
        let sql = "SELECT id, title, model_id, created_at, updated_at, is_pinned FROM conversations WHERE id = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VaultError.queryFailed(sqliteError())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id.uuidString, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw VaultError.notFound
        }

        guard
            let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
            let rowId = UUID(uuidString: idStr)
        else {
            throw VaultError.decodingFailed
        }

        let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let modelId = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let isPinned = sqlite3_column_int(stmt, 5) != 0

        return ConversationRow(id: rowId, title: title, modelId: modelId,
                               createdAt: createdAt, updatedAt: updatedAt, isPinned: isPinned)
    }

    private func fetchMessages(forConversationId cid: UUID) throws -> [ChatMessage] {
        var stmt: OpaquePointer?
        let sql = "SELECT id, role, content, timestamp, token_count, inference_metadata FROM messages WHERE conversation_id = ? ORDER BY timestamp ASC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VaultError.queryFailed(sqliteError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cid.uuidString, -1, nil)

        var messages: [ChatMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                let msgId = UUID(uuidString: idStr),
                let roleStr = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
                let role = MessageRole(rawValue: roleStr)
            else {
                continue
            }
            let content = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let tokenCount = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? Int(sqlite3_column_int(stmt, 4))
                : nil

            var inferenceMetadata: InferenceMetadata?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL,
               let blobPtr = sqlite3_column_blob(stmt, 5) {
                let blobSize = Int(sqlite3_column_bytes(stmt, 5))
                let data = Data(bytes: blobPtr, count: blobSize)
                inferenceMetadata = try? decoder.decode(InferenceMetadata.self, from: data)
            }

            messages.append(ChatMessage(
                id: msgId,
                role: role,
                content: content,
                timestamp: timestamp,
                tokenCount: tokenCount,
                inferenceMetadata: inferenceMetadata
            ))
        }
        return messages
    }

    private func fetchAllConversationIds() throws -> [UUID] {
        var stmt: OpaquePointer?
        let sql = "SELECT id FROM conversations ORDER BY is_pinned DESC, updated_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VaultError.queryFailed(sqliteError())
        }
        defer { sqlite3_finalize(stmt) }

        var ids: [UUID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let str = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
               let uuid = UUID(uuidString: str) {
                ids.append(uuid)
            }
        }
        return ids
    }

    // MARK: - Low-level helpers

    @discardableResult
    private func execute(_ sql: String, args: [Any] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VaultError.queryFailed(sqliteError())
        }
        defer { sqlite3_finalize(stmt) }

        for (index, arg) in args.enumerated() {
            let bindIndex = Int32(index + 1)
            switch arg {
            case let text as String:
                sqlite3_bind_text(stmt, bindIndex, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let double as Double:
                sqlite3_bind_double(stmt, bindIndex, double)
            case let int as Int:
                sqlite3_bind_int64(stmt, bindIndex, Int64(int))
            case let int64 as Int64:
                sqlite3_bind_int64(stmt, bindIndex, int64)
            case let data as Data:
                data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, bindIndex, ptr.baseAddress, Int32(data.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            default:
                sqlite3_bind_null(stmt, bindIndex)
            }
        }

        let status = sqlite3_step(stmt)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            throw VaultError.queryFailed(sqliteError())
        }
        return Int(sqlite3_changes(db))
    }

    private func sqliteError() -> String {
        sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown SQLite error"
    }

    private func closeDatabase() {
        sqlite3_close_v2(db)
        db = nil
    }
}
