# ForgeFlow Full Re-Verification of Previously Reported Issues
Date: 2026-04-14
Mode: Static-only (no runtime execution)

## 1. Overall Re-Verification Verdict
- Previously reported issues reviewed: **8**
  - 7 items from prior **Issues / Suggestions** section
  - 1 additional security gap explicitly called out in prior **Security Review Summary** (sync read/list actor checks)
- Current status summary:
  - **Fixed:** 8
  - **Partially Fixed:** 0
  - **Not Fixed:** 0

## 2. Issue-by-Issue Status (From Previous Report)

### Issue A (High)
**Title:** Service-layer authorization inconsistent on read APIs (object/function-level exposure)
- Previous evidence referenced:
  - `AttachmentService.listAttachments(commentId:)` unguarded
  - `CommentService.listComments(taskId:)` / `getReplies` unguarded
  - `TaskService.listTasksForUser` nil-actor bypass
- **Current status: Fixed**
- Fresh evidence:
  - `AttachmentService.listAttachments(commentId:..., postingId:..., actorId:...)` enforces access: `ForgeFlow/Services/AttachmentService.swift:184-186`
  - `CommentService.listComments(taskId:..., postingId:..., actorId:...)` and `getReplies(commentId:..., actorId:...)` enforce access: `ForgeFlow/Services/CommentService.swift:109-119`
  - `TaskService.listTasksForUser(userId:actorId:)` requires actor context and enforces authorization: `ForgeFlow/Services/TaskService.swift:306-317`
  - Caller paths now pass actor context:
    - `ForgeFlow/ViewModels/TodoCenterViewModel.swift:41`
    - `ForgeFlow/ViewModels/CommentListViewModel.swift:67`

### Issue B (High)
**Title:** Plugin custom-field rules not delivered end-to-end for live postings
- Previous evidence referenced:
  - `setFieldValue(...)` existed but no call sites
  - posting form lacked dynamic plugin-field inputs
- **Current status: Fixed**
- Fresh evidence:
  - Active plugin fields loaded: `ForgeFlow/ViewModels/PostingFormViewModel.swift:50-54`
  - Dynamic plugin fields rendered in posting form: `ForgeFlow/Views/Postings/PostingFormView.swift:38-44`, `:88-107`
  - Values persisted via `setFieldValue(...)`: `ForgeFlow/ViewModels/PostingFormViewModel.swift:75-83`
  - Setter implementation remains present: `ForgeFlow/Services/PluginService.swift:422-437`

### Issue C (High)
**Title:** Watermark policy path incompletely wired (username not propagated)
- Previous evidence referenced:
  - upload call sites omitted `watermarkUsername`
- **Current status: Fixed**
- Fresh evidence:
  - Upload callers pass username when watermark is enabled:
    - `ForgeFlow/ViewModels/AttachmentViewModel.swift:61-63`
    - `ForgeFlow/Views/Attachments/AttachmentUploadView.swift:99-100`
    - `ForgeFlow/Views/Attachments/AttachmentUploadView.swift:126-127`
  - Posting watermark policy now propagates through navigation/upload flows:
    - `ForgeFlow/Views/Postings/PostingDetailView.swift:134-137`, `:152-158`, `:172-177`
    - `ForgeFlow/Views/Attachments/AttachmentThumbnailGrid.swift:82-87`
    - `ForgeFlow/Views/Comments/CommentFormView.swift:72-78`

### Issue D (Medium)
**Title:** Background chunk/compression tasks remained placeholder-level
- Previous evidence referenced:
  - placeholder-like handler bodies in chunk/compression BG tasks
- **Current status: Fixed**
- Fresh evidence:
  - File chunking task now has persistent queue, scheduling, cancellation/resume logic: `ForgeFlow/BackgroundTasks/FileChunkingTask.swift:20-137`
  - Image compression task now has persistent queue and processing loop with checkpoint behavior: `ForgeFlow/BackgroundTasks/ImageCompressionTask.swift:20-120`
- Boundary note:
  - Runtime BGTask execution characteristics remain manual-verification-only.

### Issue E (Medium)
**Title:** Documentation integrity issues reduced static verifiability
- Previous evidence referenced:
  - broken README doc links and stale migration text
- **Current status: Fixed**
- Fresh evidence:
  - Migration statement now matches code (001-007): `README.md:130`, `ForgeFlow/Database/DatabaseManager.swift:87-93`
  - README no longer references missing docs files; now states formal docs are not published: `README.md:157-159`

### Issue F (Medium)
**Title:** `run_tests.sh` mode flags did not isolate layers as documented
- Previous evidence referenced:
  - unit/integration/views flags ran same full command
- **Current status: Fixed**
- Fresh evidence:
  - Suite groups defined by layer: `run_tests.sh:72-103`
  - `run_filtered` applies `-only-testing` filters: `run_tests.sh:105-114`
  - Flags now execute corresponding filtered groups: `run_tests.sh:122-124`

### Issue G (Medium)
**Title:** “Visible audit note” for first-accepted conflict not persisted on assignment record
- Previous evidence referenced:
  - note only in audit-entry payload; `Assignment.auditNote` not used
- **Current status: Fixed**
- Fresh evidence:
  - Conflict path now writes `auditNote` on blocked assignment: `ForgeFlow/Services/AssignmentService.swift:149-166`
  - UI displays assignment note: `ForgeFlow/Views/Postings/PostingDetailView.swift:100-103`

### Issue H (Security gap called out previously)
**Title:** Sync read/list methods lacked actor checks (`listExports/listImports/latest*`)
- Previous evidence referenced:
  - sync read/list methods had no authorization gate
- **Current status: Fixed**
- Fresh evidence:
  - Admin/coordinator guard exists: `ForgeFlow/Services/SyncService.swift:559-564`
  - Read/list methods now require actor and call guard:
    - `ForgeFlow/Services/SyncService.swift:567-570`
    - `ForgeFlow/Services/SyncService.swift:572-575`
    - `ForgeFlow/Services/SyncService.swift:577-580`
    - `ForgeFlow/Services/SyncService.swift:582-585`

## 3. Conclusion
All previously reported issues from your prior report (plus the explicit sync-read security gap from that same report) are now statically verifiable as **Fixed**.

## 4. Static Boundary Reminder
- This re-verification is static only.
- Runtime behavior still requires manual validation for:
  - actual watermark rendering/decryption UX,
  - BGTask scheduling/execution under device conditions,
  - lock/unlock timing transitions across lifecycle events.
