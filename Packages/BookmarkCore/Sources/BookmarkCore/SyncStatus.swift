import Foundation

public enum SyncStatus: String, Codable, CaseIterable, Sendable {
    case local, queued, synced, failed
}
