import Foundation
import SwiftUI

/// Tracks a pending delta export that has been generated but not yet confirmed delivered.
/// The cursor is only advanced once `confirmDeltaDelivered()` is called — a retry before
/// confirmation will re-export the same delta rather than skipping records.
struct PendingDeltaConfirmation: Sendable {
    let peerId: String
    let entityTypes: [String]
    let exportedAt: Date
}

@Observable
final class SyncViewModel {
    var lastExport: SyncExport?
    var lastImport: SyncImport?
    var exports: [SyncExport] = []
    var imports: [SyncImport] = []
    var conflicts: [SyncConflict] = []
    var isExporting = false
    var isImporting = false
    var errorMessage: String?

    // Export options
    var exportPostings = true
    var exportTasks = true
    var exportAssignments = true
    var exportComments = true
    var exportDependencies = true
    var exportStartDate: Date?
    var exportEndDate: Date?

    // Delta sync — peer device ID for outbound export
    var peerDeviceId: String = ""
    // Delta sync — source peer ID for inbound import (identifies who sent the file)
    var sourcePeerIdForImport: String = ""
    // Non-nil when a delta export is awaiting peer delivery confirmation
    var pendingDeltaConfirmation: PendingDeltaConfirmation?

    private let syncService: SyncService
    private let appState: AppState

    init(syncService: SyncService, appState: AppState) {
        self.syncService = syncService
        self.appState = appState
    }

    var selectedEntityTypes: [String] {
        var types: [String] = []
        if exportPostings { types.append("postings") }
        if exportTasks { types.append("tasks") }
        if exportAssignments { types.append("assignments") }
        if exportComments { types.append("comments") }
        if exportDependencies { types.append("dependencies") }
        return types
    }

    func load() async {
        guard let actorId = appState.currentUserId else { return }
        do {
            lastExport = try await syncService.latestExport(actorId: actorId)
            lastImport = try await syncService.latestImport(actorId: actorId)
            exports = try await syncService.listExports(actorId: actorId)
            imports = try await syncService.listImports(actorId: actorId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Full export with optional manual date range. Use for ad-hoc or first-time full transfers.
    func export() async {
        guard let userId = appState.currentUserId else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let result = try await syncService.export(
                entityTypes: selectedEntityTypes,
                startDate: exportStartDate,
                endDate: exportEndDate,
                exportedBy: userId
            )
            lastExport = result
            exports.insert(result, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delta export scoped to records updated since the last confirmed sync with `peerDeviceId`.
    /// Cursors are NOT advanced until `confirmDeltaDelivered()` is called, so a failed
    /// transfer can be retried without skipping any records.
    func deltaExport() async {
        guard let userId = appState.currentUserId, !peerDeviceId.isEmpty else {
            errorMessage = "Enter a peer device ID to start a delta sync."
            return
        }
        isExporting = true
        defer { isExporting = false }
        do {
            let result = try await syncService.exportDelta(
                peerId: peerDeviceId,
                entityTypes: selectedEntityTypes,
                exportedBy: userId
            )
            lastExport = result
            exports.insert(result, at: 0)
            // Store pending state — cursor not advanced until confirmed
            pendingDeltaConfirmation = PendingDeltaConfirmation(
                peerId: peerDeviceId,
                entityTypes: selectedEntityTypes,
                exportedAt: result.exportedAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call after the peer device confirms it received and successfully applied the delta export.
    /// This advances the local export cursor so the next delta starts from this point.
    func confirmDeltaDelivered() async {
        guard let userId = appState.currentUserId,
              let pending = pendingDeltaConfirmation else { return }
        do {
            try await syncService.confirmExportDelivered(
                peerId: pending.peerId,
                entityTypes: pending.entityTypes,
                exportedAt: pending.exportedAt,
                actorId: userId
            )
            pendingDeltaConfirmation = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFile(url: URL) async {
        guard let userId = appState.currentUserId else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let (syncImport, detectedConflicts) = try await syncService.importFile(
                fileURL: url,
                importedBy: userId
            )
            lastImport = syncImport
            conflicts = detectedConflicts
            imports.insert(syncImport, at: 0)

            // Zero-conflict import: apply immediately and advance import-side cursor
            if detectedConflicts.isEmpty {
                try await syncService.resolveConflicts(
                    importId: syncImport.id, decisions: [], actorId: userId
                )
                await advanceImportCursorIfNeeded(importRecord: syncImport, userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolveConflict(entityId: UUID, decision: SyncConflictDecision) async {
        guard let importId = lastImport?.id,
              let userId = appState.currentUserId else { return }
        do {
            try await syncService.resolveConflicts(
                importId: importId,
                decisions: [(entityId: entityId, decision: decision)],
                actorId: userId
            )
            conflicts.removeAll { $0.entityId == entityId }
            if conflicts.isEmpty {
                await advanceImportCursorIfNeeded(importRecord: lastImport, userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolveAllKeepLocal() async {
        guard let importId = lastImport?.id,
              let userId = appState.currentUserId else { return }
        let decisions = conflicts.map { (entityId: $0.entityId, decision: SyncConflictDecision.keepLocal) }
        do {
            try await syncService.resolveConflicts(
                importId: importId, decisions: decisions, actorId: userId
            )
            conflicts.removeAll()
            await advanceImportCursorIfNeeded(importRecord: lastImport, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolveAllAcceptIncoming() async {
        guard let importId = lastImport?.id,
              let userId = appState.currentUserId else { return }
        let decisions = conflicts.map { (entityId: $0.entityId, decision: SyncConflictDecision.acceptIncoming) }
        do {
            try await syncService.resolveConflicts(
                importId: importId, decisions: decisions, actorId: userId
            )
            conflicts.removeAll()
            await advanceImportCursorIfNeeded(importRecord: lastImport, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    /// Advances the import-side cursor after all conflicts are resolved.
    ///
    /// - Watermark: uses `importRecord.sourceExportedAt` (the source peer's export timestamp
    ///   from the manifest) rather than `importedAt` (local clock). Using local time would skip
    ///   records created on the source between export generation and local import time.
    /// - Entity scope: uses the entity types from the source manifest, not the local UI toggles,
    ///   so the cursor scope exactly matches what the source exported.
    private func advanceImportCursorIfNeeded(importRecord: SyncImport?, userId: UUID) async {
        guard !sourcePeerIdForImport.isEmpty, let importRecord else { return }

        // Use manifest exportedAt as the watermark; fall back to importedAt only if absent
        let watermark = importRecord.sourceExportedAt ?? importRecord.importedAt

        // Parse entity types from the manifest JSON stored on the import record
        let entityTypes: [String]
        if let json = importRecord.sourceEntityTypes,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String],
           !parsed.isEmpty {
            entityTypes = parsed
        } else {
            entityTypes = selectedEntityTypes
        }
        guard !entityTypes.isEmpty else { return }

        do {
            try await syncService.recordImportedFrom(
                peerId: sourcePeerIdForImport,
                entityTypes: entityTypes,
                syncedAt: watermark,
                actorId: userId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
