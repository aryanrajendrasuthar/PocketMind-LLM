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
import CryptoKit
import os.log

/// Orchestrates on-device Retrieval-Augmented Generation.
///
/// Documents are chunked at sentence boundaries, embedded using Apple's built-in
/// `NLEmbedding` (no model download required), and stored in a local SQLite database.
/// At query time, the single best-matching chunk is retrieved and injected into the
/// prompt — fitting within the 256-token context window by design.
///
/// **No data ever leaves the device.**
actor RAGEngine {

    // MARK: - Types

    struct IndexResult: Sendable {
        let docId: String
        let filename: String
        let chunkCount: Int
    }

    // MARK: - State

    private let embedder = EmbeddingService()
    private var store: VectorStore?
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "RAGEngine")

    // MARK: - Init

    init() {
        do {
            let emb = EmbeddingService()
            store = try VectorStore(embeddingDimension: emb.dimension)
        } catch {
            logger.error("RAGEngine init failed: \(error.localizedDescription, privacy: .public)")
            store = nil
        }
    }

    // MARK: - Indexing

    /// Chunk, embed, and store a document. Returns the index result or nil on failure.
    ///
    /// The document ID is a SHA-256 hash of the filename, so re-indexing the same file
    /// replaces the previous version without duplication.
    @discardableResult
    func indexDocument(filename: String, content: String) async -> IndexResult? {
        guard let store else { return nil }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let docId = sha256(filename)
        let rawChunks = TextChunker.chunk(content)

        var records: [ChunkRecord] = []
        for (i, text) in rawChunks.enumerated() {
            guard let emb = embedder.embed(text) else { continue }
            records.append(ChunkRecord(index: i, content: text, embedding: emb))
        }

        guard !records.isEmpty else {
            logger.warning("No embeddable chunks for '\(filename, privacy: .public)'.")
            return nil
        }

        do {
            try store.upsertDocument(id: docId, filename: filename, chunks: records)
            logger.info("Indexed '\(filename, privacy: .public)' — \(records.count) chunks.")
            return IndexResult(docId: docId, filename: filename, chunkCount: records.count)
        } catch {
            logger.error("Index failed for '\(filename, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Retrieval

    /// Find the most relevant text passage for `query`.
    ///
    /// Returns a formatted context string ready for injection into the prompt, or `nil`
    /// if no passage meets the similarity threshold.
    func retrieveContext(for query: String) async -> String? {
        guard let store else { return nil }
        guard let queryEmb = embedder.embed(query) else { return nil }

        do {
            let results = try store.search(
                queryEmbedding: queryEmb,
                topK: Constants.RAG.topK,
                threshold: Constants.RAG.similarityThreshold
            )
            guard let best = results.first else { return nil }

            logger.info("RAG retrieved (score=\(String(format: "%.2f", best.score), privacy: .public)): '\(best.content.prefix(60), privacy: .public)…'")
            return best.content
        } catch {
            logger.error("RAG retrieval error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Management

    /// All currently indexed documents.
    func allDocuments() -> [DocumentRecord] {
        (try? store?.allDocuments()) ?? []
    }

    /// Remove a document and all its chunks from the store.
    func deleteDocument(id: String) {
        try? store?.deleteDocument(id: id)
        logger.info("Deleted RAG document \(id, privacy: .public).")
    }

    // MARK: - Helpers

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
