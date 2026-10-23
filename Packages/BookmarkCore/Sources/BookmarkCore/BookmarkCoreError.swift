import Foundation

public enum BookmarkCoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case tooManyFiles(limit: Int)
    case invalidByteCount
    case fileTooLarge(limit: Int)
    case invalidPath(String)
    case invalidManifest(String)
    case missingDestination
    case captureConflict

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid HTTP or HTTPS web address."
        case .tooManyFiles(let limit): "Choose up to \(limit) files at a time."
        case .invalidByteCount: "The file size could not be verified."
        case .fileTooLarge: "Choose a file no larger than 25 MiB."
        case .invalidPath: "The original file has an unsafe storage name."
        case .invalidManifest(let reason): "The capture could not be saved: \(reason)"
        case .missingDestination: "Open Universal Bookmarker once to set up shared saving."
        case .captureConflict: "A different capture already uses this identifier."
        }
    }
}
