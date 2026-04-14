import Foundation
import GRDB

enum Seeder {
    /// Seeds demo data on first launch (debug builds only).
    static func seedIfNeeded(dbPool: DatabasePool) async throws {
        let userCount = try await dbPool.read { db in
            try User.fetchCount(db)
        }
        guard userCount == 0 else { return }

        let now = Date()

        // MARK: - Users

        let adminId = UUID()
        let coordId = UUID()
        let tech1Id = UUID()
        let tech2Id = UUID()

        let users: [(UUID, String, String, Role)] = [
            (adminId, "admin", "ForgeFlow1", .admin),
            (coordId, "coord1", "Coordinator1", .coordinator),
            (tech1Id, "tech1", "Technician1", .technician),
            (tech2Id, "tech2", "Technician2", .technician),
        ]

        for (id, _, password, _) in users {
            let hash = PasswordHasher.hash(password)
            try KeychainHelper.save(
                data: hash.data(using: .utf8)!,
                forKey: "forgeflow.password.\(id.uuidString)"
            )
        }

        // MARK: - Postings

        let postingOpen1Id = UUID()
        let postingOpen2Id = UUID()
        let postingIPId = UUID()
        let postingCompId = UUID()
        let postingDraftId = UUID()

        // MARK: - Tasks

        let task1Id = UUID(), task2Id = UUID(), task3Id = UUID()
        let task4Id = UUID(), task5Id = UUID(), task6Id = UUID()
        let task7Id = UUID(), task8Id = UUID(), task9Id = UUID()
        let task10Id = UUID()

        // MARK: - Plugins

        let pluginActiveId = UUID()
        let pluginPendingId = UUID()

        try await dbPool.write { db in
            // Users
            for (id, username, _, role) in users {
                let user = User(
                    id: id, username: username, role: role, status: .active,
                    failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
                    dndStartTime: nil, dndEndTime: nil,
                    storageQuotaBytes: 2_147_483_648,
                    version: 1, createdAt: now, updatedAt: now
                )
                try user.insert(db)
            }

            // Postings
            let postings: [(UUID, String, String, PostingStatus, AcceptanceMode)] = [
                (postingOpen1Id, "HVAC Repair — Downtown Office", "500 Commerce St", .open, .inviteOnly),
                (postingOpen2Id, "Electrical Panel Upgrade", "200 Industrial Blvd", .open, .open),
                (postingIPId, "Plumbing Inspection", "300 Oak Lane", .inProgress, .open),
                (postingCompId, "Fire Alarm Certification", "400 Safety Dr", .completed, .inviteOnly),
                (postingDraftId, "Roof Assessment (Draft)", "600 Heights Ave", .draft, .open),
            ]
            for (id, title, addr, status, mode) in postings {
                var p = ServicePosting(
                    id: id, title: title, siteAddress: addr,
                    dueDate: Date().addingTimeInterval(Double.random(in: 1...14) * 86400),
                    budgetCapCents: Int.random(in: 5000...100000),
                    status: status, acceptanceMode: mode,
                    createdBy: coordId, watermarkEnabled: id == postingOpen1Id,
                    version: 1, createdAt: now, updatedAt: now
                )
                try p.insert(db)
            }

            // Assignments — invite 2 techs to invite-only posting
            var inv1 = Assignment(
                id: UUID(), postingId: postingOpen1Id, technicianId: tech1Id,
                status: .invited, acceptedAt: nil, auditNote: nil,
                version: 1, createdAt: now, updatedAt: now
            )
            try inv1.insert(db)

            var inv2 = Assignment(
                id: UUID(), postingId: postingOpen1Id, technicianId: tech2Id,
                status: .invited, acceptedAt: nil, auditNote: nil,
                version: 1, createdAt: now, updatedAt: now
            )
            try inv2.insert(db)

            // Assignment for in-progress posting
            var accAssign = Assignment(
                id: UUID(), postingId: postingIPId, technicianId: tech1Id,
                status: .accepted, acceptedAt: now, auditNote: nil,
                version: 1, createdAt: now, updatedAt: now
            )
            try accAssign.insert(db)

            // Tasks for in-progress posting (mix of statuses, deps, blocked)
            let tasks: [(UUID, UUID, String, Priority, TaskStatus, UUID?, String?)] = [
                (task1Id, postingIPId, "Site inspection", .p0, .done, tech1Id, nil),
                (task2Id, postingIPId, "Pipe assessment", .p1, .inProgress, tech1Id, nil),
                (task3Id, postingIPId, "Replace fixtures", .p2, .notStarted, tech1Id, nil),
                (task4Id, postingIPId, "Final walkthrough", .p3, .notStarted, nil, nil),
                (task5Id, postingIPId, "Document findings", .p1, .blocked, tech1Id, "Waiting for access to utility room"),
                (task6Id, postingOpen2Id, "Panel removal", .p0, .notStarted, nil, nil),
                (task7Id, postingOpen2Id, "Wire new panel", .p1, .notStarted, nil, nil),
                (task8Id, postingCompId, "Test alarms", .p0, .done, tech1Id, nil),
                (task9Id, postingCompId, "Certify report", .p1, .done, tech1Id, nil),
                (task10Id, postingIPId, "Order parts", .p2, .notStarted, nil, nil),
            ]
            for (id, postingId, title, priority, status, assignedTo, blockedComment) in tasks {
                var t = ForgeTask(
                    id: id, postingId: postingId, parentTaskId: nil,
                    title: title, taskDescription: nil,
                    priority: priority, status: status,
                    blockedComment: blockedComment,
                    assignedTo: assignedTo, sortOrder: 0,
                    version: 1, createdAt: now, updatedAt: now
                )
                try t.insert(db)
            }

            // Dependencies: task3 depends on task2, task7 depends on task6
            var dep1 = Dependency(
                id: UUID(), taskId: task3Id, dependsOnTaskId: task2Id,
                type: .finishToStart
            )
            try dep1.insert(db)

            var dep2 = Dependency(
                id: UUID(), taskId: task7Id, dependsOnTaskId: task6Id,
                type: .finishToStart
            )
            try dep2.insert(db)

            // Comments
            let comments: [(UUID, String, UUID)] = [
                (postingIPId, "Initial inspection looks good, proceeding with assessment.", tech1Id),
                (postingIPId, "Blocked on utility room — contacted building manager.", tech1Id),
                (postingIPId, "Parts list attached, awaiting approval.", tech1Id),
                (postingCompId, "All alarms tested and certified.", tech1Id),
                (postingOpen2Id, "Panel specs confirmed with vendor.", coordId),
            ]
            for (postingId, text, authorId) in comments {
                var c = Comment(
                    id: UUID(), postingId: postingId, taskId: nil,
                    authorId: authorId, body: text,
                    parentCommentId: nil, createdAt: now
                )
                try c.insert(db)
            }

            // Notifications (mix of statuses)
            let notifications: [(UUID, NotificationEventType, String, String, NotificationStatus)] = [
                (tech1Id, .assignmentInvited, "New Invitation", "You've been invited to HVAC Repair", .delivered),
                (tech2Id, .assignmentInvited, "New Invitation", "You've been invited to HVAC Repair", .delivered),
                (coordId, .assignmentAccepted, "Assignment Accepted", "tech1 accepted Plumbing Inspection", .seen),
                (tech1Id, .taskStatusChanged, "Task Update", "Site inspection marked as done", .seen),
                (coordId, .taskBlocked, "Task Blocked", "Document findings is blocked", .delivered),
                (tech1Id, .commentAdded, "New Comment", "New comment on Plumbing Inspection", .pending),
                (coordId, .postingCompleted, "Posting Completed", "Fire Alarm Certification completed", .seen),
                (tech1Id, .pluginApprovalNeeded, "Approval Needed", "PCIe Checker needs review", .delivered),
            ]
            for (recipientId, eventType, title, body, status) in notifications {
                var n = ForgeNotification(
                    id: UUID(), recipientId: recipientId,
                    eventType: eventType, postingId: nil,
                    title: title, body: body, status: status,
                    createdAt: now, updatedAt: now
                )
                try n.insert(db)
            }

            // MARK: - Plugins

            // Active plugin with 3 fields
            var activePlugin = PluginDefinition(
                id: pluginActiveId, name: "Hardware Compatibility Checker",
                description: "Validates hardware specs against requirements",
                category: "Hardware", status: .active, createdBy: adminId,
                version: 3, createdAt: now, updatedAt: now
            )
            try activePlugin.insert(db)

            let activeFields: [(String, PluginFieldType, String?)] = [
                ("ARGB Header Count", .number, "headers"),
                ("PCIe Generation", .select, nil),
                ("Cooler Height (mm)", .number, "mm"),
            ]
            for (i, (name, type, unit)) in activeFields.enumerated() {
                var f = PluginField(
                    id: UUID(), pluginId: pluginActiveId,
                    fieldName: name, fieldType: type, unit: unit,
                    validationRules: nil, sortOrder: i, createdAt: now
                )
                try f.insert(db)
            }

            // Pending approval plugin with 1 approval step done
            var pendingPlugin = PluginDefinition(
                id: pluginPendingId, name: "Safety Compliance Check",
                description: "Validates safety gear requirements",
                category: "Safety", status: .pendingApproval, createdBy: adminId,
                version: 2, createdAt: now, updatedAt: now
            )
            try pendingPlugin.insert(db)

            var pendingField = PluginField(
                id: UUID(), pluginId: pluginPendingId,
                fieldName: "Hard Hat Required", fieldType: .boolean, unit: nil,
                validationRules: nil, sortOrder: 0, createdAt: now
            )
            try pendingField.insert(db)

            var approval1 = PluginApproval(
                id: UUID(), pluginId: pluginPendingId,
                approverId: adminId, step: 1, decision: .approved,
                notes: "Step 1 approved — needs second review.", decidedAt: now
            )
            try approval1.insert(db)
        }
    }
}
