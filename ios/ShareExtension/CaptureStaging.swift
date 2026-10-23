import Foundation

/// Copies provider-owned URLs while their callback is still active. No provider URL is retained.
enum CaptureStaging {
    static func copyFile(from source: URL, to destination: URL, maximumByteCount: Int) throws -> Int {
        guard source.isFileURL,
              try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw StagingError.notAFile
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        // `.withoutOverwriting` reserves our unique path and preserves any existing original.
        try Data().write(to: destination, options: .withoutOverwriting)
        do {
            let writer = try FileHandle(forWritingTo: destination)
            defer { try? writer.close() }
            var total = 0
            while let bytes = try reader.read(upToCount: 256 * 1024), !bytes.isEmpty {
                guard bytes.count <= maximumByteCount - total else { throw StagingError.tooLarge }
                try writer.write(contentsOf: bytes)
                total += bytes.count
            }
            try writer.synchronize()
            return total
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func writeData(_ data: Data, to destination: URL, maximumByteCount: Int) throws -> Int {
        guard data.count <= maximumByteCount else { throw StagingError.tooLarge }
        try data.write(to: destination, options: .withoutOverwriting)
        do {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.synchronize()
            return data.count
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

enum StagingError: LocalizedError, Sendable {
    case notAFile
    case tooLarge
    case unsupportedContent
    case invalidURL
    case missingProviderFile

    var errorDescription: String? {
        switch self {
        case .notAFile: "Folders cannot be saved. Share the files inside the folder."
        case .tooLarge: "This file is larger than 25 MiB. Share a smaller file."
        case .unsupportedContent: "This content could not be read. Try sharing its web link or original file."
        case .invalidURL: "Only HTTP and HTTPS web links can be saved."
        case .missingProviderFile: "The source app did not provide a readable file. Try sharing it again."
        }
    }
}
