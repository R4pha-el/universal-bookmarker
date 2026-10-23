import Foundation

struct SyncConflict: Identifiable {
    let id: UUID
    let title: String
    let serverDeleted: Bool
}
