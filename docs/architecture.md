# ForgeFlow — Architecture Overview

## Summary

ForgeFlow is a fully on-device iOS work-orchestration platform. There is no backend server, no cloud sync, and no network dependency at runtime. All persistence, business logic, and security enforcement run inside a single app process backed by a local SQLite database (via GRDB).

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI Views  (Views/, ViewModels/)                        │
│  @Observable ViewModels — thin; delegate all logic down      │
├─────────────────────────────────────────────────────────────┤
│  Service Layer  (Services/)                                  │
│  Business rules, authorization checks, audit logging         │
├─────────────────────────────────────────────────────────────┤
│  Repository Layer  (Database/Repositories/)                  │
│  Pure GRDB queries; no business logic                        │
├─────────────────────────────────────────────────────────────┤
│  SQLite via GRDB  (DatabasePool, 7 migrations)               │
│  Foreign keys ON, write-serialized pool                      │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Single `DatabasePool` per process | Write-serializes all mutations; enables atomic check-then-insert without extra locking (used by `AssignmentService.accept`) |
| Services own all authorization | Views and ViewModels never perform role or ownership checks; they call a service and handle errors |
| Append-only audit log | `AuditService.record` writes to `audit_entries`; no update/delete on that table |
| AES-256-GCM watermark originals | `AttachmentEncryptor` uses HKDF-derived per-file keys backed by a Keychain master key; only `AttachmentService.downloadOriginal` (admin-only) exposes plaintext |
| 7 sequential migrations | Each migration is idempotent and named `NNN_*`; `DatabaseMigrator` tracks applied migrations in `grdb_migrations` |

## Services

| Service | Responsibility |
|---|---|
| `AuthService` | Login, lockout (AUTH-02/03), role management, biometric toggle, DND settings |
| `PostingService` | Service-posting lifecycle (DRAFT → OPEN → IN_PROGRESS → COMPLETED) |
| `AssignmentService` | Invite/accept/decline with first-accepted-wins for OPEN mode |
| `TaskService` | Task/subtask CRUD, status machine, dependency enforcement |
| `CommentService` | Threaded comments on postings/tasks |
| `AttachmentService` | Upload pipeline (validation, checksum, compression, watermark), managed download/export |
| `NotificationService` | Dedup (MSG-02), DND hold/release (MSG-04), actor-bound read/mark |
| `PluginService` | Two-step plugin approval, field schema management |
| `SyncService` | JSON export/import for offline data transfer between devices |
| `AuditService` | Append-only audit record writer |

## Schema

Seven sequential migrations create 17 tables:

```
001  users, audit_entries, sync_exports, sync_imports
002  service_postings, assignments, tasks, dependencies
003  comments, attachments
004  notifications, connector_definitions
005  plugin_definitions, plugin_fields, plugin_test_results, plugin_approvals
006  (index only — assignments covering index for first-accepted-wins)
007  posting_field_values
```

## Authentication Flow

```
Login attempt
  → rate-limit / lockout check (AUTH-02)
  → Argon2 hash verify
  → on success: reset failedLoginCount, issue session token (AUTH-03)
  → biometric re-auth on foreground (BiometricHelper)
```

## Attachment Pipeline

```
Upload: magic-bytes → size ≤250 MB → SHA-256 dedup → quota → compress → thumbnail
        → watermark (AES-256-GCM encrypt original) → chunked write → DB record + audit

Download (watermarked preview): service access check → read file → audit FILE_DOWNLOADED
Download original (admin only): role check → read .enc → AES-256-GCM decrypt → audit ORIGINAL_ACCESSED
```

## Notification Pipeline

```
send()  → dedup window (10 min, MSG-02) → DND check → PENDING or DELIVERED → insert
release → on foreground/timer: PENDING → DELIVERED for expired DND windows (MSG-04)
read    → actor must equal recipient (NotificationService enforces at service boundary)
```
