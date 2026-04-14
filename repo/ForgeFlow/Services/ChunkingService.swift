import Foundation

actor ChunkingService {
    static let defaultChunkSize = 5 * 1024 * 1024 // 5 MB
    static let maxRetryDelay: TimeInterval = 30

    /// Copies a file in chunks with resumability and exponential backoff.
    /// Returns the total bytes copied.
    func copyInChunks(
        sourceURL: URL,
        destinationURL: URL,
        chunkSize: Int = defaultChunkSize,
        resumeFromChunk: Int = 0
    ) async throws -> Int {
        let fileManager = FileManager.default
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? sourceHandle.close() }

        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int ?? 0
        let totalChunks = (fileSize + chunkSize - 1) / chunkSize

        // Create or open destination
        if !fileManager.fileExists(atPath: destinationURL.path) {
            fileManager.createFile(atPath: destinationURL.path, contents: nil)
        }
        let destHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? destHandle.close() }

        // Seek to resume position
        let resumeOffset = UInt64(resumeFromChunk * chunkSize)
        try sourceHandle.seek(toOffset: resumeOffset)
        try destHandle.seek(toOffset: resumeOffset)

        var totalBytesCopied = Int(resumeOffset)

        for chunkIndex in resumeFromChunk..<totalChunks {
            var retryCount = 0
            var success = false

            while !success {
                do {
                    try Task.checkCancellation()

                    let offset = UInt64(chunkIndex * chunkSize)
                    try sourceHandle.seek(toOffset: offset)

                    guard let data = try sourceHandle.read(upToCount: chunkSize), !data.isEmpty else {
                        success = true
                        break
                    }

                    try destHandle.seek(toOffset: offset)
                    destHandle.write(data)

                    totalBytesCopied += data.count
                    success = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    retryCount += 1
                    let delay = min(pow(2.0, Double(retryCount)), Self.maxRetryDelay)
                    try await Task.sleep(for: .seconds(delay))

                    if retryCount > 5 {
                        throw error
                    }
                }
            }
        }

        return totalBytesCopied
    }
}
