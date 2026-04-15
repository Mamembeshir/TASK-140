import Foundation
import BackgroundTasks
import UIKit
import os.log

enum ImageCompressionTask {
    static let identifier = "com.forgeflow.app.image-compression"
    private static let queueKey = "forgeflow.bg.compress.jobs"

    // MARK: - Job model

    struct PendingJob: Codable {
        /// Original uncompressed image on disk.
        var inputURL: URL
        /// Destination path for the compressed output.
        var outputURL: URL
    }

    // MARK: - Queue management

    /// Adds an image compression operation to the persistent work queue.
    /// Safe to call from any thread. Duplicate output paths are ignored.
    static func enqueue(inputURL: URL, outputURL: URL) {
        var jobs = loadJobs()
        guard !jobs.contains(where: { $0.outputURL == outputURL }) else { return }
        jobs.append(PendingJob(inputURL: inputURL, outputURL: outputURL))
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
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handler

    private static func handleTask(_ task: BGProcessingTask) {
        let workTask = Task {
            // BG-02: Skip when battery < 20%
            let batteryLevel = await MainActor.run {
                UIDevice.current.isBatteryMonitoringEnabled = true
                return UIDevice.current.batteryLevel
            }
            guard !(batteryLevel > 0 && batteryLevel < 0.2) else {
                task.setTaskCompleted(success: true)
                return
            }

            await processQueue()
            task.setTaskCompleted(success: true)
            schedule()
        }

        // BG-03: On expiration, cancel the work task and persist remaining queue
        task.expirationHandler = {
            workTask.cancel()
            // Queue is already checkpointed after each completed job; mark graceful stop
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Work loop

    private static func processQueue() async {
        var jobs = loadJobs()
        guard !jobs.isEmpty else { return }
        ForgeLogger.background.info("ImageCompressionTask: processing \(jobs.count, privacy: .public) job(s)")

        var index = 0

        while index < jobs.count {
            // Cancellation-safe checkpoint before each job
            if Task.isCancelled {
                persistJobs(jobs)
                return
            }

            let job = jobs[index]

            // Skip stale jobs whose input no longer exists
            guard FileManager.default.fileExists(atPath: job.inputURL.path),
                  let inputData = try? Data(contentsOf: job.inputURL) else {
                jobs.remove(at: index)
                persistJobs(jobs)
                continue
            }

            if let compressed = ImageCompressor.compress(imageData: inputData) {
                try? compressed.write(to: job.outputURL, options: .atomic)
                if job.inputURL != job.outputURL {
                    // Atomically replace the source file with the compressed output,
                    // then clean up the temp output path.
                    try? FileManager.default.replaceItemAt(
                        job.inputURL,
                        withItemAt: job.outputURL,
                        backupItemName: nil,
                        options: []
                    )
                }
                // Never remove inputURL when source == output: the atomic write
                // already updated the file in-place and there is nothing else to delete.
                jobs.remove(at: index)
                persistJobs(jobs)
            } else {
                // Not a compressible image or decoding failed: drop the job
                jobs.remove(at: index)
                persistJobs(jobs)
            }
        }
    }
}
