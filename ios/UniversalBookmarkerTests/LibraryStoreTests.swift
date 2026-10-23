import XCTest
import BookmarkCore
@testable import UniversalBookmarker

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSavedLinkSurvivesReopening() async throws {
        let first = try LibraryStore(baseDirectory: directory, configuration: nil)
        try await first.addLink("https://example.com/a")
        let second = try LibraryStore(baseDirectory: directory, configuration: nil)
        XCTAssertEqual(second.items.map(\.url?.absoluteString), ["https://example.com/a"])
        XCTAssertEqual(second.syncMessage, "On this iPhone")
    }

    func testDeletingCollectionPreservesItsItems() async throws {
        let store = try LibraryStore(inMemory: true, baseDirectory: directory, configuration: nil)
        try await store.addLink("https://example.com")
        try store.createCollection(name: "Work", tint: "blue")
        let collection = try XCTUnwrap(store.collections.first)
        try store.moveItem(try XCTUnwrap(store.items.first), to: collection.id)
        try store.deleteCollection(collection)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items.first?.collectionID)
        XCTAssertTrue(store.collections.isEmpty)
    }

    func testDuplicateLinkRequiresExplicitOverride() async throws {
        let store = try LibraryStore(inMemory: true, baseDirectory: directory, configuration: nil)
        try await store.addLink("https://example.com")
        do {
            try await store.addLink("https://example.com")
            XCTFail("Duplicate must require a choice")
        } catch LibraryError.duplicateLink { }
        try await store.addLink("https://example.com", allowDuplicate: true)
        XCTAssertEqual(store.items.count, 2)
    }

    func testFailedImportDoesNotAddItem() async throws {
        let store = try LibraryStore(inMemory: true, baseDirectory: directory, configuration: nil)
        do {
            try await store.importFiles([directory.appendingPathComponent("missing.pdf")])
            XCTFail("Missing file must fail")
        } catch { }
        XCTAssertTrue(store.items.isEmpty)
    }

    func testImportedOriginalSurvivesReopening() async throws {
        let input = directory.appendingPathComponent("notes.txt")
        try Data("A saved note".utf8).write(to: input)
        let first = try LibraryStore(baseDirectory: directory, configuration: nil)
        try await first.importFiles([input])
        let second = try LibraryStore(baseDirectory: directory, configuration: nil)
        let item = try XCTUnwrap(second.items.first)
        let original = try XCTUnwrap(second.fileURL(for: item))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "A saved note")
    }
}
