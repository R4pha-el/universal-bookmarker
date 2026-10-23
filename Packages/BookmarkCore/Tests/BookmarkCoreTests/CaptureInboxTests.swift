import Foundation
import XCTest
@testable import BookmarkCore

final class CaptureInboxTests: XCTestCase, @unchecked Sendable {
    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func attachment(_ name: String = "original.pdf", bytes: Int = 4) -> CaptureAttachment {
        CaptureAttachment(kind: .pdf, filename: "Report.pdf", localFileName: name,
                          contentType: "application/pdf", byteCount: bytes)
    }

    func testPublishScopesOriginalsAndAcknowledgesIdempotently() async throws {
        let root = try sandbox()
        let source = root.appendingPathComponent("source")
        try Data("test".utf8).write(to: source)
        let inbox = CaptureInbox(rootURL: root.appendingPathComponent("inbox"))
        let file = attachment()
        let destination = DestinationDescriptor(scopeID: "account-A")
        let manifest = CaptureManifest(destination: destination, title: "Report", attachments: [file])
        try await inbox.publish(manifest, files: [file.localFileName: source])
        try await inbox.publish(manifest, files: [file.localFileName: source])
        let pending = try await inbox.pending(scopeID: "account-A")
        XCTAssertEqual(pending.map(\.id), [manifest.id])
        XCTAssertEqual(pending.first?.destination.generation, destination.generation)
        let other = try await inbox.pending(scopeID: "account-B")
        XCTAssertTrue(other.isEmpty)
        let copied = try await inbox.fileURL(for: file, in: manifest)
        XCTAssertEqual(try Data(contentsOf: copied), Data("test".utf8))
        try await inbox.acknowledge(manifest)
        try await inbox.acknowledge(manifest)
        let remaining = try await inbox.pending(scopeID: "account-A")
        XCTAssertTrue(remaining.isEmpty)
    }

    func testMissingOrMismatchedOriginalNeverPublishes() async throws {
        let root = try sandbox()
        let inbox = CaptureInbox(rootURL: root.appendingPathComponent("inbox"))
        let file = attachment()
        let manifest = CaptureManifest(destination: DestinationDescriptor(scopeID: "device"), title: "Report", attachments: [file])
        do {
            try await inbox.publish(manifest, files: [file.localFileName: root.appendingPathComponent("missing")])
            XCTFail("Missing original must fail")
        } catch {}
        let source = root.appendingPathComponent("short")
        try Data("x".utf8).write(to: source)
        do {
            try await inbox.publish(manifest, files: [file.localFileName: source])
            XCTFail("Incorrect byte count must fail")
        } catch {}
        let pending = try await inbox.pending(scopeID: "device")
        XCTAssertTrue(pending.isEmpty)
    }

    func testTraversalAndSymlinkOriginalsAreRejected() async throws {
        let root = try sandbox()
        let source = root.appendingPathComponent("source")
        try Data("test".utf8).write(to: source)
        let inbox = CaptureInbox(rootURL: root.appendingPathComponent("inbox"))
        for name in ["../escape", "/absolute", "nested/../../escape", "", ".", "a\\b"] {
            let file = attachment(name)
            let manifest = CaptureManifest(destination: DestinationDescriptor(scopeID: "device"), title: "Bad", attachments: [file])
            do {
                try await inbox.publish(manifest, files: [name: source])
                XCTFail("Unsafe name accepted: \(name)")
            } catch {}
        }
        let link = root.appendingPathComponent("symlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let file = attachment()
        do {
            try await inbox.publish(CaptureManifest(destination: DestinationDescriptor(scopeID: "device"), title: "Symlink", attachments: [file]), files: [file.localFileName: link])
            XCTFail("Symlink original accepted")
        } catch {}
        let pending = try await inbox.pending(scopeID: "device")
        XCTAssertTrue(pending.isEmpty)
    }

    func testPublicationRejectsChangedRetryAndCancellation() async throws {
        let root = try sandbox()
        let inbox = CaptureInbox(rootURL: root.appendingPathComponent("inbox"))
        let destination = DestinationDescriptor(scopeID: "device")
        let manifest = CaptureManifest(destination: destination, title: "First", url: URL(string: "https://example.com"))
        try await inbox.publish(manifest, files: [:])
        var changed = manifest
        changed.title = "Changed"
        do { try await inbox.publish(changed, files: [:]); XCTFail("Changed retry accepted") } catch {}
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await inbox.publish(CaptureManifest(destination: destination, title: "Cancelled", url: URL(string: "https://example.com")), files: [:])
        }
        do { try await cancelled.value; XCTFail("Cancelled capture accepted") } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
        let pending = try await inbox.pending(scopeID: "device")
        XCTAssertEqual(pending.map(\.id), [manifest.id])
    }

    func testDescriptorReplacementRetainsFrozenCaptureScope() async throws {
        let root = try sandbox()
        let inbox = CaptureInbox(rootURL: root)
        let first = DestinationDescriptor(scopeID: "account-A")
        try await inbox.writeDestination(first)
        let frozen = try await inbox.readDestination()
        XCTAssertEqual(frozen.scopeID, first.scopeID)
        XCTAssertEqual(frozen.generation, first.generation)
        XCTAssertEqual(frozen.updatedAt.timeIntervalSince1970, first.updatedAt.timeIntervalSince1970, accuracy: 0.001)
        try await inbox.writeDestination(DestinationDescriptor(scopeID: "account-B"))
        try await inbox.publish(CaptureManifest(destination: frozen, title: "Late", url: URL(string: "https://example.com")), files: [:])
        let accountA = try await inbox.pending(scopeID: "account-A")
        let accountB = try await inbox.pending(scopeID: "account-B")
        XCTAssertEqual(accountA.count, 1)
        XCTAssertTrue(accountB.isEmpty)
    }

    func testInvalidOrOversizedManifestNeverPublishes() async throws {
        let root = try sandbox()
        let inbox = CaptureInbox(rootURL: root)
        let destination = DestinationDescriptor(scopeID: "device")
        let empty = CaptureManifest(destination: destination, title: "Empty")
        let invalidLink = CaptureManifest(destination: destination, title: "Bad", url: URL(string: "file:///tmp/a"))
        let tooLarge = CaptureManifest(destination: destination, title: "Large", attachments: [attachment(bytes: ImportPolicy.maximumByteCount + 1)])
        let tooMany = CaptureManifest(destination: destination, title: "Many", attachments: (0...20).map { attachment("\($0).pdf") })
        for manifest in [empty, invalidLink, tooLarge, tooMany] {
            do { try await inbox.publish(manifest, files: [:]); XCTFail("Invalid manifest published") } catch {}
        }
        let pending = try await inbox.pending(scopeID: "device")
        XCTAssertTrue(pending.isEmpty)
    }

    func testDistinctScopeNamesCannotCollide() async throws {
        let root = try sandbox()
        let inbox = CaptureInbox(rootURL: root)
        for scope in ["a/b", "a_b", "../scope", "résumé"] {
            try await inbox.publish(CaptureManifest(destination: DestinationDescriptor(scopeID: scope), title: scope, url: URL(string: "https://example.com")), files: [:])
        }
        for scope in ["a/b", "a_b", "../scope", "résumé"] {
            let pending = try await inbox.pending(scopeID: scope)
            XCTAssertEqual(pending.map(\.title), [scope])
        }
    }

    func testScopeDirectorySymlinkCannotRedirectPublication() async throws {
        let root = try sandbox()
        let outside = root.appendingPathComponent("outside")
        let queue = root.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: queue.appendingPathComponent("scopes"), withDestinationURL: outside)
        let inbox = CaptureInbox(rootURL: queue)
        let manifest = CaptureManifest(destination: DestinationDescriptor(scopeID: "device"), title: "Link", url: URL(string: "https://example.com"))
        do { try await inbox.publish(manifest, files: [:]); XCTFail("Queue symlink accepted") } catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testPendingIgnoresAbandonedStagingDirectories() async throws {
        let root = try sandbox()
        let staging = root.appendingPathComponent(".staging/interrupted")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: staging.appendingPathComponent("original"))
        let inbox = CaptureInbox(rootURL: root)
        let pending = try await inbox.pending(scopeID: "device")
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
    }

    func testMissingDestinationIsExplicitAndAliasesRoundTrip() async throws {
        let inbox = CaptureInbox(rootURL: try sandbox())
        let missing = try await inbox.destinationDescriptor()
        XCTAssertNil(missing)
        do { _ = try await inbox.readDestination(); XCTFail("Missing destination accepted") }
        catch let error as BookmarkCoreError { XCTAssertEqual(error, .missingDestination) }
        let descriptor = DestinationDescriptor(scopeID: "device")
        try await inbox.setDestinationDescriptor(descriptor)
        let stored = try await inbox.destinationDescriptor()
        XCTAssertEqual(stored?.generation, descriptor.generation)
        do { try await inbox.writeDestination(DestinationDescriptor(scopeID: " ")); XCTFail("Empty scope accepted") } catch {}
        let retained = try await inbox.readDestination()
        XCTAssertEqual(retained.generation, descriptor.generation)
    }

    func testAcknowledgingAnotherScopeDoesNotRemoveOriginalCapture() async throws {
        let inbox = CaptureInbox(rootURL: try sandbox())
        let original = CaptureManifest(destination: DestinationDescriptor(scopeID: "account-A"), title: "Retain", url: URL(string: "https://example.com"))
        try await inbox.publish(original, files: [:])
        var anotherScope = original
        anotherScope.destination.scopeID = "account-B"
        try await inbox.acknowledge(anotherScope)
        let retained = try await inbox.pending(scopeID: "account-A")
        XCTAssertEqual(retained.map(\.id), [original.id])
    }
}
