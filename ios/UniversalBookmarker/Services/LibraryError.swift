import Foundation

enum LibraryError: LocalizedError {
    case duplicateLink
    case invalidCollection
    case cloudNotConfigured
    case notSignedIn
    case pendingChanges
    case invalidRecord
    case fileUnavailable
    case importFailed([String])
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .duplicateLink: "This link is already in your library. You can save another copy."
        case .invalidCollection: "This collection is no longer available."
        case .cloudNotConfigured: "Cloud sync is not configured in this build. Your saves stay on this iPhone."
        case .notSignedIn: "Sign in to access your synced library."
        case .pendingChanges: "There are unsynced saves or captures. Sync them first, or explicitly discard them before signing out."
        case .invalidRecord: "A saved record could not be read. It has been kept for recovery."
        case .fileUnavailable: "This original is not available on this iPhone yet. Connect to download it."
        case .importFailed(let failures): failures.joined(separator: "\n")
        case .remote(let message): message
        }
    }
}
