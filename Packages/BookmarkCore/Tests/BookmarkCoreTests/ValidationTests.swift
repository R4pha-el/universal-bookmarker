import Foundation
import XCTest
@testable import BookmarkCore

final class ValidationTests: XCTestCase {
    func testLinksTrimWhitespaceAndAcceptOnlyWebSchemes() throws {
        XCTAssertEqual(try LinkValidator.validate(" \nHTTPS://example.com/path?q=x \t").host, "example.com")
        for input in ["", "example.com", "javascript:alert(1)", "file:///tmp/a", "ftp://example.com", "https://", "https://bad host.com", "https://example.com/a b", "https://user:pass@example.com"] {
            XCTAssertThrowsError(try LinkValidator.validate(input), input)
        }
    }

    func testSearchFoldsUnicodeAndIncludesEachMetadataSource() {
        let item = BookmarkItem(title: "Café inspiration", kind: .file,
                                url: URL(string: "https://example.com/reference"),
                                filename: "Résumé.pdf", note: "Ångström design")
        for query in ["CAFE", "resume", "ANGSTROM", "EXAMPLE.COM", "reference", "  café  ", ""] {
            XCTAssertTrue(LibrarySearch.matches(item, query: query), query)
        }
        XCTAssertFalse(LibrarySearch.matches(item, query: "missing"))
        var deleted = item
        deleted.deletedAt = Date()
        XCTAssertFalse(LibrarySearch.matches(deleted, query: ""))
        XCTAssertTrue(BookmarkKind.pdf.isIncluded(in: .files))
        XCTAssertTrue(BookmarkKind.photo.isIncluded(in: .photos))
        XCTAssertFalse(BookmarkKind.pdf.isIncluded(in: .photos))
    }

    func testImportLimitsIncludeBoundaryAndRejectInvalidCounts() throws {
        try ImportPolicy.validate(selectionCount: 20)
        try ImportPolicy.validate(byteCount: 25 * 1_024 * 1_024)
        XCTAssertThrowsError(try ImportPolicy.validate(selectionCount: 21))
        XCTAssertThrowsError(try ImportPolicy.validate(selectionCount: -1))
        XCTAssertThrowsError(try ImportPolicy.validate(byteCount: 25 * 1_024 * 1_024 + 1))
        XCTAssertThrowsError(try ImportPolicy.validate(byteCount: -1))
    }

    func testDomainDefaultsAndCodablePreserveIdentityAndDates() throws {
        let item = BookmarkItem(title: "Saved", kind: .link)
        XCTAssertEqual(item.syncStatus, .local)
        XCTAssertEqual(item.version, 0)
        XCTAssertEqual(item.scopeID, LibraryScope.device.id)
        let collection = BookmarkCollection(name: "Reading")
        XCTAssertNil(collection.deletedAt)
        XCTAssertEqual(collection.scopeID, item.scopeID)
        let data = try CaptureCoding.encoder().encode(item)
        let decoded = try CaptureCoding.decoder().decode(BookmarkItem.self, from: data)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, item.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("T"))
        XCTAssertNotEqual(LibraryScope.account(userID: UUID()).id, LibraryScope.device.id)
    }
}
