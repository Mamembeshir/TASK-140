import Foundation
import os.log

/// Structured domain-level loggers for ForgeFlow.
///
/// Sensitive fields use `privacy: .private` which redacts values in non-debug
/// (production) builds at the OS level. Counts, IDs, and status codes are
/// marked `.public` since they contain no PII.
///
/// Usage:
///   ForgeLogger.auth.info("Login succeeded for actor \(id, privacy: .public)")
///   ForgeLogger.auth.warning("Login failed: \(username, privacy: .private)")
enum ForgeLogger {
    /// Authentication, authorization, and role-check events.
    /// Watch this category to debug login failures, lockouts, and access-denied events.
    static let auth = Logger(subsystem: "com.forgeflow.app", category: "auth")

    /// Sync export/import lifecycle events.
    /// Watch this category to debug data sync, checksum failures, and conflict resolution.
    static let sync = Logger(subsystem: "com.forgeflow.app", category: "sync")

    /// File upload, download, and attachment management events.
    /// Watch this category to debug quota, magic-byte validation, and encryption paths.
    static let attachments = Logger(subsystem: "com.forgeflow.app", category: "attachments")

    /// Background task scheduling, execution, and expiration events.
    /// Watch this category to debug orphan cleanup, compression, cache eviction, and chunking.
    static let background = Logger(subsystem: "com.forgeflow.app", category: "background")
}
