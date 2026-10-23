import Foundation
import CryptoKit
import UniformTypeIdentifiers
import BookmarkCore

struct ImportedOriginal: Sendable {
    let attachmentID: UUID
    let localFileName: String
    let filename: String
    let kind: BookmarkKind
    let contentType: String
    let byteCount: Int
    let sha256: String
}

actor OriginalFileStore {
    nonisolated let rootURL: URL
    static let maximumBytes = 25 * 1024 * 1024

    init(rootURL: URL) { self.rootURL = rootURL }

    nonisolated func url(scopeID: String, name: String) -> URL {
        let scope = SHA256.hash(data: Data(scopeID.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(scope).appendingPathComponent(name)
    }

    func importFile(_ input: URL, scopeID: String) throws -> ImportedOriginal {
        let access = input.startAccessingSecurityScopedResource()
        defer { if access { input.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let resource = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard resource.isRegularFile == true else { throw LibraryError.remote("Choose a file, rather than a folder.") }
        guard let size = resource.fileSize, size <= Self.maximumBytes else {
            throw LibraryError.remote("Files must be 25 MiB or smaller.")
        }
        let attachmentID = UUID()
        let ext = input.pathExtension.filter { $0.isLetter || $0.isNumber }.prefix(16)
        let name = attachmentID.uuidString.lowercased() + (ext.isEmpty ? "" : "." + ext)
        let final = url(scopeID: scopeID, name: name)
        try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = final.appendingPathExtension("partial")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: input, to: staging)
        let actual = try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard actual <= Self.maximumBytes else { throw LibraryError.remote("Files must be 25 MiB or smaller.") }
        let digest = try Self.digest(staging)
        try Task.checkCancellation()
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staging.path)
        try FileManager.default.moveItem(at: staging, to: final)
        let type = resource.contentType ?? UTType(filenameExtension: input.pathExtension) ?? .data
        let kind: BookmarkKind = type.conforms(to: .image) ? .photo : type.conforms(to: .pdf) ? .pdf : .file
        return ImportedOriginal(attachmentID: attachmentID, localFileName: name,
                                filename: input.lastPathComponent, kind: kind,
                                contentType: type.preferredMIMEType ?? "application/octet-stream",
                                byteCount: actual, sha256: digest)
    }

    func storeDownload(_ data: Data, scopeID: String, name: String, expectedHash: String?) throws -> URL {
        guard data.count <= Self.maximumBytes else { throw LibraryError.remote("The downloaded file is too large.") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expectedHash, digest != expectedHash { throw LibraryError.remote("The downloaded original failed its integrity check.") }
        let target = url(scopeID: scopeID, name: name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return target
    }

    func remove(scopeID: String, name: String) {
        try? FileManager.default.removeItem(at: url(scopeID: scopeID, name: name))
    }

    private static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
