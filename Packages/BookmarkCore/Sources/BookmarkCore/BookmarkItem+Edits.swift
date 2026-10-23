import Foundation

extension BookmarkItem {
    /// A detail form owns these fields. Persistence owns identity, versions and originals.
    public func applyingUserEdits(from draft: BookmarkItem) -> BookmarkItem {
        var updated = self
        updated.title = draft.title
        updated.note = draft.note
        updated.collectionID = draft.collectionID
        return updated
    }
}
