# ForgeFlow — Requirements Traceability Matrix

Maps requirement codes referenced in source comments to the implementing file(s) and test(s) that verify each requirement.

## Attachment Requirements (ATT)

| ID | Requirement | Implementation | Test |
|---|---|---|---|
| ATT-01 | File type validated via magic bytes, not extension | `MagicBytesValidator.detectMimeType` · `AttachmentService.upload` | `AttachmentServiceTests` — invalid magic bytes throws |
| ATT-02 | File size ≤ 250 MB | `AttachmentService.upload` (size guard) | `AttachmentServiceTests` — oversized file throws `.fileTooLarge` |
| ATT-03 | Images compressed and thumbnail generated on upload | `ImageCompressor`, `ThumbnailGenerator` · `AttachmentService.upload` | `AttachmentServiceTests` — thumbnail path set for image upload |
| ATT-04 | Per-user storage quota enforced | `FileQuotaManager.checkQuota` · `AttachmentService.upload` | `AttachmentServiceTests` — quota exceeded throws |
| ATT-06 | Large files (> 50 MB) copied in chunks | `ChunkingService.copyInChunks` · `AttachmentService.upload` | `AttachmentServiceTests` — chunked copy path taken above threshold |
| ATT-07 | Watermarked images encrypt original with AES-256-GCM | `AttachmentEncryptor.encrypt/decrypt` · `AttachmentService.upload` / `downloadOriginal` | `AttachmentServiceTests` — original encrypted path set when watermark enabled |
| ATT-08 | SHA-256 checksum computed and duplicate uploads rejected | `HashValidator.sha256Hex` · `AttachmentService.upload` | `AttachmentServiceTests` — duplicate file throws `.duplicateFile` |
| ATT-DL | Download/export routes through service (access check + audit) | `AttachmentService.downloadAttachment` / `downloadOriginal` | `AttachmentServiceTests` — download audited; unauthorized actor throws |

## Authentication Requirements (AUTH)

| ID | Requirement | Implementation | Test |
|---|---|---|---|
| AUTH-02 | Account lockout after repeated failed login attempts; counter not incremented while locked | `AuthService.login` — lockout check, counter guard | `AuthServiceTests` — lockout after N failures; locked account does not increment count |
| AUTH-03 | Successful login resets lockout state | `AuthService.login` — reset on success | `AuthServiceTests` — failedLoginCount reset after valid credential |

## Messaging / Notification Requirements (MSG)

| ID | Requirement | Implementation | Test |
|---|---|---|---|
| MSG-02 | Dedup: skip identical (eventType, postingId, recipientId) within 10 minutes | `NotificationService.send` — `findDuplicate` check | `NotificationServiceTests` — duplicate within window returns nil |
| MSG-04 | DND: notifications held as PENDING during DND window; released on foreground/timer | `NotificationService.send` / `releaseDNDHeld` | `NotificationIntegrationTests` — DND hold and release |
| MSG-06 | Email and SMS connectors seeded but disabled | `MessagingSchemaMigration` — INSERT with `isEnabled=0` | `IntegrationTests.connectorsSeededByMigration` — count=2, enabled=0 |
| MSG-07 | Assignment acceptance triggers coordinator notification | `AssignmentService.accept` — `notificationService.send` call | `NotificationIntegrationTests.assignmentAcceptedNotifiesCoordinator` |

## Assignment Requirements

| Requirement | Implementation | Test |
|---|---|---|
| First-accepted-wins (OPEN mode) | `AssignmentService.accept` — atomic check+insert within `dbPool.write` | `AssignmentIntegrationTests` — concurrent accept, only first wins |
| Idempotent re-accept (same technician) | `AssignmentService.accept` — early `.success(existing)` if `technicianId` matches | `AssignmentIntegrationTests` — re-accept returns existing assignment |
| Invite-only gating | `AssignmentService.accept` — `requireSelfOrAdmin` + invited-only check | `AssignmentIntegrationTests` — uninvited technician throws `.notInvited` |

## Task Requirements

| Requirement | Implementation | Test |
|---|---|---|
| Task status machine | `TaskService.updateStatus` — transition validation | `TaskVerificationTests` — all valid/invalid transitions |
| Subtask creation | `TaskService.createSubtask` — parent link + posting scope | `TaskVerificationTests` — subtask attached to parent |
| Dependency enforcement | `DependencyRepository` + `TaskService` — blocks status advance | `TaskVerificationTests` — blocked task cannot advance |
| Actor-bound task load | `TaskListViewModel.loadTasks` — `guard let actorId` before service call | Build-time: non-optional `actorId` passed to `listTasks(postingId:actorId:)` |

## Schema / Migration Requirements

| Requirement | Implementation | Test |
|---|---|---|
| All 17 tables created by 7 migrations | `DatabaseManager.migrator` registers all 7 migrations | `IntegrationTests.allExpectedTablesExistAfterMigration` |
| Foreign keys enforced | `DatabasePool` configured with `foreignKeysEnabled = true` | `IntegrationTests.foreignKeyEnforcementPreventsOrphanedAttachment` |
| Covering index on assignments for first-accepted-wins | `006_AssignmentConstraints` — `idx_assignments_posting_status` | Schema review |
