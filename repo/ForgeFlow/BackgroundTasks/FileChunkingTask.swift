import BackgroundTasks
import Foundation
import UIKit
import os.log

enum FileChunkingTask {
    static let identifier = "com.forgeflow.app.file-chunking"
    private static let queueKey = "forgeflow.bg.chunk.jobs"

    // MARK: - Job model

    struct PendingJob: Codable {
        var sourceURL: URL
        var destinationURL: URL
        /// Chunk index to resume from on the next attempt.
        var resumeChunk: Int
    }

    // MARK: - Queue management

    /// Adds a large-file copy operation to the persistent work queue.
    /// Safe to call from any thread. Duplicate destinations are ignored.
    static func enqueue(sourceURL: URL, destinationURL: URL) {
        var jobs = loadJobs()
        guard !jobs.contains(where: { $0.destinationURL == destinationURL }) else { return }
        jobs.append(PendingJob(sourceURL: sourceURL, destinationURL: destinationURL, resumeChunk: 0))
        persistJobs(jobs)
    }

    private static func loadJobs() -> [PendingJob] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let jobs = try? JSONDecoder().decode([PendingJob].self, from: data) else { return [] }
        return jobs
    }

    private static func persistJobs(_ jobs: [PendingJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }

    // MARK: - Registration / scheduling

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleTask(processingTask)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600) // 6 hours
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handler

    private static func handleTask(_ task: BGProcessingTask) {
        // BG-02: Skip if low power mode
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            task.setTaskCompleted(success: true)
            schedule()
            return
        }

        let workTask = Task {
            await processQueue()
            task.setTaskCompleted(success: true)
            schedule()
        }

        // BG-03: On memory warning or expiration, cancel and persist resume positions
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            workTask.cancel()
        }

        task.expirationHandler = {
            workTask.cancel()
            NotificationCenter.default.removeObserver(observer)
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Work loop

    private static func processQueue() async {
        var jobs = loadJobs()
        guard !jobs.isEmpty else { return }
        ForgeLogger.background.info("FileChunkingTask: processing \(jobs.count, privacy: .public) job(s)")

        let service = ChunkingService()
        var index = 0

        while index < jobs.count {
            // Cancellation-safe checkpoint before each job
            if Task.isCancelled {
                persistJobs(jobs) // Save current resume positions
                return
            }

            // Skip jobs whose source no longer exists (completed or removed externally)
            guard FileManager.default.fileExists(atPath: jobs[index].sourceURL.path) else {
                jobs.remove(at: index)
                persistJobs(jobs)
                continue
            }

            let job = jobs[index]
            do {
                _ = try await service.copyInChunks(
                    sourceURL: job.sourceURL,
                    destinationURL: job.destinationURL,
                    resumeFromChunk: job.resumeChunk
                )
                // Completed: remove from queue and clean up temp source
                try? FileManager.default.removeItem(at: job.sourceURL)
                jobs.remove(at: index)
                persistJobs(jobs)
            } catch is CancellationError {
                // Estimate resume chunk from bytes written to destination so far
                let written = (try? FileManager.default.attributesOfItem(
                    atPath: job.destinationURL.path)[.size] as? Int) ?? 0
                jobs[index].resumeChunk = written / ChunkingService.defaultChunkSize
                persistJobs(jobs)
                return
            } catch {
                // I/O error on this job: advance past it and retry next run
                index += 1
            }
        }

        persistJobs(jobs)
    }
}
