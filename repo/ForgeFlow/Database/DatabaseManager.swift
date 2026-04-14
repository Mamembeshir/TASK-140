import Foundation
import GRDB

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupportURL.appendingPathComponent("ForgeFlow.sqlite")

            var config = Configuration()
            config.foreignKeysEnabled = true
            #if DEBUG
            if ProcessInfo.processInfo.environment["FORGEFLOW_SQL_TRACE"] == "1" {
                config.prepareDatabase { db in
                    db.trace { event in
                        // Redact potentially sensitive fields from trace output
                        var desc = String(describing: event)
                        for sensitive in ["password", "hash", "token", "secret", "dndStartTime", "dndEndTime"] {
                            desc = desc.replacingOccurrences(
                                of: "(?i)\(sensitive)\\s*=\\s*'[^']*'",
                                with: "\(sensitive)='[REDACTED]'",
                                options: .regularExpression
                            )
                        }
                        print("SQL: \(desc)")
                    }
                }
            }
            #endif

            dbPool = try DatabasePool(path: dbURL.path, configuration: config)
            try migrator.migrate(dbPool)
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    /// For testing with a temporary on-disk database
    init(inMemory: Bool) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbURL = tempDir.appendingPathComponent("ForgeFlowTest-\(UUID().uuidString).sqlite")

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("001_InitialSchema") { db in
            try InitialSchemaMigration.migrate(db)
        }

        migrator.registerMigration("002_PostingsSchema") { db in
            try PostingsSchemaMigration.migrate(db)
        }

        migrator.registerMigration("003_CommentsAttachmentsSchema") { db in
            try CommentsAttachmentsSchemaMigration.migrate(db)
        }

        migrator.registerMigration("004_MessagingSchema") { db in
            try MessagingSchemaMigration.migrate(db)
        }

        migrator.registerMigration("005_PluginSyncSchema") { db in
            try PluginSyncSchemaMigration.migrate(db)
        }

        migrator.registerMigration("006_AssignmentConstraints") { db in
            try AssignmentConstraintsMigration.migrate(db)
        }

        migrator.registerMigration("007_PostingFieldValues") { db in
            try PostingFieldValuesMigration.migrate(db)
        }

        migrator.registerMigration("008_SyncCursorSchema") { db in
            try SyncCursorSchemaMigration.migrate(db)
        }

        migrator.registerMigration("009_SyncImportMetadata") { db in
            try SyncImportMetadataMigration.migrate(db)
        }

        return migrator
    }
}
