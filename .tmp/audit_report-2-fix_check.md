# ForgeFlow Full Issue Recheck (Fresh)

Date: 2026-04-14  
Mode: Static-only recheck of **all previously reported material issues** from the prior audit.

## Overall Status
- **All previously reported issues in the prior issue list are now addressed (6/6 fixed).**

## Issue-by-Issue Verification

### 1) Background image compression could delete uploaded image files
- **Previous severity:** Blocker
- **Current status:** Fixed
- **Verification evidence:**
  - Compression now enqueues to a distinct temp output path: `ForgeFlow/Services/AttachmentService.swift:159`
  - Replace logic only runs when input/output differ: `ForgeFlow/BackgroundTasks/ImageCompressionTask.swift:112`
  - Explicit safeguard not to remove input when source==output: `ForgeFlow/BackgroundTasks/ImageCompressionTask.swift:123`

### 2) Object-level authorization bypass on read/list methods when actor missing
- **Previous severity:** High
- **Current status:** Fixed
- **Verification evidence:**
  - Posting task list now fails closed if actor not found: `ForgeFlow/Services/PostingService.swift:343`
  - Assignment list now fails closed if actor not found: `ForgeFlow/Services/AssignmentService.swift:312`
  - Task list now requires actor existence before access checks: `ForgeFlow/Services/TaskService.swift:301`

### 3) Notification dedup race under concurrent sends
- **Previous severity:** High
- **Current status:** Fixed (static)
- **Verification evidence:**
  - Dedup + insert now executed in one write transaction: `ForgeFlow/Services/NotificationService.swift:34`, `ForgeFlow/Services/NotificationService.swift:36`
  - Transaction-scoped duplicate lookup used by `send`: `ForgeFlow/Database/Repositories/NotificationRepository.swift:70`
- **Boundary note:** Runtime stress/concurrency behavior should still be manually exercised for production confidence.

### 4) User creation could commit DB user before Keychain persistence succeeded
- **Previous severity:** High
- **Current status:** Fixed
- **Verification evidence:**
  - Compensating delete on Keychain failure is implemented: `ForgeFlow/Services/AuthService.swift:243`, `ForgeFlow/Services/AuthService.swift:249`
  - Repo delete helper used for compensation: `ForgeFlow/Database/Repositories/UserRepository.swift:73`
  - Explicit error for this path exists: `ForgeFlow/Models/Errors.swift:18`

### 5) Plugin field value updates lacked posting ownership/object-scope authorization
- **Previous severity:** Medium
- **Current status:** Fixed
- **Verification evidence:**
  - Actor/user existence required: `ForgeFlow/Services/PluginService.swift:423`
  - Role restricted to admin/coordinator: `ForgeFlow/Services/PluginService.swift:427`
  - Posting existence required: `ForgeFlow/Services/PluginService.swift:430`
  - Coordinators limited to postings they created: `ForgeFlow/Services/PluginService.swift:433`

### 6) Due date label omitted time display
- **Previous severity:** Low
- **Current status:** Fixed
- **Verification evidence:**
  - Due date label now uses full display formatter (includes time): `ForgeFlow/Views/Components/DueDateLabel.swift:14`
  - Accessibility label also uses full display formatter: `ForgeFlow/Views/Components/DueDateLabel.swift:20`
  - Formatter definition remains `MM/dd/yyyy h:mm a`: `ForgeFlow/Utilities/DateFormatters.swift:7`

## Final Conclusion
- Based on current static evidence, the full set of previously reported issues in scope is now fixed.
