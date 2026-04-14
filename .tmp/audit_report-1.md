# ForgeFlow Static Audit
Date: 2026-04-14
Reviewer mode: Static-only (no runtime execution)

## 1. Verdict
- Overall conclusion: **Partial Pass**

## 2. Scope and Static Verification Boundary
- Reviewed:
  - Project docs, structure, Xcode project manifest, migrations, models, services, view models, key views, and test sources.
  - Security-critical paths: authentication, role/actor checks, posting/task/assignment/comment/attachment/sync/plugin access controls.
  - Test inventory and static coverage vs prompt-critical risks.
- Not reviewed:
  - Runtime UX behavior, simulator/device behavior, performance, BGTask scheduling behavior under iOS runtime conditions.
  - Real biometric behavior, real file importer/photo picker behavior, iPad split behavior at runtime.
- Intentionally not executed:
  - App launch/build/run, tests, Docker, any external service.
- Manual verification required for:
  - Runtime lock/unlock behavior timing and scene transitions.
  - Real BGTask execution and battery/memory throttling outcomes.
  - Real watermark rendering/decryption UX and large-file resumability under interrupted I/O.

## 3. Repository / Requirement Mapping Summary
- Prompt core goal mapped: on-device iOS orchestration for Administrator/Coordinator/Technician using SwiftUI + GRDB/SQLite, with local auth, assignments/tasks/comments/attachments/notifications/sync/plugins.
- Main implementation areas mapped:
  - Auth/session/lock: `AuthService`, `AppState`, auth views.
  - Core orchestration: `PostingService`, `AssignmentService`, `TaskService`, `CommentService`, `AttachmentService`.
  - Messaging: `NotificationService`, Messaging views/viewmodels.
  - Sync + plugin lifecycle: `SyncService`, `PluginService`, related migrations/models.
  - Persistence and migrations: `DatabaseManager`, migrations `001`-`007`.
  - Tests: Unit/Integration/View suites in `ForgeFlowTests`.

## 4. Section-by-section Review

### 1. Hard Gates
#### 1.1 Documentation and static verifiability
- Conclusion: **Partial Pass**
- Rationale:
  - Startup/run/test instructions exist and are usable.
  - Documentation links in README point to missing files, and project-structure notes are stale (migration count mismatch).
- Evidence:
  - Startup/testing instructions: `README.md:14-155`
  - Missing docs links: `README.md:159-161`
  - Referenced docs directory absent: `docs` missing (filesystem check)
  - Stale migration count text (says 001-005): `README.md:130`; actual migrations include `006` and `007`: `ForgeFlow/Database/DatabaseManager.swift:87-93`
- Manual verification note: Not required for this conclusion.

#### 1.2 Material deviation from prompt
- Conclusion: **Partial Pass**
- Rationale:
  - Repository is clearly centered on the prompt domain and core entities.
  - But some prompt-critical flows are not fully end-to-end (notably plugin custom field capture for live postings, watermark policy flow wiring).
- Evidence:
  - Core domain coverage: `ForgeFlow/Models/*.swift`, `ForgeFlow/Services/*.swift`
  - Plugin field-value persistence added: `ForgeFlow/Database/Migrations/007_PostingFieldValues.swift:4-29`, `ForgeFlow/Models/PostingFieldValue.swift:4-17`
  - Missing end-user capture path for plugin values (no `setFieldValue` call sites): `ForgeFlow/Services/PluginService.swift:410-425`, search usage none outside service

### 2. Delivery Completeness
#### 2.1 Coverage of explicit core requirements
- Conclusion: **Partial Pass**
- Rationale:
  - Implemented: role model, local auth/password rules, biometrics, inactivity lock model, posting/task/assignment/comment/notification/sync/plugin foundations, dedup+DND messaging logic, GRDB persistence.
  - Incomplete/weak: plugin custom field values not wired into posting creation/edit workflow; watermark workflow does not propagate username needed for watermarking/encrypted-original branch; some access-control critical reads remain under-guarded.
- Evidence:
  - Password policy: `ForgeFlow/Services/AuthService.swift:26-32`
  - Lock model: `ForgeFlow/App/AppState.swift:25-57`
  - Notification dedup+DND: `ForgeFlow/Services/NotificationService.swift:31-39`, `:54-58`, `:105-119`
  - Plugin value storage capability only: `ForgeFlow/Services/PluginService.swift:393-425`
  - Watermark branch requires username: `ForgeFlow/Services/AttachmentService.swift:122-133`
  - Upload call sites omit `watermarkUsername`: `ForgeFlow/ViewModels/AttachmentViewModel.swift:55-63`, `ForgeFlow/Views/Attachments/AttachmentUploadView.swift:96-100`, `:122-126`

#### 2.2 End-to-end 0→1 deliverable vs partial/demo
- Conclusion: **Partial Pass**
- Rationale:
  - Full multi-module app structure and sizable test suite are present.
  - Some required subsystems remain partially stubbed (background chunk/compression worker tasks).
- Evidence:
  - Complete structure: `README.md:123-155`
  - Placeholder-like BG handlers:
    - `ForgeFlow/BackgroundTasks/FileChunkingTask.swift:45-47`
    - `ForgeFlow/BackgroundTasks/ImageCompressionTask.swift:36-43`

### 3. Engineering and Architecture Quality
#### 3.1 Module decomposition and structure
- Conclusion: **Pass**
- Rationale:
  - Clear decomposition across App/Models/DB/Services/ViewModels/Views/BackgroundTasks/Utilities.
- Evidence:
  - Structure: `README.md:123-155`
  - Service/repository split visible across `ForgeFlow/Services` and `ForgeFlow/Database/Repositories`.

#### 3.2 Maintainability/extensibility
- Conclusion: **Partial Pass**
- Rationale:
  - Good extension points (plugin lifecycle, sync services, repositories).
  - But security checks are inconsistent due optional actor parameters and unguarded read APIs, increasing future regression risk.
- Evidence:
  - Optional actor auth APIs: `ForgeFlow/Services/TaskService.swift:286-316`, `ForgeFlow/Services/AssignmentService.swift:287-312`, `ForgeFlow/Services/PostingService.swift:303-315`
  - Unguarded read APIs: `ForgeFlow/Services/CommentService.swift:109-115`, `ForgeFlow/Services/AttachmentService.swift:184-186`

### 4. Engineering Details and Professionalism
#### 4.1 Error handling, logging, validation, API design
- Conclusion: **Partial Pass**
- Rationale:
  - Strong validation in several areas (auth/password, attachments magic bytes/size/quota).
  - Weak spots: inconsistent auth enforcement on some reads; heavy use of fire-and-forget `try?` in notification/task background async blocks; test runner argument modes are misleading.
- Evidence:
  - Validation examples: `ForgeFlow/Services/AuthService.swift:26-32`, `ForgeFlow/Services/AttachmentService.swift:56-83`
  - Fire-and-forget suppression examples: `ForgeFlow/Services/TaskService.swift:189-207`, `ForgeFlow/Services/PostingService.swift:285-297`, `ForgeFlow/Services/CommentService.swift:90-97`
  - Test mode script re-runs same full command for all flags: `run_tests.sh:71-89`

#### 4.2 Product-grade vs demo shape
- Conclusion: **Partial Pass**
- Rationale:
  - Overall resembles a real app, not a single-file demo.
  - Remaining stubs and incomplete requirement wiring prevent full product-grade acceptance.
- Evidence:
  - App wiring and dependency graph: `ForgeFlow/App/ForgeFlowApp.swift:18-132`
  - Stub-like BG task bodies: `ForgeFlow/BackgroundTasks/FileChunkingTask.swift:45-49`, `ForgeFlow/BackgroundTasks/ImageCompressionTask.swift:36-43`

### 5. Prompt Understanding and Requirement Fit
#### 5.1 Business goal/semantic fit
- Conclusion: **Partial Pass**
- Rationale:
  - Good fit on core orchestration and local-first architecture.
  - Notable semantic misses: “visible audit note” for first-accepted conflict is not surfaced as assignment audit note/UI field; plugin rule custom values are not captured in posting workflow; watermark policy support path is incomplete in UI->service parameterization.
- Evidence:
  - Conflict logging to audit entries exists: `ForgeFlow/Services/AssignmentService.swift:140-152`
  - `Assignment.auditNote` modeled but never set in accept conflict path: `ForgeFlow/Models/Assignment.swift:12`, `ForgeFlow/Services/AssignmentService.swift:160-170`
  - Plugin field values support not integrated into posting form/viewmodel: `ForgeFlow/ViewModels/PostingFormViewModel.swift:5-71`, `ForgeFlow/Views/Postings/PostingFormView.swift:10-66`, `ForgeFlow/Services/PluginService.swift:410-425`
  - Watermark username not passed: `ForgeFlow/Services/AttachmentService.swift:122-133`, `ForgeFlow/Views/Attachments/AttachmentUploadView.swift:96-100`, `:122-126`

### 6. Aesthetics (frontend)
#### 6.1 Visual/interaction quality
- Conclusion: **Cannot Confirm Statistically**
- Rationale:
  - Static SwiftUI structure suggests coherent hierarchy, spacing, and role-based navigation, but visual fidelity, rendering quality, and interaction feel require runtime/manual inspection.
- Evidence:
  - Main navigation layouts (iPhone/iPad split): `ForgeFlow/Views/MainTabView.swift:50-97`
  - Messaging UI and row status indicators: `ForgeFlow/Views/Messaging/MessagingCenterView.swift:24-87`, `ForgeFlow/Views/Messaging/NotificationRowView.swift:52-71`
- Manual verification note:
  - Verify on iPhone/iPad portrait/landscape/Split View and Dynamic Type sizes.

## 5. Issues / Suggestions (Severity-Rated)

### Blocker / High
1. **High** — Service-layer authorization is inconsistent on read APIs (object/function-level exposure)
- Conclusion: **Fail**
- Evidence:
  - `ForgeFlow/Services/AttachmentService.swift:184-186` (`listAttachments(commentId:)` no actor check)
  - `ForgeFlow/Services/CommentService.swift:109-115` (`listComments(taskId:)`, `getReplies` no actor check)
  - `ForgeFlow/Services/TaskService.swift:306-316` (`listTasksForUser` allows nil `actorId` bypass)
  - Callers omitting actor context: `ForgeFlow/ViewModels/TodoCenterViewModel.swift:41`, `ForgeFlow/ViewModels/CommentListViewModel.swift:32`
- Impact:
  - Cross-user/posting data disclosure risk if these methods are invoked outside intended UI paths.
- Minimum actionable fix:
  - Make `actorId` mandatory for all sensitive read methods; enforce posting/task/comment membership checks uniformly; remove permissive overloads.

2. **High** — Plugin custom-field rules are not delivered end-to-end for live postings
- Conclusion: **Fail**
- Evidence:
  - Storage and setter exist: `ForgeFlow/Services/PluginService.swift:393-425`
  - No non-service call sites of `setFieldValue(...)` in app code (usage search)
  - Posting creation/edit UI has no dynamic plugin field inputs: `ForgeFlow/ViewModels/PostingFormViewModel.swift:5-71`, `ForgeFlow/Views/Postings/PostingFormView.swift:10-66`
- Impact:
  - Administrators can define plugin fields/rules, but live posting workflows cannot reliably provide required field values.
- Minimum actionable fix:
  - Add plugin-field rendering/input in posting form/detail flows and persist via `setFieldValue`; include validation errors surfaced to users before publish.

3. **High** — Watermark policy path is incompletely wired (username not propagated)
- Conclusion: **Fail**
- Evidence:
  - Watermark/encrypted-original branch requires `watermarkUsername`: `ForgeFlow/Services/AttachmentService.swift:122-133`
  - Upload callers omit `watermarkUsername` (defaults nil): `ForgeFlow/ViewModels/AttachmentViewModel.swift:55-63`, `ForgeFlow/Views/Attachments/AttachmentUploadView.swift:96-100`, `:122-126`
- Impact:
  - “Watermarked preview + encrypted original” policy may not activate in normal UI upload flows.
- Minimum actionable fix:
  - Resolve current username from `AppState`/`AuthService` and pass it for watermark-enabled uploads; add tests for watermark-enabled path.

### Medium
4. **Medium** — Background chunk/compression tasks remain placeholder-level
- Conclusion: **Partial Fail**
- Evidence:
  - `ForgeFlow/BackgroundTasks/FileChunkingTask.swift:45-47`
  - `ForgeFlow/BackgroundTasks/ImageCompressionTask.swift:36-43`
- Impact:
  - Prompt requirement that heavy processing runs in BG tasks is only partially met.
- Minimum actionable fix:
  - Implement persisted work queue + resumable job execution in BG handlers (compression/chunking), with cancellation-safe checkpoints.

5. **Medium** — Documentation integrity issues reduce static verifiability
- Conclusion: **Partial Fail**
- Evidence:
  - Broken docs links: `README.md:159-161`
  - Stale migration statement: `README.md:130` vs `ForgeFlow/Database/DatabaseManager.swift:87-93`
- Impact:
  - Reviewers lose confidence in docs-to-code consistency; onboarding friction.
- Minimum actionable fix:
  - Add missing docs or remove links; update migration count/structure docs to match current code.

6. **Medium** — `run_tests.sh` mode flags do not isolate layers as documented
- Conclusion: **Partial Fail**
- Evidence:
  - `run_tests.sh:71-89` executes same `xcodebuild ... test` command for unit/integration/views branches.
- Impact:
  - Static test command docs imply coverage segmentation that script does not provide.
- Minimum actionable fix:
  - Use `-only-testing:` filters per suite or split schemes/test plans; align README claims.

7. **Medium** — “Visible audit note” for first-accepted conflict not persisted on assignment record
- Conclusion: **Partial Fail**
- Evidence:
  - Conflict note is audit-entry text only: `ForgeFlow/Services/AssignmentService.swift:140-152`
  - `Assignment.auditNote` exists but not set in conflict path: `ForgeFlow/Models/Assignment.swift:12`, `ForgeFlow/Services/AssignmentService.swift:160-170`
- Impact:
  - Requirement asks for visible audit note; current implementation has no direct assignment-level field/UI surfacing for blocked acceptance.
- Minimum actionable fix:
  - Persist conflict note to a visible field/path (e.g., assignment/posting conflict log model + UI display).

## 6. Security Review Summary
- **Authentication entry points**: **Pass**
  - Evidence: credential login + lockout + biometrics in `ForgeFlow/Services/AuthService.swift:36-136`; lock-screen integration in `ForgeFlow/Views/Auth/LockScreenView.swift:38-110`.
- **Route-level authorization**: **Partial Pass**
  - Evidence: role-based tabs in `ForgeFlow/Views/MainTabView.swift:38-47`; service checks for many mutations.
  - Gap: UI gating is not sufficient where service reads are unguarded.
- **Object-level authorization**: **Fail**
  - Evidence: unguarded comment/task attachment/comment-thread read paths (`CommentService`/`AttachmentService` methods above).
- **Function-level authorization**: **Fail**
  - Evidence: optional actor parameters allow bypass when omitted (`TaskService.listTasksForUser`, similar optional patterns).
- **Tenant/user data isolation**: **Partial Fail**
  - Evidence: many writes enforce actor role; several reads can bypass actor checks if called without actor.
- **Admin/internal/debug protection**: **Partial Pass**
  - Evidence: plugin/admin operations require admin (`PluginService.requireAdmin`: `ForgeFlow/Services/PluginService.swift:30-39`); sync write operations now require admin/coordinator (`ForgeFlow/Services/SyncService.swift:59-67`, `:77`, `:253`, `:389`).
  - Gap: sync read/list methods (`listExports/listImports/latest*`) have no actor checks: `ForgeFlow/Services/SyncService.swift:559-562`.

## 7. Tests and Logging Review
- **Unit tests**: **Pass (limited scope)**
  - Evidence: unit suites exist for auth/posting/task/notification logic (`ForgeFlowTests/UnitTests/*.swift`).
- **API/integration tests**: **Partial Pass**
  - Evidence: broad integration coverage exists (`ForgeFlowTests/IntegrationTests/*.swift`).
  - Gaps: scarce negative authorization/object-isolation tests for comment/attachment/sync/plugin access boundaries.
- **Logging categories / observability**: **Partial Pass**
  - Evidence: structured audit trail via `AuditService` (`ForgeFlow/Services/AuditService.swift:13-80`), optional SQL trace with redaction (`ForgeFlow/Database/DatabaseManager.swift:23-36`).
  - Gap: many async notification sends suppress errors with `try?` and no diagnostic channel.
- **Sensitive-data leakage risk in logs/responses**: **Partial Pass**
  - Evidence: SQL trace redaction includes password/hash/token/secret fields (`ForgeFlow/Database/DatabaseManager.swift:27-33`); no plain password logging observed.
  - Residual risk: DEBUG keychain fallback stores sensitive material in `UserDefaults` (`ForgeFlow/Utilities/KeychainHelper.swift:27-33`, `:51-54`) — debug-only but still sensitive.

## 8. Test Coverage Assessment (Static Audit)

### 8.1 Test Overview
- Unit tests exist: `ForgeFlowTests/UnitTests/*`.
- Integration tests exist: `ForgeFlowTests/IntegrationTests/*`.
- View tests exist: `ForgeFlowTests/ViewTests/*`.
- Framework: Swift Testing (`import Testing` across test files).
- Test entry docs/commands exist in README and `run_tests.sh`: `README.md:75-100`, `run_tests.sh:71-89`.
- Caveat: script flags are not genuinely isolated test layers (see Issue #6).

### 8.2 Coverage Mapping Table
| Requirement / Risk Point | Mapped Test Case(s) | Key Assertion / Fixture / Mock | Coverage Assessment | Gap | Minimum Test Addition |
|---|---|---|---|---|---|
| Password policy (>=10, >=1 digit) | `ForgeFlowTests/UnitTests/AuthServiceTests.swift:55-77` | `AuthService.validatePassword(...)` expectations | sufficient | None major | Add boundary for exactly 128 chars accepted/rejected above 128 |
| Lockout after repeated failures | `ForgeFlowTests/IntegrationTests/AuthIntegrationTests.swift:79-97` | verifies `status == .locked`, `failedLoginCount == 5` | sufficient | None major | Add lockout expiry recovery case |
| Posting create→publish flow | `ForgeFlowTests/IntegrationTests/PostingIntegrationTests.swift:47-84` | checks DRAFT->OPEN and auto tasks | sufficient | None major | Add unauthorized publish attempt test |
| Assignment idempotency + first-accepted-wins | `ForgeFlowTests/IntegrationTests/AssignmentIntegrationTests.swift:95-122`, `:124-138` | verifies second open accept rejected and invite-only double accept same id | sufficient | “Visible audit note” semantics not asserted | Add assertion for user-visible conflict note path |
| Task state machine + blocked comment/dependencies | `ForgeFlowTests/IntegrationTests/TaskIntegrationTests.swift:69-164`, `TaskVerificationTests.swift:50-208` | validates transitions and dependency enforcement | sufficient | No negative auth checks on task reads | Add unauthorized actor read/update tests |
| Notification dedup + DND + seen states | `ForgeFlowTests/IntegrationTests/NotificationIntegrationTests.swift:39-160`, `:164-228` | dedup window and DND transitions asserted | sufficient | No actor mismatch read test | Add list/get unread with wrong actorId checks |
| Sync export/import/conflict lifecycle | `ForgeFlowTests/IntegrationTests/SyncIntegrationTests.swift:41-99` | export checksum, import record/conflict path | basically covered | No unauthorized role tests | Add coordinator/admin pass + technician fail tests |
| Plugin two-step approval | `ForgeFlowTests/IntegrationTests/PluginIntegrationTests.swift:48-110`, `:114-150` | lifecycle and same-approver rejection tested | basically covered | No tests for live posting field-value validation wiring | Add posting publish validation tests with stored field values |
| Comment/attachment authorization boundaries | No meaningful negative tests found | N/A | missing | Severe risk area under-tested | Add non-participant read/list/create denial tests |
| Tenant/user data isolation for read APIs | No dedicated isolation tests found | N/A | missing | Optional actor bypass risks undetected | Add cross-user access attempt matrix for comments/attachments/tasks/sync lists |

### 8.3 Security Coverage Audit
- Authentication: **Basically covered** (password/lockout/deactivation tests present).
- Route authorization: **Insufficient** (little/no test evidence for role-tab/service boundary interplay).
- Object-level authorization: **Missing/Insufficient** for comments/attachments/task reads.
- Tenant/data isolation: **Missing/Insufficient** dedicated tests.
- Admin/internal protection: **Insufficient** for sync/plugin negative-role paths.

### 8.4 Final Coverage Judgment
- **Partial Pass**
- Covered major happy paths and several business-rule invariants (state machines, idempotency, dedup, DND, plugin approval chain).
- Uncovered security read-boundary/isolation tests mean severe authorization defects could still remain undetected while tests pass.

## 9. Final Notes
- This report is static-only and evidence-based; runtime claims are intentionally avoided.
- Re-review confirms several prior security improvements (notably actor-scoped checks in selected task/posting/attachment/sync paths), but material gaps remain in consistent authorization enforcement and end-to-end plugin/watermark requirement delivery.
