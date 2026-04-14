# ForgeFlow Architecture & Design

## Overview

ForgeFlow is an on-device iOS work orchestration platform for field teams. All data is stored locally using GRDB (SQLite). No backend server required.

## Architecture

**Pattern:** MVVM with SwiftUI + @Observable

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    Views     │ ──▶ │  ViewModels  │ ──▶ │   Services   │
│  (SwiftUI)   │     │ (@Observable)│     │  (Sendable)  │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                          ┌───────▼───────┐
                                          │ Repositories  │
                                          │  (GRDB Pool)  │
                                          └───────┬───────┘
                                                  │
                                          ┌───────▼───────┐
                                          │   SQLite DB   │
                                          │  (encrypted)  │
                                          └───────────────┘
```

## GRDB Setup

- `DatabasePool` for concurrent reads, serialized writes
- Foreign keys enabled via `config.foreignKeysEnabled = true`
- 5 sequential migrations (001-005)
- `eraseDatabaseOnSchemaChange = true` in DEBUG
- UUID stored as BLOB via GRDB 6.x Codable encoding
- Optimistic locking via `version` column on mutable entities

## State Machines

### 1. Posting Status
```
DRAFT → OPEN → IN_PROGRESS → COMPLETED
                            → CANCELLED
```
- DRAFT: Created by coordinator, not yet visible
- OPEN: Published, accepting assignments
- IN_PROGRESS: At least one assignment accepted
- COMPLETED: All tasks DONE (auto-transition)
- CANCELLED: Manually cancelled by coordinator/admin

### 2. Task Status
```
NOT_STARTED → IN_PROGRESS → DONE
            → BLOCKED → IN_PROGRESS (unblock)
                      → NOT_STARTED (reset)
```
- BLOCKED requires `blockedComment` (min 10 chars)
- Dependencies: finishToStart — blocked task can't start until dependency is DONE
- Parent DONE requires all subtasks DONE

### 3. Assignment Status
```
INVITED → ACCEPTED
        → DECLINED
```
- OPEN postings: first-accepted-wins, subsequent attempts get "already assigned"
- INVITE_ONLY: accept is idempotent for same technician

### 4. Notification Status
```
PENDING → DELIVERED → SEEN
```
- PENDING: Created during DND quiet hours
- DELIVERED: Outside DND window
- SEEN: User explicitly marked
- Dedup: same (eventType, postingId, recipientId) within 10 min → single notification

### 5. Plugin Status
```
DRAFT → TESTING → PENDING_APPROVAL → APPROVED → ACTIVE
                                    → REJECTED
```
- DRAFT: Created by admin, fields can be added
- TESTING: Plugin tested against sample postings
- PENDING_APPROVAL: Requires 2 different admins to approve
- Same admin cannot approve both steps
- REJECTED: Any step rejection

## File Management Pipeline

```
Upload → Validate Magic Bytes → Check Size (≤250MB)
       → SHA-256 Checksum → Dedup Check
       → Check User Quota (2GB)
       → Compress (JPEG quality 0.7)
       → Generate Thumbnail (200x200)
       → Watermark (if posting.watermarkEnabled)
       → Encrypt Original (AES-256-GCM)
       → Store to Documents/attachments/
       → Chunked Copy (files >50MB via ChunkingService)
```

## Plugin Approval Flow

```
1. Admin creates plugin (DRAFT)
2. Admin adds custom fields (TEXT/NUMBER/BOOLEAN/SELECT)
3. Admin tests plugin against sample postings
4. Plugin transitions to TESTING
5. Admin submits for approval → PENDING_APPROVAL
6. Admin A approves Step 1
7. Admin B approves Step 2 (must be different admin)
8. Plugin → APPROVED
9. Admin activates → ACTIVE
```

## Sync Flow

### Export
1. Select entity types (postings, tasks, assignments)
2. Optional date range filter
3. Generate JSON with manifest
4. Compute SHA-256 checksum
5. Save to Documents/exports/*.forgeflow

### Import
1. Select .forgeflow file
2. Validate manifest checksums
3. Compare incoming records with local by (id, version)
4. Flag version mismatches as conflicts
5. Present side-by-side diff for each conflict
6. User resolves: "Keep Local" or "Accept Incoming"
7. Apply decisions in GRDB transaction

## Background Task Registration

| Task | Identifier | Schedule |
|------|-----------|----------|
| OrphanCleanup | com.forgeflow.orphan-cleanup | Daily (24h) |
| ImageCompression | com.forgeflow.image-compression | On demand |
| CacheEviction | com.forgeflow.cache-eviction | 12 hours |
| FileChunking | com.forgeflow.file-chunking | 6 hours |

All tasks:
- Check `ProcessInfo.processInfo.isLowPowerModeEnabled` before heavy work (BG-02)
- Observe `UIApplication.didReceiveMemoryWarningNotification` to cancel work (BG-03)
- Set `expirationHandler` to save state on system termination

## Adaptive Layout

- iPhone: `TabView` with role-based tabs
- iPad: `NavigationSplitView` with sidebar
- Admin sees: Dashboard, Postings, Calendar, Messaging, Plugins, Sync
- Coordinator sees: Dashboard, Postings, Calendar, Messaging, Sync
- Technician sees: Dashboard, Postings, Calendar, Messaging

## Design System

- Colors from asset catalog (ForgeBlue, SurfacePrimary, etc.)
- Dynamic Type for all text
- Dark Mode support via semantic colors
- 44pt minimum tap targets
- VoiceOver accessibility labels on all interactive elements
- No hardcoded file paths — all use FileManager APIs

## Security Model

Threats are intra-app (privilege escalation, cross-user data access within a shared session). There is no network surface.

**Role trust levels**

| Role | Trust |
|---|---|
| Admin | Full — encrypted originals, user management, storage quotas |
| Coordinator | Elevated — create postings, view assigned technicians |
| Technician | Restricted — only postings they are assigned to |

**Threat matrix**

| ID | Threat | Control |
|---|---|---|
| T-01 | Brute-force login | Account lockout after N failures (AUTH-02); back-off timer |
| T-02 | Credential theft from DB | Argon2 hashing; plaintext never persisted |
| T-03 | Cross-user notification read | `NotificationService` enforces `actorId == userId`; throws `.unauthorized` |
| T-04 | Unauthorized original image access | `AttachmentService.downloadOriginal` admin-role check; AES-256-GCM + Keychain key |
| T-05 | Privilege escalation via role parameter | `AuthService.requireRole` looks up role from DB; client values not trusted |
| T-06 | Cross-user profile mutation | `AuthService.requireSelfOrAdmin` on `toggleBiometric`, `updateDNDSettings`, `getUser` |
| T-07 | File injection via misleading extension | `MagicBytesValidator` checks actual file header (ATT-01) |
| T-08 | Oversized upload / quota abuse | 250 MB hard cap (ATT-02); per-user quota (ATT-04) |
| T-09 | Duplicate file upload | SHA-256 dedup per posting (ATT-08) |
| T-10 | Notification spam | 10-min dedup window per (eventType, postingId, recipientId) (MSG-02) |
| T-11 | Audit log tampering | `audit_entries` is append-only; no UPDATE/DELETE paths in any service |
| T-12 | Race in first-accepted-wins | `DatabasePool` serializes writes; check + insert is atomic |
| T-13 | Task load by unauthenticated actor | `TaskListViewModel` guards on non-nil `currentUserId` before service call |
| T-14 | Malicious sync import | SHA-256 checksum verified; schema validated by GRDB model decoding |
