# ForgeFlow — Business Logic Questions Log

---

## 1. Auth & Security

### 1.1 Where is the password hash stored if not in SQLite?
* **Question:** The prompt says local username/password. GRDB uses SQLite. But storing password hashes in SQLite on an unencrypted device is less secure than using the Keychain.
* **My Understanding:** iOS Keychain is the standard secure store for credentials. The User table in SQLite stores everything except the password hash. The hash lives in Keychain keyed by user ID.
* **Solution:** `User` model in SQLite has all fields except password. Password hash stored in iOS Keychain via `KeychainHelper` keyed as `forgeflow.password.{userId}`. AuthService reads from Keychain to verify. This means passwords survive app updates but are wiped on app uninstall (Keychain default behavior).

### 1.2 What screens are "sensitive" for the 5-minute inactivity lock?
* **Question:** The prompt says "a 5-minute inactivity timeout re-locks sensitive screens." Which screens are sensitive?
* **My Understanding:** All screens except the login screen itself are sensitive. The entire app should lock, not individual screens.
* **Solution:** After 5 minutes of no user interaction (no taps, no scrolls), the app overlays a lock screen requiring password or biometric re-authentication. The lock applies globally — the user returns to exactly where they were after unlocking. `AppState` tracks last interaction timestamp and checks on every scene phase change and timer tick.

### 1.3 How does biometric unlock interact with the inactivity lock?
* **Question:** Can users use FaceID/TouchID to unlock after the inactivity timeout?
* **My Understanding:** Yes. Biometric is a convenience unlock. It's only available if the user has previously authenticated with a password in the current app session (since app launch).
* **Solution:** First launch or fresh app start → must enter password. After that, biometric unlock is available for the inactivity lock. If biometric fails 3 times, fall back to password. If the app is terminated and relaunched, password is required again first.

---

## 2. Postings & Assignments

### 2.1 How does "first accepted wins" work for OPEN postings?
* **Question:** If multiple technicians can accept an OPEN posting, and two tap "Accept" at nearly the same time, how is the conflict resolved?
* **My Understanding:** The database enforces it via UNIQUE constraint. The first INSERT succeeds; the second hits the constraint and is a no-op.
* **Solution:** Assignment table has UNIQUE(posting_id, technician_id). For OPEN postings, additionally only ONE accepted assignment is allowed per posting (unless the coordinator explicitly allows multiple technicians). The service checks: if an ACCEPTED assignment already exists for this posting, reject new acceptances with the message "Already assigned to [name] at [time]." This check + insert is wrapped in a SQLite transaction. Audit entry records both the winner and the blocked attempt.

### 2.2 Can a posting have multiple assigned technicians?
* **Question:** The prompt says "invite one or more Technicians." Does that mean multiple can work on the same posting simultaneously?
* **My Understanding:** INVITE_ONLY mode allows the coordinator to invite multiple specific technicians, each getting their own assignment. OPEN mode is "first accepted wins" — only one technician.
* **Solution:** INVITE_ONLY: coordinator selects multiple technicians → each gets an INVITED assignment → each can independently accept/decline → multiple ACCEPTED assignments possible → tasks are distributed among accepted technicians. OPEN: any technician can accept → only one ACCEPTED assignment allowed → "first accepted wins."

### 2.3 What does "auto-generates a task breakdown" mean exactly?
* **Question:** The prompt says "each posting automatically generates a task breakdown with subtasks, dependencies, priority, and progress states." How is this generated?
* **My Understanding:** The system creates a default task structure that the coordinator then customizes. It's not AI-generated — it's a template.
* **Solution:** When a posting is created, the system auto-generates: one parent task with the same title as the posting (priority P2, status NOT_STARTED), and no subtasks by default. The coordinator then adds subtasks, sets priorities, and defines dependencies via the task editor. If plugins are active, plugin-specific subtasks may be auto-added based on plugin rules.

---

## 3. File Management

### 3.1 What does "resumable chunking for files over 50 MB" mean for a local-only app?
* **Question:** The prompt mentions "resumable chunking" and "retry with exponential backoff under weak connectivity." But this is a fully offline app. What connectivity is involved?
* **My Understanding:** "Upload/download" in this context means importing files from other apps (Files app, AirDrop, camera roll) into the ForgeFlow sandbox. Large files (>50 MB) are read in chunks to avoid memory spikes. "Resumable" means if the app is backgrounded or interrupted during a large file copy, it can resume from the last chunk. "Weak connectivity" likely refers to slow device-to-device transfers (e.g., AirDrop over poor Bluetooth).
* **Solution:** `ChunkingService` reads large files in 5 MB chunks into the sandbox. Progress is tracked per-chunk. If interrupted (memory warning, backgrounding), the service saves the last successful chunk index and resumes on next opportunity. Exponential backoff applies to retry intervals when a chunk read/write fails (e.g., disk full temporarily): 1s, 2s, 4s, 8s, max 30s. This runs as a BGProcessingTask.

### 3.2 How does watermarking work?
* **Question:** The prompt says "rendering a stamped preview while keeping the original encrypted at rest."
* **My Understanding:** Two copies: the original is encrypted (AES-256 using a key from Keychain), and a watermarked preview is generated by overlaying text (user name + timestamp) on the image/PDF. Users see the watermarked version; only Admin can decrypt and access the original.
* **Solution:** `WatermarkRenderer` takes an image, overlays a semi-transparent diagonal text stamp ("ForgeFlow / [user name] / [date]"), and saves as the preview. `AttachmentService` encrypts the original using AES-256-GCM with a key stored in Keychain. The `Attachment` record has both `file_path` (watermarked preview) and `original_encrypted_path` (encrypted original). The decryption endpoint checks Admin role before returning the original.

### 3.3 How is the per-user quota calculated?
* **Question:** "Default 2 GB per user." Does this count only their uploaded files or all files they can access?
* **My Understanding:** Only files uploaded by the user count toward their quota. Files uploaded by others on shared postings don't count against them.
* **Solution:** `FileQuotaManager` sums `file_size_bytes` from Attachment where `uploaded_by = userId`. If total >= quota, new uploads are rejected with "Storage quota exceeded. Delete old files or contact your Administrator." Admin can view and adjust per-user quotas.

---

## 4. Notifications

### 4.1 How does deduplication within a 10-minute window work in SQLite?
* **Question:** The prompt says deduplicate by (event_type + posting_id + recipient) within 10 minutes.
* **My Understanding:** Before creating a notification, check if one with the same (event_type, posting_id, recipient_id) was created in the last 10 minutes. If so, skip.
* **Solution:** `NotificationService.send()` first queries: `SELECT 1 FROM notifications WHERE event_type = ? AND posting_id = ? AND recipient_id = ? AND created_at > datetime('now', '-10 minutes')`. If a row exists, return without creating a new notification. This is cheaper than a UNIQUE constraint with a time component (which SQLite doesn't support natively).

### 4.2 How do do-not-disturb hours work?
* **Question:** Notifications honor DND. But what does "honor" mean — suppress or delay?
* **My Understanding:** Delay. The notification is still created in the database but not surfaced in the UI until the DND window ends.
* **Solution:** Each user has `dnd_start_time` and `dnd_end_time` in their profile (e.g., 22:00–07:00). When `NotificationService.send()` creates a notification during DND, it sets status = PENDING. A timer (or the next app foreground event) checks for PENDING notifications outside DND and transitions them to DELIVERED, surfacing them in the Messaging Center. During DND, the notification bell does NOT show new counts.

---

## 5. Plugins

### 5.1 What does "sandbox against sample postings" mean?
* **Question:** The prompt says Admin can "test them in a local sandbox against sample postings." How is this sandbox isolated?
* **My Understanding:** The sandbox runs the plugin's validation rules against existing postings to see if they would pass or fail. It doesn't modify any live data.
* **Solution:** `PluginService.testPlugin(pluginId, samplePostingIds)`: for each sample posting, the service evaluates the plugin's field rules (e.g., "cooler height must be <= 6 inches") against the posting's custom field values. Results are recorded in `PluginTestResult` with PASS/FAIL and any error messages. The test is read-only — no posting data is modified. Admin reviews results before submitting for approval.

### 5.2 Why do two different Admins need to approve?
* **Question:** The prompt requires "two-step release approval." Why not one?
* **My Understanding:** This is a separation-of-duties control. The plugin creator shouldn't also be the sole approver. Two different Admins ensure a second pair of eyes reviews the rules before they affect live data.
* **Solution:** `PluginApproval` records two steps. Step 1 and Step 2 must be approved by different `approver_id` values. If the same Admin tries to approve both, the service rejects with "Same administrator cannot approve both steps." This is a hard enforcement in `PluginService.approvePlugin()`.

---

## 6. Sync

### 6.1 What format is the sync export file?
* **Question:** The prompt says "local file export/import" for device-to-device sync but doesn't specify format.
* **My Understanding:** A structured, self-contained file that can be shared via AirDrop or Files app.
* **Solution:** Export generates a `.forgeflow` file (actually a ZIP containing JSON files per entity type + attachment files). Structure: `manifest.json` (metadata, checksums, version), `users.json`, `postings.json`, `tasks.json`, etc., plus an `attachments/` directory. The manifest includes a SHA-256 hash of each JSON file for integrity validation on import.

### 6.2 How does conflict resolution work on import?
* **Question:** If two devices have the same posting with different edits, how is the conflict resolved?
* **My Understanding:** The system should detect conflicts and let the user choose, not auto-resolve.
* **Solution:** On import, `SyncService` compares each incoming record's `id` and `version` with the local database. If the local version is different: mark as CONFLICT. The sync status screen shows all conflicts with side-by-side diffs. User chooses "Keep Local" or "Accept Incoming" per record. Bulk actions: "Accept All Incoming" or "Keep All Local." No automatic merge — the user decides.