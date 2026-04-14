import Foundation
import GRDB
import CryptoKit
import os.log

/// Sync conflict record for import conflict resolution
struct SyncConflict: Sendable {
    let entityType: String
    let entityId: UUID
    let localVersion: Int
    let incomingVersion: Int
    let localData: String
    let incomingData: String
}

/// Decision for resolving a sync conflict
enum SyncConflictDecision: String, Sendable {
    case keepLocal = "KEEP_LOCAL"
    case acceptIncoming = "ACCEPT_INCOMING"
}

final class SyncService: Sendable {
    private let dbPool: DatabasePool
    private let syncRepository: SyncRepository
    private let postingRepository: PostingRepository
    private let taskRepository: TaskRepository?
    private let assignmentRepository: AssignmentRepository?
    private let commentRepository: CommentRepository?
    private let dependencyRepository: DependencyRepository?
    private let userRepository: UserRepository?
    private let auditService: AuditService

    /// Cached import data for conflict resolution (keyed by import ID)
    private let importCache = ImportCache()

    init(
        dbPool: DatabasePool,
        syncRepository: SyncRepository,
        postingRepository: PostingRepository,
        auditService: AuditService,
        taskRepository: TaskRepository? = nil,
        assignmentRepository: AssignmentRepository? = nil,
        commentRepository: CommentRepository? = nil,
        dependencyRepository: DependencyRepository? = nil,
        userRepository: UserRepository? = nil
    ) {
        self.dbPool = dbPool
        self.syncRepository = syncRepository
        self.postingRepository = postingRepository
        self.auditService = auditService
        self.taskRepository = taskRepository
        self.assignmentRepository = assignmentRepository
        self.commentRepository = commentRepository
        self.dependencyRepository = dependencyRepository
        self.userRepository = userRepository
    }

    // MARK: - Authorization

    /// Sync operations require admin or coordinator role.
    private func requireSyncAccess(actorId: UUID) async throws {
        guard let userRepo = userRepository, let actor = try await userRepo.findById(actorId) else {
            throw SyncError.exportFailed(reason: "Not authorized")
        }
        guard actor.role == .admin || actor.role == .coordinator else {
            throw SyncError.exportFailed(reason: "Not authorized — admin or coordinator required")
        }
    }

    // MARK: - Export

    /// Public export API. Uses a single `startDate` applied uniformly to all entity types.
    func export(
        entityTypes: [String],
        startDate: Date?,
        endDate: Date?,
        exportedBy: UUID
    ) async throws -> SyncExport {
        // Build a uniform per-entity start-date map from the single startDate
        let startDates = Dictionary(uniqueKeysWithValues: entityTypes.map { ($0, startDate) })
        return try await exportWithPerEntityDates(
            entityTypes: entityTypes, startDates: startDates, endDate: endDate, exportedBy: exportedBy
        )
    }

    /// Core export implementation. Each entity type is filtered by its own cursor date from
    /// `startDates`, so delta exports are scoped correctly per entity and cannot over-export.
    private func exportWithPerEntityDates(
        entityTypes: [String],
        startDates: [String: Date?],
        endDate: Date?,
        exportedBy: UUID
    ) async throws -> SyncExport {
        try await requireSyncAccess(actorId: exportedBy)
        ForgeLogger.sync.info("Export started by actor \(exportedBy, privacy: .public), entityTypes=\(entityTypes.joined(separator: ","), privacy: .public)")
        let exportId = UUID()
        let exportDir = Self.exportsDirectory()
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let fileName = "forgeflow-\(Self.dateFormatter.string(from: Date()))-\(exportId.uuidString.prefix(8)).forgeflow"
        let exportURL = exportDir.appendingPathComponent(fileName)

        var totalRecords = 0
        var entityData: [String: [[String: Any]]] = [:]

        let iso8601 = ISO8601DateFormatter()

        // Export postings — filter by updatedAt to capture modifications as well as new records
        if entityTypes.contains("postings") {
            let startDate = startDates["postings"] ?? nil
            let postings = try await postingRepository.findAll()
            var records: [[String: Any]] = []
            for posting in postings {
                if let start = startDate, posting.updatedAt < start { continue }
                if let end = endDate, posting.updatedAt > end { continue }
                records.append([
                    "id": posting.id.uuidString,
                    "title": posting.title,
                    "siteAddress": posting.siteAddress,
                    "status": posting.status.rawValue,
                    "budgetCapCents": posting.budgetCapCents,
                    "acceptanceMode": posting.acceptanceMode.rawValue,
                    "createdBy": posting.createdBy.uuidString,
                    "watermarkEnabled": posting.watermarkEnabled,
                    "version": posting.version,
                    "dueDate": iso8601.string(from: posting.dueDate),
                    "updatedAt": iso8601.string(from: posting.updatedAt),
                ])
            }
            entityData["postings"] = records
            totalRecords += records.count
        }

        // Export tasks — filter by updatedAt so status changes are captured incrementally
        if entityTypes.contains("tasks"), let taskRepo = taskRepository {
            let startDate = startDates["tasks"] ?? nil
            let allPostings = try await postingRepository.findAll()
            var records: [[String: Any]] = []
            for posting in allPostings {
                let tasks = try await taskRepo.findByPosting(posting.id)
                for task in tasks {
                    if let start = startDate, task.updatedAt < start { continue }
                    if let end = endDate, task.updatedAt > end { continue }
                    records.append([
                        "id": task.id.uuidString,
                        "postingId": task.postingId.uuidString,
                        "title": task.title,
                        "status": task.status.rawValue,
                        "priority": task.priority.rawValue,
                        "version": task.version,
                        "updatedAt": iso8601.string(from: task.updatedAt),
                    ])
                }
            }
            entityData["tasks"] = records
            totalRecords += records.count
        }

        // Export assignments — filter by updatedAt to capture status transitions
        if entityTypes.contains("assignments"), let assignRepo = assignmentRepository {
            let startDate = startDates["assignments"] ?? nil
            let allPostings = try await postingRepository.findAll()
            var records: [[String: Any]] = []
            for posting in allPostings {
                let assignments = try await assignRepo.findByPosting(posting.id)
                for a in assignments {
                    if let start = startDate, a.updatedAt < start { continue }
                    if let end = endDate, a.updatedAt > end { continue }
                    records.append([
                        "id": a.id.uuidString,
                        "postingId": a.postingId.uuidString,
                        "technicianId": a.technicianId.uuidString,
                        "status": a.status.rawValue,
                        "version": a.version,
                        "updatedAt": iso8601.string(from: a.updatedAt),
                    ])
                }
            }
            entityData["assignments"] = records
            totalRecords += records.count
        }

        // Export comments — additive only, filter by createdAt (no updatedAt on comments)
        if entityTypes.contains("comments"), let commentRepo = commentRepository {
            let startDate = startDates["comments"] ?? nil
            let allPostings = try await postingRepository.findAll()
            var records: [[String: Any]] = []
            for posting in allPostings {
                let comments = try await commentRepo.findByPosting(posting.id)
                for c in comments {
                    if let start = startDate, c.createdAt < start { continue }
                    if let end = endDate, c.createdAt > end { continue }
                    var record: [String: Any] = [
                        "id": c.id.uuidString,
                        "postingId": c.postingId.uuidString,
                        "authorId": c.authorId.uuidString,
                        "body": c.body,
                        "createdAt": iso8601.string(from: c.createdAt),
                    ]
                    if let parentId = c.parentCommentId { record["parentCommentId"] = parentId.uuidString }
                    if let taskId = c.taskId { record["taskId"] = taskId.uuidString }
                    records.append(record)
                }
            }
            entityData["comments"] = records
            totalRecords += records.count
        }

        // Export dependencies — immutable relationships; always export all deps whose task
        // falls within the window (task updatedAt in range), or all deps on a full export.
        if entityTypes.contains("dependencies"), let depRepo = dependencyRepository, let taskRepo = taskRepository {
            let startDate = startDates["dependencies"] ?? nil
            let allPostings = try await postingRepository.findAll()
            var records: [[String: Any]] = []
            for posting in allPostings {
                let tasks = try await taskRepo.findByPosting(posting.id)
                for task in tasks {
                    // Include deps for tasks that are within the date window (or on full export)
                    if let start = startDate, task.updatedAt < start { continue }
                    let deps = try await depRepo.findByTask(task.id)
                    for dep in deps {
                        records.append([
                            "id": dep.id.uuidString,
                            "taskId": dep.taskId.uuidString,
                            "dependsOnTaskId": dep.dependsOnTaskId.uuidString,
                            "type": dep.type.rawValue,
                        ])
                    }
                }
            }
            entityData["dependencies"] = records
            totalRecords += records.count
        }

        // Build data payload (without checksum)
        let dataPayload: [String: Any] = ["data": entityData]
        let dataJson = try JSONSerialization.data(withJSONObject: dataPayload, options: [.sortedKeys])

        // Compute SHA-256 of data payload
        let checksum = SHA256.hash(data: dataJson)
            .map { String(format: "%02x", $0) }
            .joined()

        // Build final file with manifest + data
        let manifest: [String: Any] = [
            "version": "1.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "entityTypes": entityTypes,
            "recordCount": totalRecords,
            "checksumSha256": checksum,
        ]

        let finalPayload: [String: Any] = ["manifest": manifest, "data": entityData]
        let jsonData = try JSONSerialization.data(withJSONObject: finalPayload, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: exportURL)

        let entityTypesJson = try String(
            data: JSONSerialization.data(withJSONObject: entityTypes),
            encoding: .utf8
        ) ?? "[]"

        let syncExport = SyncExport(
            id: exportId,
            exportedBy: exportedBy,
            filePath: exportURL.path,
            entityTypes: entityTypesJson,
            recordCount: totalRecords,
            checksumSha256: checksum,
            exportedAt: Date()
        )

        try await dbPool.write { [self] db in
            try syncRepository.insertExportInTransaction(db: db, syncExport)
            try auditService.record(
                db: db, actorId: exportedBy,
                action: "SYNC_EXPORTED", entityType: "SyncExport", entityId: exportId,
                afterData: "{\"recordCount\":\(totalRecords)}"
            )
        }

        ForgeLogger.sync.info("Export completed: exportId=\(exportId, privacy: .public) records=\(totalRecords, privacy: .public)")
        return syncExport
    }

    // MARK: - Import

    func importFile(
        fileURL: URL,
        importedBy: UUID
    ) async throws -> (syncImport: SyncImport, conflicts: [SyncConflict]) {
        try await requireSyncAccess(actorId: importedBy)
        ForgeLogger.sync.info("Import started by actor \(importedBy, privacy: .public)")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            ForgeLogger.sync.error("Import failed: file not found at path \(fileURL.lastPathComponent, privacy: .private)")
            throw SyncError.invalidSyncFile
        }

        let fileData = try Data(contentsOf: fileURL)

        guard let json = try JSONSerialization.jsonObject(with: fileData) as? [String: Any],
              let manifestDict = json["manifest"] as? [String: Any],
              let dataDict = json["data"] as? [String: [[String: Any]]] else {
            throw SyncError.invalidSyncFile
        }

        // Validate checksum: recompute from data section and compare to manifest
        guard let storedChecksum = manifestDict["checksumSha256"] as? String else {
            throw SyncError.checksumValidationFailed
        }

        let dataPayload: [String: Any] = ["data": dataDict]
        let dataJson = try JSONSerialization.data(withJSONObject: dataPayload, options: [.sortedKeys])
        let computedChecksum = SHA256.hash(data: dataJson)
            .map { String(format: "%02x", $0) }
            .joined()

        guard computedChecksum == storedChecksum else {
            throw SyncError.checksumValidationFailed
        }

        // Compare incoming records with local — detect conflicts
        var conflicts: [SyncConflict] = []
        var totalRecords = 0

        // Postings
        if let incomingPostings = dataDict["postings"] {
            for record in incomingPostings {
                totalRecords += 1
                guard let idStr = record["id"] as? String,
                      let incomingId = UUID(uuidString: idStr),
                      let incomingVersion = record["version"] as? Int else { continue }

                if let localPosting = try await postingRepository.findById(incomingId) {
                    if localPosting.version != incomingVersion {
                        conflicts.append(SyncConflict(
                            entityType: "postings", entityId: incomingId,
                            localVersion: localPosting.version, incomingVersion: incomingVersion,
                            localData: "{\"title\":\"\(localPosting.title)\",\"version\":\(localPosting.version)}",
                            incomingData: "{\"title\":\"\(record["title"] ?? "")\",\"version\":\(incomingVersion)}"
                        ))
                    }
                }
            }
        }

        // Tasks
        if let incomingTasks = dataDict["tasks"], let taskRepo = taskRepository {
            for record in incomingTasks {
                totalRecords += 1
                guard let idStr = record["id"] as? String,
                      let incomingId = UUID(uuidString: idStr),
                      let incomingVersion = record["version"] as? Int else { continue }

                if let localTask = try await taskRepo.findById(incomingId) {
                    if localTask.version != incomingVersion {
                        conflicts.append(SyncConflict(
                            entityType: "tasks", entityId: incomingId,
                            localVersion: localTask.version, incomingVersion: incomingVersion,
                            localData: "{\"title\":\"\(localTask.title)\",\"version\":\(localTask.version)}",
                            incomingData: "{\"title\":\"\(record["title"] ?? "")\",\"version\":\(incomingVersion)}"
                        ))
                    }
                }
            }
        }

        // Assignments
        if let incomingAssignments = dataDict["assignments"], let assignRepo = assignmentRepository {
            for record in incomingAssignments {
                totalRecords += 1
                guard let idStr = record["id"] as? String,
                      let incomingId = UUID(uuidString: idStr),
                      let incomingVersion = record["version"] as? Int else { continue }

                if let localAssignment = try await assignRepo.findById(incomingId) {
                    if localAssignment.version != incomingVersion {
                        conflicts.append(SyncConflict(
                            entityType: "assignments", entityId: incomingId,
                            localVersion: localAssignment.version, incomingVersion: incomingVersion,
                            localData: "{\"status\":\"\(localAssignment.status.rawValue)\",\"version\":\(localAssignment.version)}",
                            incomingData: "{\"status\":\"\(record["status"] ?? "")\",\"version\":\(incomingVersion)}"
                        ))
                    }
                }
            }
        }

        // Comments (additive — no version conflicts, just count)
        if let incomingComments = dataDict["comments"] {
            totalRecords += incomingComments.count
        }

        // Dependencies (additive — no version conflicts)
        if let incomingDeps = dataDict["dependencies"] {
            totalRecords += incomingDeps.count
        }

        // Extract source watermark and entity types from manifest.
        // These are stored on the import record so the cursor can be advanced to the
        // source's exportedAt (not local importedAt) and scoped to the manifest's entity types.
        let iso8601 = ISO8601DateFormatter()
        let sourceExportedAt = (manifestDict["exportedAt"] as? String)
            .flatMap { iso8601.date(from: $0) }
        let sourceEntityTypesJson: String? = {
            guard let types = manifestDict["entityTypes"] as? [String] else { return nil }
            return try? String(data: JSONSerialization.data(withJSONObject: types), encoding: .utf8)
        }()

        let importId = UUID()
        let status: SyncImportStatus = conflicts.isEmpty ? .validated : .pending

        var syncImport = SyncImport(
            id: importId, importedBy: importedBy, filePath: fileURL.path,
            recordCount: totalRecords, conflictsCount: conflicts.count,
            status: status, importedAt: Date(),
            sourceExportedAt: sourceExportedAt,
            sourceEntityTypes: sourceEntityTypesJson
        )

        // Cache the import data for conflict resolution
        await importCache.store(importId: importId, data: dataDict)

        try await dbPool.write { [self] db in
            try syncRepository.insertImportInTransaction(db: db, syncImport)
            try auditService.record(
                db: db, actorId: importedBy,
                action: "SYNC_IMPORTED", entityType: "SyncImport", entityId: importId,
                afterData: "{\"recordCount\":\(totalRecords),\"conflicts\":\(conflicts.count)}"
            )
        }

        return (syncImport, conflicts)
    }

    // MARK: - Resolve Conflicts

    func resolveConflicts(
        importId: UUID,
        decisions: [(entityId: UUID, decision: SyncConflictDecision)],
        actorId: UUID
    ) async throws {
        try await requireSyncAccess(actorId: actorId)
        guard var syncImport = try await syncRepository.findImportById(importId) else {
            throw SyncError.importFailed(reason: "Import record not found")
        }

        let cachedData = await importCache.load(importId: importId)

        // Track how many conflicts are being resolved in this call
        let resolvedCount = decisions.count
        let remainingConflicts = max(0, syncImport.conflictsCount - resolvedCount)

        try await dbPool.write { [self] db in
            for (entityId, decision) in decisions {
                if decision == .acceptIncoming {
                    if let data = cachedData {
                        try applyIncoming(db: db, entityId: entityId, importData: data)
                    }
                }
                // keepLocal = no DB change needed (local data preserved)
                try auditService.record(
                    db: db, actorId: actorId,
                    action: "SYNC_CONFLICT_RESOLVED", entityType: "SyncImport",
                    entityId: entityId,
                    afterData: "{\"decision\":\"\(decision.rawValue)\"}"
                )
            }

            syncImport.conflictsCount = remainingConflicts

            // Only mark APPLIED when ALL conflicts have been resolved
            if remainingConflicts == 0 {
                // Apply all non-conflicting records; collect any insert/validation errors
                var insertErrors: [String] = []
                if let data = cachedData {
                    insertErrors = applyNonConflicting(db: db, importData: data)
                }
                syncImport.status = insertErrors.isEmpty ? .applied : .partialFailure
                if !insertErrors.isEmpty {
                    ForgeLogger.sync.error("Import applied with \(insertErrors.count, privacy: .public) record errors for importId=\(syncImport.id, privacy: .public)")
                } else {
                    ForgeLogger.sync.info("Import fully applied for importId=\(syncImport.id, privacy: .public)")
                }
            }

            try syncRepository.updateImportInTransaction(db: db, &syncImport)
        }

        if remainingConflicts == 0 {
            await importCache.remove(importId: importId)
        }
    }

    /// Inserts records from import data that don't exist locally (new entities).
    /// Returns a list of error descriptions for records that failed validation or insertion.
    @discardableResult
    private func applyNonConflicting(db: Database, importData: [String: [[String: Any]]]) -> [String] {
        var errors: [String] = []

        // Insert new postings
        if let postings = importData["postings"] {
            for record in postings {
                guard let idStr = record["id"] as? String,
                      let id = UUID(uuidString: idStr) else {
                    errors.append("posting: missing or invalid id")
                    continue
                }
                guard let createdByStr = record["createdBy"] as? String,
                      let createdBy = UUID(uuidString: createdByStr) else {
                    errors.append("posting \(idStr): missing or invalid createdBy")
                    continue
                }
                do {
                    if try ServicePosting.fetchOne(db, key: id) == nil {
                        let now = Date()
                        let dueDate = (record["dueDate"] as? String)
                            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? now
                        var posting = ServicePosting(
                            id: id,
                            title: (record["title"] as? String) ?? "",
                            siteAddress: (record["siteAddress"] as? String) ?? "",
                            dueDate: dueDate,
                            budgetCapCents: (record["budgetCapCents"] as? Int) ?? 0,
                            status: PostingStatus(rawValue: (record["status"] as? String) ?? "DRAFT") ?? .draft,
                            acceptanceMode: AcceptanceMode(rawValue: (record["acceptanceMode"] as? String) ?? "OPEN") ?? .open,
                            createdBy: createdBy,
                            watermarkEnabled: (record["watermarkEnabled"] as? Bool) ?? false,
                            version: (record["version"] as? Int) ?? 1,
                            createdAt: now, updatedAt: now
                        )
                        try posting.insert(db)
                    }
                } catch {
                    errors.append("posting \(idStr): \(error.localizedDescription)")
                }
            }
        }

        // Insert new tasks
        if let tasks = importData["tasks"] {
            for record in tasks {
                guard let idStr = record["id"] as? String,
                      let id = UUID(uuidString: idStr) else {
                    errors.append("task: missing or invalid id")
                    continue
                }
                guard let postingIdStr = record["postingId"] as? String,
                      let postingId = UUID(uuidString: postingIdStr) else {
                    errors.append("task \(idStr): missing or invalid postingId")
                    continue
                }
                do {
                    if try ForgeTask.fetchOne(db, key: id) == nil {
                        let now = Date()
                        var task = ForgeTask(
                            id: id,
                            postingId: postingId,
                            parentTaskId: nil,
                            title: (record["title"] as? String) ?? "",
                            taskDescription: nil,
                            priority: Priority(rawValue: (record["priority"] as? String) ?? "P2") ?? .p2,
                            status: TaskStatus(rawValue: (record["status"] as? String) ?? "NOT_STARTED") ?? .notStarted,
                            blockedComment: nil, assignedTo: nil, sortOrder: 0,
                            version: (record["version"] as? Int) ?? 1,
                            createdAt: now, updatedAt: now
                        )
                        try task.insert(db)
                    }
                } catch {
                    errors.append("task \(idStr): \(error.localizedDescription)")
                }
            }
        }

        // Insert new comments (additive, no conflict)
        if let comments = importData["comments"] {
            for record in comments {
                guard let idStr = record["id"] as? String,
                      let id = UUID(uuidString: idStr) else {
                    errors.append("comment: missing or invalid id")
                    continue
                }
                guard let postingIdStr = record["postingId"] as? String,
                      let postingId = UUID(uuidString: postingIdStr) else {
                    errors.append("comment \(idStr): missing or invalid postingId")
                    continue
                }
                guard let authorIdStr = record["authorId"] as? String,
                      let authorId = UUID(uuidString: authorIdStr) else {
                    errors.append("comment \(idStr): missing or invalid authorId")
                    continue
                }
                do {
                    if try Comment.fetchOne(db, key: id) == nil {
                        let comment = Comment(
                            id: id,
                            postingId: postingId,
                            taskId: (record["taskId"] as? String).flatMap(UUID.init),
                            authorId: authorId,
                            body: (record["body"] as? String) ?? "",
                            parentCommentId: (record["parentCommentId"] as? String).flatMap(UUID.init),
                            createdAt: Date()
                        )
                        try comment.insert(db)
                    }
                } catch {
                    errors.append("comment \(idStr): \(error.localizedDescription)")
                }
            }
        }

        return errors
    }

    /// Applies incoming record data to the local database.
    private func applyIncoming(db: Database, entityId: UUID, importData: [String: [[String: Any]]]) throws {
        // Check postings
        // Postings — full field mapping
        if let postings = importData["postings"] {
            if let r = postings.first(where: { ($0["id"] as? String) == entityId.uuidString }) {
                if var local = try ServicePosting.fetchOne(db, key: entityId) {
                    if let v = r["title"] as? String { local.title = v }
                    if let v = r["siteAddress"] as? String { local.siteAddress = v }
                    if let v = r["budgetCapCents"] as? Int { local.budgetCapCents = v }
                    if let v = r["status"] as? String, let s = PostingStatus(rawValue: v) { local.status = s }
                    if let v = r["acceptanceMode"] as? String, let m = AcceptanceMode(rawValue: v) { local.acceptanceMode = m }
                    if let v = r["watermarkEnabled"] as? Bool { local.watermarkEnabled = v }
                    if let v = r["dueDate"] as? String { local.dueDate = ISO8601DateFormatter().date(from: v) ?? local.dueDate }
                    if let v = r["version"] as? Int { local.version = v }
                    local.updatedAt = Date()
                    try local.update(db)
                    return
                }
            }
        }
        // Tasks — full field mapping
        if let tasks = importData["tasks"] {
            if let r = tasks.first(where: { ($0["id"] as? String) == entityId.uuidString }) {
                if var local = try ForgeTask.fetchOne(db, key: entityId) {
                    if let v = r["title"] as? String { local.title = v }
                    if let v = r["status"] as? String, let s = TaskStatus(rawValue: v) { local.status = s }
                    if let v = r["priority"] as? String, let p = Priority(rawValue: v) { local.priority = p }
                    if let v = r["version"] as? Int { local.version = v }
                    local.updatedAt = Date()
                    try local.update(db)
                    return
                }
            }
        }
        // Assignments — full field mapping
        if let assignments = importData["assignments"] {
            if let r = assignments.first(where: { ($0["id"] as? String) == entityId.uuidString }) {
                if var local = try Assignment.fetchOne(db, key: entityId) {
                    if let v = r["status"] as? String, let s = AssignmentStatus(rawValue: v) { local.status = s }
                    if let v = r["version"] as? Int { local.version = v }
                    local.updatedAt = Date()
                    try local.update(db)
                    return
                }
            }
        }
    }

    // MARK: - Read

    private func requireAdminOrCoordinator(actorId: UUID) async throws {
        guard let userRepo = userRepository,
              let actor = try await userRepo.findById(actorId),
              actor.role == .admin || actor.role == .coordinator else {
            throw SyncError.notAuthorized
        }
    }

    func listExports(actorId: UUID) async throws -> [SyncExport] {
        try await requireAdminOrCoordinator(actorId: actorId)
        return try await syncRepository.findAllExports()
    }

    func listImports(actorId: UUID) async throws -> [SyncImport] {
        try await requireAdminOrCoordinator(actorId: actorId)
        return try await syncRepository.findAllImports()
    }

    func latestExport(actorId: UUID) async throws -> SyncExport? {
        try await requireAdminOrCoordinator(actorId: actorId)
        return try await syncRepository.latestExport()
    }

    func latestImport(actorId: UUID) async throws -> SyncImport? {
        try await requireAdminOrCoordinator(actorId: actorId)
        return try await syncRepository.latestImport()
    }

    // MARK: - Incremental (Delta) Export

    /// Exports only records updated since the last confirmed sync with `peerId`.
    /// Each entity type uses its own cursor date so deltas are correctly scoped —
    /// a stale cursor for one entity does not cause over-export of another.
    ///
    /// **Cursors are NOT advanced here.** Call `confirmExportDelivered` after the peer
    /// confirms receipt and successful apply. This prevents data loss if the transfer fails:
    /// a retry will re-export the same delta rather than skipping records.
    func exportDelta(peerId: String, entityTypes: [String], exportedBy: UUID) async throws -> SyncExport {
        // Build per-entity cursor map (nil = no cursor yet → full export for that type)
        var startDates: [String: Date?] = [:]
        for entityType in entityTypes {
            let cursor = try await syncRepository.findCursor(peerId: peerId, entityType: entityType)
            startDates[entityType] = cursor?.lastSyncedAt
        }

        // Export each entity type against its own cursor date — no cursor advancement
        return try await exportWithPerEntityDates(
            entityTypes: entityTypes, startDates: startDates, endDate: nil, exportedBy: exportedBy
        )
    }

    /// Advances the local export cursor after the peer confirms receipt and successful apply.
    /// Must be called explicitly — `exportDelta` alone does not advance cursors.
    func confirmExportDelivered(peerId: String, entityTypes: [String], exportedAt: Date, actorId: UUID) async throws {
        try await requireSyncAccess(actorId: actorId)
        for entityType in entityTypes {
            try await syncRepository.upsertCursor(peerId: peerId, entityType: entityType, lastSyncedAt: exportedAt)
        }
    }

    /// Records that data from `peerId` has been successfully imported up to `syncedAt`.
    /// Call after a successful apply (`.applied` status) to update the local delta cursor.
    func recordImportedFrom(peerId: String, entityTypes: [String], syncedAt: Date, actorId: UUID) async throws {
        try await requireAdminOrCoordinator(actorId: actorId)
        for entityType in entityTypes {
            try await syncRepository.upsertCursor(peerId: peerId, entityType: entityType, lastSyncedAt: syncedAt)
        }
    }

    func listCursors(peerId: String, actorId: UUID) async throws -> [SyncCursor] {
        try await requireAdminOrCoordinator(actorId: actorId)
        return try await syncRepository.listCursors(peerId: peerId)
    }

    // MARK: - Helpers

    static func exportsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("exports", isDirectory: true)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

// MARK: - Import Data Cache (actor for thread safety)

private actor ImportCache {
    private var cache: [UUID: [String: [[String: Any]]]] = [:]

    func store(importId: UUID, data: [String: [[String: Any]]]) {
        cache[importId] = data
    }

    func load(importId: UUID) -> [String: [[String: Any]]]? {
        cache[importId]
    }

    func remove(importId: UUID) {
        cache.removeValue(forKey: importId)
    }
}
