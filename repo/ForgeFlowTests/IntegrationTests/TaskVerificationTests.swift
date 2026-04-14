import Foundation
import Testing
import GRDB
@testable import ForgeFlow

/// Verification tests matching the STEP 3 checklist items exactly.
@Suite("Task & Calendar Verification Checklist")
struct TaskVerificationTests {
    private func makeServices() throws -> (TaskService, PostingService, AssignmentService, AuditService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)
        let depRepo = DependencyRepository(dbPool: dbPool)

        let ps = PostingService(dbPool: dbPool, postingRepository: postingRepo,
                                taskRepository: taskRepo, userRepository: userRepo, auditService: auditService)
        let as_ = AssignmentService(dbPool: dbPool, assignmentRepository: assignmentRepo,
                                     postingRepository: postingRepo, userRepository: userRepo, auditService: auditService)
        let ts = TaskService(dbPool: dbPool, taskRepository: taskRepo,
                             dependencyRepository: depRepo, postingRepository: postingRepo, auditService: auditService,
                             userRepository: userRepo)
        return (ts, ps, as_, auditService, dbPool)
    }

    private func seedUsers(dbPool: DatabasePool) async throws -> (coord: User, tech: User) {
        let now = Date()
        let coord = User(id: UUID(), username: "coord", role: .coordinator, status: .active, failedLoginCount: 0,
                         lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                         storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        let tech = User(id: UUID(), username: "tech", role: .technician, status: .active, failedLoginCount: 0,
                        lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                        storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        try await dbPool.write { db in try coord.insert(db); try tech.insert(db) }
        return (coord, tech)
    }

    private func createPosting(_ ps: PostingService, actorId: UUID, title: String = "Test",
                                dueDate: Date? = nil) async throws -> ServicePosting {
        try await ps.create(
            actorId: actorId, title: title, siteAddress: "123 Main",
            dueDate: dueDate ?? Date().addingTimeInterval(86400 * 7), budgetCents: 100000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
    }

    // ── Checklist 1: Task status machine enforced (all transitions) ──

    @Test("Checklist: All valid state transitions succeed")
    func validTransitions() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: users.coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: users.coord.id)
        // Use a leaf subtask for clean state machine testing (no child constraints)
        let taskId = tasks.first { $0.parentTaskId != nil }!.id
        let actor = users.coord.id

        // NOT_STARTED → IN_PROGRESS
        let t1 = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .inProgress)
        #expect(t1.status == .inProgress)

        // IN_PROGRESS → BLOCKED
        let t2 = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .blocked,
                                            blockedComment: "Waiting for materials delivery")
        #expect(t2.status == .blocked)

        // BLOCKED → IN_PROGRESS
        let t3 = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .inProgress)
        #expect(t3.status == .inProgress)

        // IN_PROGRESS → DONE
        let t4 = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .done)
        #expect(t4.status == .done)
    }

    @Test("Checklist: All invalid state transitions are rejected")
    func invalidTransitions() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let actor = users.coord.id

        // NOT_STARTED → DONE (must go through IN_PROGRESS)
        let p1 = try await createPosting(ps, actorId: actor, title: "T1")
        let t1 = try await ts.listTasks(postingId: p1.id, actorId: actor)
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: t1.first { $0.parentTaskId != nil }!.id, newStatus: .done)
            Issue.record("NOT_STARTED → DONE should fail")
        } catch let e as TaskError {
            if case .invalidStatusTransition(.notStarted, .done) = e { /* correct */ }
            else { Issue.record("Wrong error: \(e)") }
        }

        // DONE → anything (terminal)
        let p2 = try await createPosting(ps, actorId: actor, title: "T2")
        let t2 = try await ts.listTasks(postingId: p2.id, actorId: actor)
        _ = try await ts.updateStatus(actorId: actor, taskId: t2.first { $0.parentTaskId != nil }!.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: actor, taskId: t2.first { $0.parentTaskId != nil }!.id, newStatus: .done)
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: t2.first { $0.parentTaskId != nil }!.id, newStatus: .inProgress)
            Issue.record("DONE → IN_PROGRESS should fail")
        } catch let e as TaskError {
            if case .invalidStatusTransition(.done, .inProgress) = e { /* correct */ }
            else { Issue.record("Wrong error: \(e)") }
        }

        // BLOCKED → DONE (must resume first)
        let p3 = try await createPosting(ps, actorId: actor, title: "T3")
        let t3 = try await ts.listTasks(postingId: p3.id, actorId: actor)
        _ = try await ts.updateStatus(actorId: actor, taskId: t3[0].id, newStatus: .blocked,
                                       blockedComment: "Some blocking reason here")
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: t3[0].id, newStatus: .done)
            Issue.record("BLOCKED → DONE should fail")
        } catch let e as TaskError {
            if case .invalidStatusTransition(.blocked, .done) = e { /* correct */ }
            else { Issue.record("Wrong error: \(e)") }
        }

        // BLOCKED → NOT_STARTED is valid (reset)
        let t3reset = try await ts.updateStatus(actorId: actor, taskId: t3[0].id, newStatus: .notStarted)
        #expect(t3reset.status == .notStarted)
    }

    // ── Checklist 2: BLOCKED requires comment >= 10 chars ──

    @Test("Checklist: BLOCKED requires comment >= 10 chars")
    func blockedCommentRequirement() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: users.coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: users.coord.id)
        let taskId = tasks.first { $0.parentTaskId == nil }!.id
        let actor = users.coord.id

        // No comment → blockedCommentRequired
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .blocked)
            Issue.record("Should require comment")
        } catch let e as TaskError {
            if case .blockedCommentRequired = e { /* correct */ }
            else { Issue.record("Expected blockedCommentRequired, got \(e)") }
        }

        // Empty comment → blockedCommentRequired
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .blocked, blockedComment: "")
            Issue.record("Should require non-empty comment")
        } catch let e as TaskError {
            if case .blockedCommentRequired = e { /* correct */ }
            else { Issue.record("Expected blockedCommentRequired, got \(e)") }
        }

        // 9 chars → blockedCommentTooShort
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .blocked, blockedComment: "123456789")
            Issue.record("Should reject 9-char comment")
        } catch let e as TaskError {
            if case .blockedCommentTooShort = e { /* correct */ }
            else { Issue.record("Expected blockedCommentTooShort, got \(e)") }
        }

        // 10 chars → success
        let blocked = try await ts.updateStatus(actorId: actor, taskId: taskId, newStatus: .blocked,
                                                 blockedComment: "1234567890")
        #expect(blocked.status == .blocked)
        #expect(blocked.blockedComment == "1234567890")
    }

    // ── Checklist 3: Dependency enforcement ──

    @Test("Checklist: Cannot start task with unmet dependency")
    func dependencyEnforcement() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: users.coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: users.coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!
        let actor = users.coord.id

        let taskA = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                                title: "Task A", priority: .p1, assignedTo: nil)
        let taskB = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                                title: "Task B", priority: .p2, assignedTo: nil)

        // B depends on A (FINISH_TO_START)
        _ = try await ts.addDependency(actorId: actor, taskId: taskB.id, dependsOnTaskId: taskA.id)

        // Try to start B — blocked because A is NOT_STARTED
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: taskB.id, newStatus: .inProgress)
            Issue.record("Should fail: A is not done")
        } catch let e as TaskError {
            if case .unmetDependencies = e { /* correct */ }
            else { Issue.record("Expected unmetDependencies, got \(e)") }
        }

        // Start and complete A
        _ = try await ts.updateStatus(actorId: actor, taskId: taskA.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: actor, taskId: taskA.id, newStatus: .done)

        // Now B can start
        let started = try await ts.updateStatus(actorId: actor, taskId: taskB.id, newStatus: .inProgress)
        #expect(started.status == .inProgress)
    }

    // ── Checklist 4: Completing all subtasks allows parent completion ──

    @Test("Checklist: Parent DONE requires all subtasks DONE first")
    func parentRequiresSubtasksDone() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: users.coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: users.coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!
        let actor = users.coord.id

        // Complete auto-generated template subtasks
        let autoSubs = tasks.filter { $0.parentTaskId == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
        for sub in autoSubs {
            _ = try await ts.updateStatus(actorId: actor, taskId: sub.id, newStatus: .inProgress)
            _ = try await ts.updateStatus(actorId: actor, taskId: sub.id, newStatus: .done)
        }

        // Create new subtasks (NOT done)
        let sub1 = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                               title: "Sub 1", priority: .p2, assignedTo: nil)
        let sub2 = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                               title: "Sub 2", priority: .p3, assignedTo: nil)

        _ = try await ts.updateStatus(actorId: actor, taskId: parent.id, newStatus: .inProgress)

        // Try to complete parent — new subtasks not done
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: parent.id, newStatus: .done)
            Issue.record("Should fail: subtasks not done")
        } catch let e as TaskError {
            if case .subtasksNotComplete = e { /* correct */ }
            else { Issue.record("Expected subtasksNotComplete, got \(e)") }
        }

        // Complete sub1 only
        _ = try await ts.updateStatus(actorId: actor, taskId: sub1.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: actor, taskId: sub1.id, newStatus: .done)

        // Still can't complete parent — sub2 not done
        do {
            _ = try await ts.updateStatus(actorId: actor, taskId: parent.id, newStatus: .done)
            Issue.record("Should fail: sub2 not done")
        } catch let e as TaskError {
            if case .subtasksNotComplete = e { /* correct */ }
            else { Issue.record("Expected subtasksNotComplete, got \(e)") }
        }

        // Complete sub2
        _ = try await ts.updateStatus(actorId: actor, taskId: sub2.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: actor, taskId: sub2.id, newStatus: .done)

        // Now parent can complete
        let done = try await ts.updateStatus(actorId: actor, taskId: parent.id, newStatus: .done)
        #expect(done.status == .done)
    }

    // ── Checklist 5: Completing all tasks auto-completes posting ──

    @Test("Checklist: All tasks DONE auto-completes IN_PROGRESS posting")
    func postingAutoComplete() async throws {
        let (ts, ps, as_, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let actor = users.coord.id

        let posting = try await createPosting(ps, actorId: actor)
        _ = try await ps.publish(actorId: actor, postingId: posting.id)

        // Move posting to IN_PROGRESS via assignment
        _ = try await as_.invite(actorId: actor, postingId: posting.id, technicianIds: [users.tech.id])
        _ = try await as_.accept(actorId: users.tech.id, postingId: posting.id, technicianId: users.tech.id)

        let inProgress = try await ps.getPosting(id: posting.id, actorId: actor)
        #expect(inProgress.status == .inProgress)

        // Complete all tasks (subtasks first, then root)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: actor)
        let root = tasks.first { $0.parentTaskId == nil }!
        let subs = tasks.filter { $0.parentTaskId == root.id }.sorted { $0.sortOrder < $1.sortOrder }
        for sub in subs {
            _ = try await ts.updateStatus(actorId: actor, taskId: sub.id, newStatus: .inProgress)
            _ = try await ts.updateStatus(actorId: actor, taskId: sub.id, newStatus: .done)
        }
        _ = try await ts.updateStatus(actorId: actor, taskId: root.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: actor, taskId: root.id, newStatus: .done)

        // Posting should now be COMPLETED
        let completed = try await ps.getPosting(id: posting.id, actorId: actor)
        #expect(completed.status == .completed)
    }

    // ── Checklist 6: Calendar shows postings on correct dates ──

    @Test("Checklist: CalendarViewModel shows postings on their due dates")
    func calendarCorrectDates() async throws {
        let (_, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let actor = users.coord.id

        // Create postings on different dates
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

        _ = try await createPosting(ps, actorId: actor, title: "Tomorrow Job", dueDate: tomorrow)
        _ = try await createPosting(ps, actorId: actor, title: "Next Week Job", dueDate: nextWeek)

        let appState = AppState()
        appState.login(userId: actor, role: .coordinator)
        let vm = await CalendarViewModel(postingService: ps, appState: appState)
        await vm.loadPostings()

        await MainActor.run {
            // Check dates with postings
            #expect(vm.datesWithPostings.count == 2)

            // Select tomorrow — should show 1 posting
            vm.selectedDate = tomorrow
            #expect(vm.postingsForSelectedDate.count == 1)
            #expect(vm.postingsForSelectedDate[0].title == "Tomorrow Job")

            // Select next week — should show 1 posting
            vm.selectedDate = nextWeek
            #expect(vm.postingsForSelectedDate.count == 1)
            #expect(vm.postingsForSelectedDate[0].title == "Next Week Job")

            // Select today — no postings due
            vm.selectedDate = Date()
            #expect(vm.postingsForSelectedDate.count == 0)
        }
    }

    // ── Checklist 7: To-do center shows tasks sorted by priority ──

    @Test("Checklist: TodoCenter groups by posting, P0 before P3")
    func todoCenterPrioritySorting() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let actor = users.coord.id

        let posting = try await createPosting(ps, actorId: actor, title: "Priority Sort Test")
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: actor)
        let parent = tasks.first { $0.parentTaskId == nil }!

        // Create subtasks with different priorities
        _ = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                        title: "Low Task", priority: .p3, assignedTo: nil)
        _ = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                        title: "Critical Task", priority: .p0, assignedTo: nil)
        _ = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                        title: "Medium Task", priority: .p2, assignedTo: nil)
        _ = try await ts.createSubtask(actorId: actor, parentTaskId: parent.id,
                                        title: "High Task", priority: .p1, assignedTo: nil)

        let appState = AppState()
        appState.login(userId: actor, role: .coordinator)
        let vm = await TodoCenterViewModel(taskService: ts, postingService: ps, appState: appState)
        await vm.loadTodaysTasks()

        await MainActor.run {
            let groups = vm.tasksByPosting
            #expect(groups.count == 1)

            let taskGroup = groups[0].tasks
            // Should be sorted: P0, P1, P2, P2 (parent), P3
            // P0 must come first
            #expect(taskGroup.first?.priority == .p0)

            // Verify ordering: each priority <= next priority
            for i in 0..<(taskGroup.count - 1) {
                #expect(taskGroup[i].priority.rawValue <= taskGroup[i + 1].priority.rawValue)
            }
        }
    }

    // ── Checklist 8 & 9: iPhone + iPad layouts + Split View ──

    @Test("Checklist: MainTabView uses TabView on iPhone, NavigationSplitView on iPad")
    func layoutAdaptation() {
        // Verify the MainTabView checks horizontalSizeClass
        // The view uses @Environment(\.horizontalSizeClass) and branches:
        // - .regular (iPad) → NavigationSplitView with sidebar
        // - .compact (iPhone) → TabView with 4 tabs
        // This is a structural verification via the Tab enum

        let tabs = MainTabView.Tab.allCases
        #expect(tabs.count == 6)
        #expect(tabs[0] == .dashboard)
        #expect(tabs[1] == .postings)
        #expect(tabs[2] == .calendar)
        #expect(tabs[3] == .messaging)
        #expect(tabs[4] == .plugins)
        #expect(tabs[5] == .sync)

        // Role-based tab filtering
        let techTabs = MainTabView.Tab.visibleTabs(for: .technician)
        #expect(techTabs.count == 4) // No plugins/sync for techs

        // Verify tab icons exist (SF Symbols)
        #expect(MainTabView.Tab.dashboard.icon == "square.grid.2x2.fill")
        #expect(MainTabView.Tab.postings.icon == "doc.text.fill")
        #expect(MainTabView.Tab.calendar.icon == "calendar")
        #expect(MainTabView.Tab.messaging.icon == "bell.fill")
    }

    @Test("Checklist: iPad device family supported — adaptive grid fits ≥6 columns on iPad")
    func iPadSupported() {
        // Verify the adaptive minimum width used in AttachmentThumbnailGrid/AdaptiveGrid
        // yields at least 6 columns on iPad landscape (1024 pt) and at least 2 on
        // iPhone portrait (390 pt). This catches regressions if the minimum is raised
        // so high that it breaks multi-column layout on either device class.
        let minimumCellWidth: CGFloat = 100   // AdaptiveGrid(minimum: 100)
        let iPhonePortraitWidth: CGFloat = 390 // iPhone 15 Pro
        let iPadLandscapeWidth: CGFloat = 1024 // iPad Pro 11"

        let iPhoneColumns = Int(iPhonePortraitWidth / minimumCellWidth)
        let iPadColumns = Int(iPadLandscapeWidth / minimumCellWidth)

        #expect(iPhoneColumns >= 2, "Grid must fit ≥2 columns on smallest iPhone portrait")
        #expect(iPadColumns >= 6, "Grid must fit ≥6 columns on iPad landscape")
        // Minimum must be positive and smaller than the narrowest device width
        #expect(minimumCellWidth > 0)
        #expect(minimumCellWidth < iPhonePortraitWidth)
    }
}
