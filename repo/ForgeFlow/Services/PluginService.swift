import Foundation
import GRDB

final class PluginService: Sendable {
    private let dbPool: DatabasePool
    private let pluginRepository: PluginRepository
    private let postingRepository: PostingRepository
    private let userRepository: UserRepository?
    private let auditService: AuditService
    let notificationService: NotificationService?

    init(
        dbPool: DatabasePool,
        pluginRepository: PluginRepository,
        postingRepository: PostingRepository,
        auditService: AuditService,
        notificationService: NotificationService? = nil,
        userRepository: UserRepository? = nil
    ) {
        self.dbPool = dbPool
        self.pluginRepository = pluginRepository
        self.postingRepository = postingRepository
        self.auditService = auditService
        self.notificationService = notificationService
        self.userRepository = userRepository
    }

    // MARK: - Authorization

    /// Enforces that the actor is an admin. All plugin lifecycle operations are admin-only.
    private func requireAdmin(actorId: UUID) async throws {
        guard let userRepo = userRepository,
              let actor = try await userRepo.findById(actorId) else {
            throw PluginError.notAuthorized
        }
        guard actor.role == .admin else {
            throw PluginError.notAuthorized
        }
    }

    /// Enforces that the actor is an admin or coordinator (posting creators who set field values).
    private func requireAdminOrCoordinator(actorId: UUID) async throws {
        guard let userRepo = userRepository,
              let actor = try await userRepo.findById(actorId) else {
            throw PluginError.notAuthorized
        }
        guard actor.role == .admin || actor.role == .coordinator else {
            throw PluginError.notAuthorized
        }
    }

    // MARK: - Create (Admin only → DRAFT)

    func create(
        name: String,
        description: String,
        category: String,
        createdBy: UUID
    ) async throws -> PluginDefinition {
        try await requireAdmin(actorId: createdBy)

        let now = Date()
        let plugin = PluginDefinition(
            id: UUID(),
            name: name,
            description: description,
            category: category,
            status: .draft,
            createdBy: createdBy,
            version: 1,
            createdAt: now,
            updatedAt: now
        )

        try await dbPool.write { [self] db in
            try pluginRepository.insertInTransaction(db: db, plugin)
            try auditService.record(
                db: db,
                actorId: createdBy,
                action: "PLUGIN_CREATED",
                entityType: "PluginDefinition",
                entityId: plugin.id,
                afterData: "{\"name\":\"\(name)\",\"category\":\"\(category)\"}"
            )
        }

        return plugin
    }

    // MARK: - Add Field

    func addField(
        pluginId: UUID,
        fieldName: String,
        fieldType: PluginFieldType,
        unit: String?,
        validationRules: String?,
        actorId: UUID
    ) async throws -> PluginField {
        try await requireAdmin(actorId: actorId)

        guard let plugin = try await pluginRepository.findById(pluginId) else {
            throw PluginError.pluginNotFound
        }
        guard plugin.status == .draft || plugin.status == .testing else {
            throw PluginError.invalidStatusTransition(from: plugin.status, to: plugin.status)
        }

        let existingFields = try await pluginRepository.findFields(pluginId: pluginId)
        let now = Date()
        let field = PluginField(
            id: UUID(),
            pluginId: pluginId,
            fieldName: fieldName,
            fieldType: fieldType,
            unit: unit,
            validationRules: validationRules,
            sortOrder: existingFields.count,
            createdAt: now
        )

        try await dbPool.write { [self] db in
            try pluginRepository.insertFieldInTransaction(db: db, field)
        }

        return field
    }

    // MARK: - Test Plugin (evaluate validation rules against sample postings)

    func testPlugin(pluginId: UUID, samplePostingIds: [UUID], actorId: UUID) async throws -> [PluginTestResult] {
        try await requireAdmin(actorId: actorId)

        guard let plugin = try await pluginRepository.findById(pluginId) else {
            throw PluginError.pluginNotFound
        }
        guard plugin.status == .draft || plugin.status == .testing else {
            throw PluginError.invalidStatusTransition(from: plugin.status, to: .testing)
        }

        let fields = try await pluginRepository.findFields(pluginId: pluginId)
        guard !fields.isEmpty else {
            throw PluginError.noFieldsDefined
        }

        var results: [PluginTestResult] = []
        let now = Date()

        for postingId in samplePostingIds {
            let posting = try await postingRepository.findById(postingId)
            let fieldValues = try await loadFieldValues(postingId: postingId, fields: fields)
            let (testStatus, errorDetails) = evaluateRules(fields: fields, posting: posting, fieldValues: fieldValues)

            let result = PluginTestResult(
                id: UUID(),
                pluginId: pluginId,
                postingId: postingId,
                status: testStatus,
                errorDetails: errorDetails,
                testedAt: now
            )
            results.append(result)
        }

        // Persist results and transition to TESTING
        try await dbPool.write { [self] db in
            try pluginRepository.deleteTestResultsInTransaction(db: db, pluginId: pluginId)
            for result in results {
                try pluginRepository.insertTestResultInTransaction(db: db, result)
            }
            if plugin.status == .draft {
                var updated = plugin
                updated.status = .testing
                try pluginRepository.updateInTransaction(db: db, &updated)
            }
        }

        return results
    }

    // MARK: - Rule Evaluation Engine

    /// Evaluates plugin field validation rules against a posting's custom field values.
    private func evaluateRules(fields: [PluginField], posting: ServicePosting?, fieldValues: [UUID: String]) -> (PluginTestResultStatus, String?) {
        guard let posting else {
            return (.fail, "Posting not found")
        }

        var errors: [String] = []

        for field in fields {
            guard let rulesJson = field.validationRules,
                  let rulesData = rulesJson.data(using: .utf8),
                  let rules = try? JSONSerialization.jsonObject(with: rulesData) as? [String: Any] else {
                continue // No validation rules → field passes
            }

            // Get the actual custom field value for this posting
            let storedValue = fieldValues[field.id]

            switch field.fieldType {
            case .number:
                let numValue = storedValue.flatMap(Double.init) ?? 0
                if let min = rules["min"] as? Double, numValue < min {
                    errors.append("\(field.fieldName): value \(numValue) below minimum \(min)")
                }
                if let max = rules["max"] as? Double, numValue > max {
                    errors.append("\(field.fieldName): value \(numValue) above maximum \(max)")
                }
            case .text:
                let textValue = storedValue ?? ""
                if let minLength = rules["minLength"] as? Int, textValue.count < minLength {
                    errors.append("\(field.fieldName): value too short (min \(minLength) chars)")
                }
                if let pattern = rules["pattern"] as? String {
                    if textValue.range(of: pattern, options: .regularExpression) == nil {
                        errors.append("\(field.fieldName): value does not match pattern")
                    }
                }
            case .boolean:
                let boolValue = storedValue == "true" || storedValue == "1"
                if let required = rules["required"] as? Bool, required && !boolValue {
                    errors.append("\(field.fieldName): required condition not met")
                }
            case .select:
                let selectValue = storedValue ?? ""
                if let allowedValues = rules["allowedValues"] as? [String] {
                    if !allowedValues.contains(selectValue) {
                        errors.append("\(field.fieldName): '\(selectValue)' not in allowed values")
                    }
                }
            }
        }

        if errors.isEmpty {
            return (.pass, nil)
        } else {
            return (.fail, errors.joined(separator: "; "))
        }
    }

    // MARK: - Live Posting Validation (called by PostingService)

    /// Validates a posting against all ACTIVE plugin rules.
    /// Returns list of validation errors (empty = passes all rules).
    func validatePostingAgainstActivePlugins(_ posting: ServicePosting) async throws -> [String] {
        let activePlugins = try await pluginRepository.findActive()
        var allErrors: [String] = []

        for plugin in activePlugins {
            let fields = try await pluginRepository.findFields(pluginId: plugin.id)
            let fieldValues = try await loadFieldValues(postingId: posting.id, fields: fields)
            let (status, errorDetails) = evaluateRules(fields: fields, posting: posting, fieldValues: fieldValues)
            if status == .fail, let details = errorDetails {
                allErrors.append("[\(plugin.name)] \(details)")
            }
        }

        return allErrors
    }

    // MARK: - Submit for Approval (TESTING → PENDING_APPROVAL)

    func submitForApproval(pluginId: UUID, actorId: UUID) async throws {
        try await requireAdmin(actorId: actorId)

        guard var plugin = try await pluginRepository.findById(pluginId) else {
            throw PluginError.pluginNotFound
        }
        guard plugin.status == .testing else {
            throw PluginError.invalidStatusTransition(from: plugin.status, to: .pendingApproval)
        }

        let testResults = try await pluginRepository.findTestResults(pluginId: pluginId)
        guard !testResults.isEmpty else {
            throw PluginError.noTestResults
        }
        guard testResults.allSatisfy({ $0.status == .pass }) else {
            throw PluginError.testsFailed
        }

        try await dbPool.write { [self] db in
            plugin.status = .pendingApproval
            try pluginRepository.updateInTransaction(db: db, &plugin)
            try auditService.record(
                db: db, actorId: actorId,
                action: "PLUGIN_SUBMITTED_FOR_APPROVAL",
                entityType: "PluginDefinition", entityId: pluginId
            )
        }

        if let ns = notificationService {
            Task {
                try? await ns.send(
                    recipientId: plugin.createdBy,
                    eventType: .pluginApprovalNeeded,
                    postingId: nil,
                    title: "Plugin Submitted",
                    body: "\(plugin.name) is pending approval."
                )
            }
        }
    }

    // MARK: - Approve Step (2 different admins required)

    func approveStep(
        pluginId: UUID,
        approverId: UUID,
        step: Int,
        decision: PluginApprovalDecision,
        notes: String?
    ) async throws {
        try await requireAdmin(actorId: approverId)

        guard var plugin = try await pluginRepository.findById(pluginId) else {
            throw PluginError.pluginNotFound
        }
        guard plugin.status == .pendingApproval else {
            throw PluginError.invalidStatusTransition(from: plugin.status, to: .approved)
        }
        guard step == 1 || step == 2 else {
            throw PluginError.invalidApprovalStep
        }

        let existingApprovals = try await pluginRepository.findApprovals(pluginId: pluginId)

        if step == 2 {
            guard let step1 = existingApprovals.first(where: { $0.step == 1 }) else {
                throw PluginError.step1NotCompleted
            }
            if step1.approverId == approverId {
                throw PluginError.sameApproverBothSteps
            }
        }

        if existingApprovals.contains(where: { $0.step == step }) {
            throw PluginError.stepAlreadyCompleted(step: step)
        }

        let approval = PluginApproval(
            id: UUID(), pluginId: pluginId, approverId: approverId,
            step: step, decision: decision, notes: notes, decidedAt: Date()
        )

        try await dbPool.write { [self] db in
            try pluginRepository.insertApprovalInTransaction(db: db, approval)

            if decision == .rejected {
                plugin.status = .rejected
                try pluginRepository.updateInTransaction(db: db, &plugin)
            } else if step == 2 && decision == .approved {
                plugin.status = .approved
                try pluginRepository.updateInTransaction(db: db, &plugin)
            }

            try auditService.record(
                db: db, actorId: approverId,
                action: "PLUGIN_APPROVAL_STEP_\(step)",
                entityType: "PluginDefinition", entityId: pluginId,
                afterData: "{\"decision\":\"\(decision.rawValue)\",\"step\":\(step)}"
            )
        }

        if let ns = notificationService {
            let eventType: NotificationEventType = decision == .approved ? .pluginApproved : .pluginRejected
            Task {
                try? await ns.send(
                    recipientId: plugin.createdBy,
                    eventType: eventType,
                    postingId: nil,
                    title: decision == .approved ? "Plugin Approved (Step \(step))" : "Plugin Rejected",
                    body: notes ?? "No additional notes."
                )
            }
        }
    }

    // MARK: - Activate (APPROVED → ACTIVE)

    func activate(pluginId: UUID, actorId: UUID) async throws {
        try await requireAdmin(actorId: actorId)

        guard var plugin = try await pluginRepository.findById(pluginId) else {
            throw PluginError.pluginNotFound
        }
        guard plugin.status == .approved else {
            throw PluginError.invalidStatusTransition(from: plugin.status, to: .active)
        }

        try await dbPool.write { [self] db in
            plugin.status = .active
            try pluginRepository.updateInTransaction(db: db, &plugin)
            try auditService.record(
                db: db, actorId: actorId,
                action: "PLUGIN_ACTIVATED",
                entityType: "PluginDefinition", entityId: pluginId
            )
        }
    }

    // MARK: - Posting Field Values

    /// Loads custom field values for a posting, keyed by pluginFieldId.
    private func loadFieldValues(postingId: UUID, fields: [PluginField]) async throws -> [UUID: String] {
        try await dbPool.read { db in
            var values: [UUID: String] = [:]
            for field in fields {
                if let pfv = try PostingFieldValue
                    .filter(PostingFieldValue.Columns.postingId == postingId)
                    .filter(PostingFieldValue.Columns.pluginFieldId == field.id)
                    .fetchOne(db) {
                    values[field.id] = pfv.value
                }
            }
            return values
        }
    }

    /// Sets a custom field value for a posting. Creates or updates.
    /// Admins may update any posting. Coordinators may only update postings they created.
    func setFieldValue(postingId: UUID, pluginFieldId: UUID, value: String, actorId: UUID) async throws {
        guard let userRepo = userRepository,
              let actor = try await userRepo.findById(actorId) else {
            throw PluginError.notAuthorized
        }
        guard actor.role == .admin || actor.role == .coordinator else {
            throw PluginError.notAuthorized
        }
        guard let posting = try await postingRepository.findById(postingId) else {
            throw PluginError.postingNotFound
        }
        if actor.role == .coordinator {
            guard posting.createdBy == actorId else {
                throw PluginError.notAuthorized
            }
        }
        let now = Date()
        try await dbPool.write { db in
            // Upsert: delete existing then insert
            try PostingFieldValue
                .filter(PostingFieldValue.Columns.postingId == postingId)
                .filter(PostingFieldValue.Columns.pluginFieldId == pluginFieldId)
                .deleteAll(db)
            var pfv = PostingFieldValue(
                id: UUID(), postingId: postingId, pluginFieldId: pluginFieldId,
                value: value, createdAt: now, updatedAt: now
            )
            try pfv.insert(db)
        }
    }

    // MARK: - Form Support

    /// Returns all active plugins paired with their fields. Used by posting form to render custom inputs.
    func getActivePluginsWithFields() async throws -> [(plugin: PluginDefinition, fields: [PluginField])] {
        let active = try await pluginRepository.findActive()
        var result: [(PluginDefinition, [PluginField])] = []
        for plugin in active {
            let fields = try await pluginRepository.findFields(pluginId: plugin.id)
            if !fields.isEmpty {
                result.append((plugin, fields))
            }
        }
        return result
    }

    /// Validates a set of field values against plugin field rules without requiring a saved posting.
    /// Returns a list of human-readable error strings (empty = all rules pass).
    func validateFieldValues(fields: [PluginField], values: [UUID: String]) -> [String] {
        var errors: [String] = []
        for field in fields {
            guard let rulesJson = field.validationRules,
                  let rulesData = rulesJson.data(using: .utf8),
                  let rules = try? JSONSerialization.jsonObject(with: rulesData) as? [String: Any] else {
                continue
            }
            let storedValue = values[field.id]
            switch field.fieldType {
            case .number:
                let numValue = storedValue.flatMap(Double.init) ?? 0
                if let min = rules["min"] as? Double, numValue < min {
                    errors.append("\(field.fieldName): value below minimum \(min)")
                }
                if let max = rules["max"] as? Double, numValue > max {
                    errors.append("\(field.fieldName): value above maximum \(max)")
                }
            case .text:
                let textValue = storedValue ?? ""
                if let minLength = rules["minLength"] as? Int, textValue.count < minLength {
                    errors.append("\(field.fieldName): too short (min \(minLength) chars)")
                }
                if let pattern = rules["pattern"] as? String,
                   textValue.range(of: pattern, options: .regularExpression) == nil {
                    errors.append("\(field.fieldName): does not match required pattern")
                }
            case .boolean:
                let boolValue = storedValue == "true" || storedValue == "1"
                if let required = rules["required"] as? Bool, required && !boolValue {
                    errors.append("\(field.fieldName): required condition not met")
                }
            case .select:
                let selectValue = storedValue ?? ""
                if let allowedValues = rules["allowedValues"] as? [String], !allowedValues.contains(selectValue) {
                    errors.append("\(field.fieldName): '\(selectValue)' is not a valid selection")
                }
            }
        }
        return errors
    }

    // MARK: - Read

    func listAll() async throws -> [PluginDefinition] {
        try await pluginRepository.findAll()
    }

    func getPlugin(_ id: UUID) async throws -> PluginDefinition? {
        try await pluginRepository.findById(id)
    }

    func getFields(pluginId: UUID) async throws -> [PluginField] {
        try await pluginRepository.findFields(pluginId: pluginId)
    }

    func getApprovals(pluginId: UUID) async throws -> [PluginApproval] {
        try await pluginRepository.findApprovals(pluginId: pluginId)
    }

    func getTestResults(pluginId: UUID) async throws -> [PluginTestResult] {
        try await pluginRepository.findTestResults(pluginId: pluginId)
    }
}
