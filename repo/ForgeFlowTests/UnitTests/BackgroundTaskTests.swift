import Testing
import Foundation
@testable import ForgeFlow

// MARK: - Background Task Unit Tests
//
// These tests cover the pure-logic, non-BGTaskScheduler parts of each background
// task module: identifier strings, queue serialisation, deduplication behaviour,
// and configuration constants.  BGTaskScheduler registration / scheduling calls
// are excluded — they require a running host app and are exercised manually in
// the simulator.

@Suite("BackgroundTask: CacheEvictionTask")
struct CacheEvictionTaskTests {

    @Test("Identifier matches BGTaskSchedulerPermittedIdentifiers entry")
    func identifierValue() {
        #expect(CacheEvictionTask.identifier == "com.forgeflow.app.cache-eviction")
    }

    @Test("Retention window is exactly 90 days")
    func retentionDays() {
        #expect(CacheEvictionTask.retentionDays == 90)
    }
}

// MARK: -

@Suite("BackgroundTask: OrphanCleanupTask")
struct OrphanCleanupTaskTests {

    @Test("Identifier matches BGTaskSchedulerPermittedIdentifiers entry")
    func identifierValue() {
        #expect(OrphanCleanupTask.identifier == "com.forgeflow.app.orphan-cleanup")
    }
}

// MARK: -

@Suite("BackgroundTask: ImageCompressionTask", .serialized)
struct ImageCompressionTaskTests {

    private let queueKey = "forgeflow.bg.compress.jobs"

    // Clean UserDefaults before/after each test so tests are isolated.
    private func resetQueue() {
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    private func readQueue() -> [ImageCompressionTask.PendingJob]? {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return nil }
        return try? JSONDecoder().decode([ImageCompressionTask.PendingJob].self, from: data)
    }

    @Test("Identifier matches BGTaskSchedulerPermittedIdentifiers entry")
    func identifierValue() {
        #expect(ImageCompressionTask.identifier == "com.forgeflow.app.image-compression")
    }

    @Test("PendingJob round-trips through JSON encoding")
    func pendingJobCodable() throws {
        let input  = URL(filePath: "/tmp/forgeflow_test_in.jpg")
        let output = URL(filePath: "/tmp/forgeflow_test_out.jpg")
        let job    = ImageCompressionTask.PendingJob(inputURL: input, outputURL: output)

        let data    = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(ImageCompressionTask.PendingJob.self, from: data)

        #expect(decoded.inputURL  == input)
        #expect(decoded.outputURL == output)
    }

    @Test("Enqueue adds a job to the persistent queue")
    func enqueueAddsJob() {
        resetQueue()
        defer { resetQueue() }

        let input  = URL(filePath: "/tmp/fg_img_in.jpg")
        let output = URL(filePath: "/tmp/fg_img_out.jpg")
        ImageCompressionTask.enqueue(inputURL: input, outputURL: output)

        let jobs = readQueue()
        #expect(jobs?.count == 1)
        #expect(jobs?.first?.inputURL  == input)
        #expect(jobs?.first?.outputURL == output)
    }

    @Test("Enqueue deduplicates by output URL — second call is ignored")
    func enqueueDeduplicatesByOutputURL() {
        resetQueue()
        defer { resetQueue() }

        let input1 = URL(filePath: "/tmp/fg_src1.jpg")
        let input2 = URL(filePath: "/tmp/fg_src2.jpg")
        let output = URL(filePath: "/tmp/fg_shared_out.jpg")

        ImageCompressionTask.enqueue(inputURL: input1, outputURL: output)
        ImageCompressionTask.enqueue(inputURL: input2, outputURL: output) // same output → ignored

        let jobs = readQueue()
        #expect(jobs?.count == 1)
        #expect(jobs?.first?.inputURL == input1, "First-enqueued job should win")
    }

    @Test("Enqueue allows multiple jobs with distinct output URLs")
    func enqueueMultipleDistinct() {
        resetQueue()
        defer { resetQueue() }

        let pairs: [(URL, URL)] = [
            (URL(filePath: "/tmp/a_in.jpg"), URL(filePath: "/tmp/a_out.jpg")),
            (URL(filePath: "/tmp/b_in.jpg"), URL(filePath: "/tmp/b_out.jpg")),
            (URL(filePath: "/tmp/c_in.jpg"), URL(filePath: "/tmp/c_out.jpg")),
        ]
        for (i, o) in pairs { ImageCompressionTask.enqueue(inputURL: i, outputURL: o) }

        let jobs = readQueue()
        #expect(jobs?.count == 3)
    }
}

// MARK: -

@Suite("BackgroundTask: FileChunkingTask", .serialized)
struct FileChunkingTaskTests {

    private let queueKey = "forgeflow.bg.chunk.jobs"

    private func resetQueue() {
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    private func readQueue() -> [FileChunkingTask.PendingJob]? {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return nil }
        return try? JSONDecoder().decode([FileChunkingTask.PendingJob].self, from: data)
    }

    @Test("Identifier matches BGTaskSchedulerPermittedIdentifiers entry")
    func identifierValue() {
        #expect(FileChunkingTask.identifier == "com.forgeflow.app.file-chunking")
    }

    @Test("PendingJob round-trips through JSON encoding including resumeChunk")
    func pendingJobCodable() throws {
        let source = URL(filePath: "/tmp/fg_large.bin")
        let dest   = URL(filePath: "/tmp/fg_dest.bin")
        let job    = FileChunkingTask.PendingJob(sourceURL: source, destinationURL: dest, resumeChunk: 17)

        let data    = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(FileChunkingTask.PendingJob.self, from: data)

        #expect(decoded.sourceURL      == source)
        #expect(decoded.destinationURL == dest)
        #expect(decoded.resumeChunk    == 17)
    }

    @Test("Enqueue adds a job starting at chunk 0")
    func enqueueStartsAtChunkZero() {
        resetQueue()
        defer { resetQueue() }

        FileChunkingTask.enqueue(
            sourceURL:      URL(filePath: "/tmp/fg_chunk_src.bin"),
            destinationURL: URL(filePath: "/tmp/fg_chunk_dst.bin")
        )

        let jobs = readQueue()
        #expect(jobs?.first?.resumeChunk == 0)
    }

    @Test("Enqueue deduplicates by destination URL — second call is ignored")
    func enqueueDeduplicatesByDestination() {
        resetQueue()
        defer { resetQueue() }

        let src1  = URL(filePath: "/tmp/fg_cs1.bin")
        let src2  = URL(filePath: "/tmp/fg_cs2.bin")
        let dest  = URL(filePath: "/tmp/fg_cd.bin")

        FileChunkingTask.enqueue(sourceURL: src1, destinationURL: dest)
        FileChunkingTask.enqueue(sourceURL: src2, destinationURL: dest) // duplicate → ignored

        let jobs = readQueue()
        #expect(jobs?.count == 1)
        #expect(jobs?.first?.sourceURL == src1, "First-enqueued source should win")
    }

    @Test("Enqueue allows multiple jobs with distinct destination URLs")
    func enqueueMultipleDistinct() {
        resetQueue()
        defer { resetQueue() }

        for i in 0..<4 {
            FileChunkingTask.enqueue(
                sourceURL:      URL(filePath: "/tmp/fg_ms\(i).bin"),
                destinationURL: URL(filePath: "/tmp/fg_md\(i).bin")
            )
        }

        let jobs = readQueue()
        #expect(jobs?.count == 4)
    }
}
