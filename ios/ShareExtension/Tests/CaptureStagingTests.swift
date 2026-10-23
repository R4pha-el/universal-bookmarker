import Foundation
import XCTest

// Compile CaptureStaging.swift into this test target; no UIKit or extension host is needed.
final class CaptureStagingTests: XCTestCase {
    func testCopiesOriginalBytesBeforeProviderTemporaryFileDisappears() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("provider.pdf")
        let target = root.appendingPathComponent("owned.pdf")
        let bytes = Data([0, 1, 2, 3, 255])
        try bytes.write(to: source)
        XCTAssertEqual(try CaptureStaging.copyFile(from: source, to: target, maximumByteCount: 5), 5)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testOversizedFileLeavesNoPartialOriginal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("provider.bin")
        let target = root.appendingPathComponent("owned.bin")
        try Data(repeating: 1, count: 10).write(to: source)
        XCTAssertThrowsError(try CaptureStaging.copyFile(from: source, to: target, maximumByteCount: 9))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testDirectoryCannotBeAcceptedAsOriginal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("owned")
        XCTAssertThrowsError(try CaptureStaging.copyFile(from: root, to: target, maximumByteCount: 25))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testExistingDestinationIsNeverOverwritten() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("provider.bin")
        let target = root.appendingPathComponent("owned.bin")
        try Data([1]).write(to: source)
        try Data([2]).write(to: target)
        XCTAssertThrowsError(try CaptureStaging.copyFile(from: source, to: target, maximumByteCount: 25))
        XCTAssertEqual(try Data(contentsOf: target), Data([2]))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
