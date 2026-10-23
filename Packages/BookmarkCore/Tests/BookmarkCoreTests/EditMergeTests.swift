import XCTest
@testable import BookmarkCore

final class EditMergeTests: XCTestCase {
    func testStaleDetailEditPreservesDownloadedOriginalAndAcknowledgedVersion() {
        var persisted = BookmarkItem(title: "Document", kind: .pdf, filename: "plan.pdf",
                                     localFileName: "downloaded.pdf", byteCount: 12, version: 7,
                                     scopeID: "account:owner", syncStatus: .synced)
        var staleDraft = persisted
        staleDraft.version = 0
        staleDraft.localFileName = nil
        staleDraft.title = "Renamed document"
        staleDraft.note = "Remember this"
        persisted = persisted.applyingUserEdits(from: staleDraft)
        XCTAssertEqual(persisted.title, "Renamed document")
        XCTAssertEqual(persisted.note, "Remember this")
        XCTAssertEqual(persisted.localFileName, "downloaded.pdf")
        XCTAssertEqual(persisted.version, 7)
        XCTAssertEqual(persisted.id, staleDraft.id)
        XCTAssertEqual(persisted.scopeID, "account:owner")
    }
}
