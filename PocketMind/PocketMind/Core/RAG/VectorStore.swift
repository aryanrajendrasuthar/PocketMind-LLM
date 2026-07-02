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

import Foundation
import SQLite3
import os.log

// MARK: - Record types

struct ChunkRecord: Sendable {
    let index: Int
    let content: String
    let embedding: [Float]
}

struct DocumentRecord: Identifiable, Sendable {
    let id: String
    let filename: String
    let indexedAt: Date
    let chunkCount: Int
}

struct SearchResult: Sendable {
    let content: String
    let score: Float
    let docId: String
}

// MARK: - VectorStore

/// SQLite-backed store for RAG document chunks and their embeddings.
///
/// Uses the same `sqlite3` system library as `PrivacyVault` — no additional
/// dependencies. Brute-force cosine search is fast enough for up to ~5 000 chunks
/// (sub-millisecond on A-series chips for 300-dim embeddings).
// VectorStore is a plain class, not an actor. RAGEngine (its owner) is an actor
// and serializes all access — no second isolation domain needed.
final class VectorStore: @unchecked Sendable {

    enum StoreError: Error {
        case openFailed(String)
        case queryFailed(String)
    }

    private var db: OpaquePointer?
    private let embDimension: Int
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "VectorStore")

    init(embeddingDimension: Int) throws {
        self.embDimension = embeddingDimension

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ragDir = appSupport.appendingPathComponent("rag", isDirectory: true)
        try FileManager.default.createDirectory(at: ragDir, withIntermediateDirectories: true)

        // Exclude from iCloud backup — embeddings can be rebuilt from source documents.
        var dirURL = ragDir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dirURL.setResourceValues(resourceValues)

        let dbPath = ragDir.appendingPathComponent("vectors.db").path
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw StoreError.openFailed(sqliteError())
        }
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA foreign_keys = ON")
        try createSchema()
        logger.info("VectorStore opened.")
    }

    // MARK: - Public API

    /// Replace all chunks for a document with freshly computed embeddings.
    func upsertDocument(id: String, filename: String, chunks: [ChunkRecord]) throws {
        try exec(
            """
            INSERT INTO rag_documents (id, filename, indexed_at, chunk_count)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                filename    = excluded.filename,
                indexed_at  = excluded.indexed_at,
                chunk_count = excluded.chunk_count
            """,
            args: [id, filename, Date().timeIntervalSince1970, chunks.count]
        )
        try exec("DELETE FROM rag_chunks WHERE doc_id = ?", args: [id])

        for chunk in chunks {
            let blob = float32Blob(chunk.embedding)
            try exec(
                "INSERT INTO rag_chunks (doc_id, chunk_index, content, embedding) VALUES (?, ?, ?, ?)",
                args: [id, chunk.index, chunk.content, blob]
            )
        }
        logger.info("Upserted document '\(filename)' — \(chunks.count) chunks.")
    }

    /// Return the top-k chunks most similar to `queryEmbedding`, filtered by `threshold`.
    func search(queryEmbedding: [Float], topK: Int, threshold: Float) throws -> [SearchResult] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "SELECT doc_id, content, embedding FROM rag_chunks"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(sqliteError())
        }

        let expectedBytes = embDimension * MemoryLayout<Float>.size
        var scored: [(score: Float, content: String, docId: String)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let blobPtr  = sqlite3_column_blob(stmt, 2),
                sqlite3_column_bytes(stmt, 2) == expectedBytes
            else { continue }

            let chunkEmb = blobToFloat32(blobPtr, count: embDimension)
            let score = dotProduct(queryEmbedding, chunkEmb)
            guard score >= threshold else { continue }

            let content = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let docId   = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            scored.append((score, content, docId))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { SearchResult(content: $0.content, score: $0.score, docId: $0.docId) }
    }

    /// List all indexed documents, newest first.
    func allDocuments() throws -> [DocumentRecord] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "SELECT id, filename, indexed_at, chunk_count FROM rag_documents ORDER BY indexed_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(sqliteError())
        }

        var docs: [DocumentRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id         = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let filename   = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let indexedAt  = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let chunkCount = Int(sqlite3_column_int(stmt, 3))
            docs.append(DocumentRecord(id: id, filename: filename, indexedAt: indexedAt, chunkCount: chunkCount))
        }
        return docs
    }

    /// Delete a document and all its chunks (CASCADE handles the chunks table).
    func deleteDocument(id: String) throws {
        try exec("DELETE FROM rag_documents WHERE id = ?", args: [id])
        logger.info("Deleted document \(id).")
    }

    // MARK: - Schema

    private func createSchema() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS rag_documents (
                id          TEXT PRIMARY KEY NOT NULL,
                filename    TEXT NOT NULL,
                indexed_at  REAL NOT NULL,
                chunk_count INTEGER NOT NULL DEFAULT 0
            )
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS rag_chunks (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                doc_id      TEXT NOT NULL REFERENCES rag_documents(id) ON DELETE CASCADE,
                chunk_index INTEGER NOT NULL,
                content     TEXT NOT NULL,
                embedding   BLOB
            )
            """)
        try exec("CREATE INDEX IF NOT EXISTS idx_chunks_doc ON rag_chunks(doc_id)")
    }

    // MARK: - Binary helpers

    private func float32Blob(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func blobToFloat32(_ ptr: UnsafeRawPointer, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        memcpy(&out, ptr, count * MemoryLayout<Float>.size)
        return out
    }

    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot
    }

    // MARK: - SQLite helpers

    @discardableResult
    private func exec(_ sql: String, args: [Any] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(sqliteError())
        }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            switch arg {
            case let s as String:
                sqlite3_bind_text(stmt, idx, s, -1, transient)
            case let d as Double:
                sqlite3_bind_double(stmt, idx, d)
            case let n as Int:
                sqlite3_bind_int64(stmt, idx, Int64(n))
            case let data as Data:
                _ = data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(data.count), transient)
                }
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw StoreError.queryFailed(sqliteError())
        }
        return Int(sqlite3_changes(db))
    }

    private func sqliteError() -> String {
        db.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "unknown"
    }
}
