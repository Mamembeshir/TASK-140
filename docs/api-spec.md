# ForgeFlow Internal API Specification

## Models

### User
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| username | String | Unique, 3-100 chars |
| role | Role | ADMIN, COORDINATOR, TECHNICIAN |
| status | UserStatus | ACTIVE, LOCKED, DEACTIVATED |
| failedLoginCount | Int | Reset on success |
| lockedUntil | Date? | 15 min lockout after 5 failures |
| biometricEnabled | Bool | Requires password auth first |
| dndStartTime | String? | "HH:mm" format |
| dndEndTime | String? | "HH:mm" format |
| storageQuotaBytes | Int | Default 2 GB |
| version | Int | Optimistic locking |

### ServicePosting
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| title | String | Required |
| siteAddress | String | Required |
| dueDate | Date | Must be future |
| budgetCapCents | Int | Stored as cents |
| status | PostingStatus | DRAFT → OPEN → IN_PROGRESS → COMPLETED/CANCELLED |
| acceptanceMode | AcceptanceMode | INVITE_ONLY or OPEN |
| createdBy | UUID | FK → users |
| watermarkEnabled | Bool | Stamps preview images |
| version | Int | Optimistic locking |

### ForgeTask
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| postingId | UUID | FK → service_postings (CASCADE) |
| parentTaskId | UUID? | FK → tasks (self-referential) |
| title | String | Required |
| priority | Priority | P0-P3 |
| status | TaskStatus | NOT_STARTED → IN_PROGRESS → DONE/BLOCKED |
| blockedComment | String? | Required when status = BLOCKED |
| assignedTo | UUID? | FK → users |
| version | Int | Optimistic locking |

### Assignment
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| postingId | UUID | FK → service_postings |
| technicianId | UUID | FK → users |
| status | AssignmentStatus | INVITED → ACCEPTED/DECLINED |
| acceptedAt | Date? | Set on accept |
| Unique | (postingId, technicianId) | |

### ForgeNotification
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| recipientId | UUID | FK → users |
| eventType | NotificationEventType | 10 event types |
| status | NotificationStatus | PENDING → DELIVERED → SEEN |

### PluginDefinition
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| name | String | Required |
| status | PluginStatus | DRAFT → TESTING → PENDING_APPROVAL → APPROVED → ACTIVE |
| createdBy | UUID | FK → users |
| version | Int | Optimistic locking |

### PluginField
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| pluginId | UUID | FK → plugin_definitions (CASCADE) |
| fieldName | String | Required |
| fieldType | PluginFieldType | TEXT, NUMBER, BOOLEAN, SELECT |
| unit | String? | e.g., "mm", "headers" |
| validationRules | String? | JSON |

### PluginApproval
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| pluginId | UUID | FK → plugin_definitions |
| approverId | UUID | FK → users |
| step | Int | 1 or 2 |
| decision | PluginApprovalDecision | APPROVED or REJECTED |

### SyncExport / SyncImport
Export generates .forgeflow ZIP with JSON + manifest + SHA-256 checksums.
Import validates checksums, detects version conflicts, supports per-record resolution.

---

## Repositories

All repositories follow the pattern: `final class XRepository: Sendable` with `DatabasePool` dependency.

| Repository | Key Methods |
|-----------|-------------|
| UserRepository | findById, findByUsername, insert, update |
| PostingRepository | findById, findAll, findByStatus, insert, updateWithLocking |
| TaskRepository | findById, findByPosting, insert, updateWithLocking |
| AssignmentRepository | findByPostingAndTechnician, insertOrIgnore, updateWithLocking |
| CommentRepository | findByPosting, insert |
| AttachmentRepository | findByPosting, insert, sumStorageForUser |
| NotificationRepository | findByRecipient, findDuplicate, countUnread, insertInTransaction, updateStatusInTransaction |
| PluginRepository | findById, findAll, findFields, insertInTransaction, updateInTransaction, findApprovals, insertApprovalInTransaction |
| SyncRepository | findAllExports, findAllImports, insertExport, insertImport, updateImport |

---

## Services

| Service | Key Methods |
|---------|-------------|
| AuthService | login, createUser, validatePassword, getUser, updateDNDSettings |
| PostingService | create, publish, cancel, listAll, listForRole |
| AssignmentService | invite, accept, decline |
| TaskService | create, updateStatus, addDependency |
| CommentService | create, listByPosting |
| AttachmentService | upload (magic bytes, SHA-256, quota, compression, watermark, chunking) |
| NotificationService | send (dedup + DND), markSeen, bulkMarkSeen, releaseDNDHeld |
| PluginService | create, addField, testPlugin, submitForApproval, approveStep (2-admin), activate |
| SyncService | export (JSON + SHA-256), importFile (validate + conflict detect), resolveConflicts |
| AuditService | record (append-only audit trail) |

---

## ViewModels

All ViewModels use `@Observable` pattern with async load/action methods.

| ViewModel | Responsibilities |
|-----------|-----------------|
| AuthViewModel | Login flow, biometric, lockout |
| PostingListViewModel | List/filter postings by role |
| PostingFormViewModel | Create/edit posting with validation |
| PostingDetailViewModel | Detail + publish/cancel actions |
| TaskListViewModel | Group tasks by posting, dependency display |
| CalendarViewModel | Date-based posting display |
| CommentListViewModel | Threaded comments with inline images |
| MessagingCenterViewModel | Notification inbox with live updates |
| PluginListViewModel | List plugins, create new |
| PluginEditorViewModel | Edit fields, submit for approval |
| PluginTestViewModel | Select postings, run tests |
| PluginApprovalViewModel | 2-step approval workflow |
| SyncViewModel | Export/import with conflict resolution |
