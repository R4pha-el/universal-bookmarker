import Foundation

/// Cross-process handoff: each capture becomes visible with one directory rename.
/// Acknowledge only after the receiving app commits metadata and original copies.
public actor CaptureInbox {
    private let rootURL: URL
    private let manager = FileManager.default

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func readDestination() throws -> DestinationDescriptor {
        guard let descriptor = try destinationDescriptor() else { throw BookmarkCoreError.missingDestination }
        return descriptor
    }

    public func destinationDescriptor() throws -> DestinationDescriptor? {
        try ensureRoot()
        let url = rootURL.appendingPathComponent("destination.json")
        guard manager.fileExists(atPath: url.path) else { return nil }
        try requireRegularFile(url)
        let descriptor = try CaptureCoding.decoder().decode(DestinationDescriptor.self, from: Data(contentsOf: url))
        try validateScope(descriptor.scopeID)
        return descriptor
    }

    public func writeDestination(_ descriptor: DestinationDescriptor) throws {
        try Task.checkCancellation()
        try validateScope(descriptor.scopeID)
        try ensureRoot()
        let destination = rootURL.appendingPathComponent("destination.json")
        if manager.fileExists(atPath: destination.path) { try requireRegularFile(destination) }
        try synchronizedWrite(CaptureCoding.encoder().encode(descriptor), to: destination)
    }

    public func setDestinationDescriptor(_ descriptor: DestinationDescriptor) throws {
        try writeDestination(descriptor)
    }

    /// Keys must exactly match attachment localFileName values. Retain provider
    /// temporary files until this call finishes. Cancellation never publishes.
    public func publish(_ manifest: CaptureManifest, files: [String: URL]) throws {
        try Task.checkCancellation()
        try validate(manifest)
        try ensureRoot()
        let parent = try scopeDirectory(manifest.scopeID, create: true)
        let destination = parent.appendingPathComponent(manifest.id.uuidString.lowercased(), isDirectory: true)
        let bytes = try CaptureCoding.encoder().encode(manifest)
        if manager.fileExists(atPath: destination.path) {
            try verifyExisting(manifest, directory: destination, expectedBytes: bytes)
            return
        }
        guard Set(files.keys) == Set(manifest.attachments.map(\.localFileName)) else {
            throw BookmarkCoreError.invalidManifest("Original files do not match the manifest.")
        }

        let stagingParent = try directory(".staging", under: rootURL, create: true)
        let staging = try directory(UUID().uuidString.lowercased(), under: stagingParent, create: true)
        defer { try? manager.removeItem(at: staging) }
        let originals = try directory("originals", under: staging, create: true)
        for attachment in manifest.attachments {
            try Task.checkCancellation()
            guard let source = files[attachment.localFileName], source.isFileURL else {
                throw BookmarkCoreError.invalidManifest("Missing original file.")
            }
            try requireRegularFile(source)
            try verifySize(source, expected: attachment.byteCount)
            let target = originals.appendingPathComponent(attachment.localFileName)
            try manager.copyItem(at: source, to: target)
            try requireRegularFile(target)
            try verifySize(target, expected: attachment.byteCount)
            try synchronize(target)
        }
        try Task.checkCancellation()
        try synchronizedWrite(bytes, to: staging.appendingPathComponent("manifest.json"))
        try Task.checkCancellation()
        do {
            try manager.moveItem(at: staging, to: destination)
        } catch {
            // Another process may have completed the identical retry.
            guard manager.fileExists(atPath: destination.path) else { throw error }
            try verifyExisting(manifest, directory: destination, expectedBytes: bytes)
        }
    }

    /// Other account scopes and incomplete staging directories remain untouched.
    public func pending(scopeID: String) throws -> [CaptureManifest] {
        try validateScope(scopeID)
        try ensureRoot()
        let parent = try scopeDirectory(scopeID, create: false)
        guard manager.fileExists(atPath: parent.path) else { return [] }
        try requireDirectory(parent)
        let children = try manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result: [CaptureManifest] = []
        for child in children where UUID(uuidString: child.lastPathComponent) != nil {
            try Task.checkCancellation()
            try requireDirectory(child)
            let manifestURL = child.appendingPathComponent("manifest.json")
            try requireRegularFile(manifestURL)
            let bytes = try Data(contentsOf: manifestURL)
            let manifest = try CaptureCoding.decoder().decode(CaptureManifest.self, from: bytes)
            guard manifest.scopeID == scopeID,
                  manifest.id.uuidString.lowercased() == child.lastPathComponent.lowercased() else {
                throw BookmarkCoreError.invalidManifest("Capture identity does not match its queue.")
            }
            try validate(manifest)
            try verifyOriginals(manifest, directory: child)
            result.append(manifest)
        }
        return result.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    public func fileURL(for attachment: CaptureAttachment, in manifest: CaptureManifest) throws -> URL {
        try validate(manifest)
        guard manifest.attachments.contains(attachment) else {
            throw BookmarkCoreError.invalidManifest("The original is not part of this capture.")
        }
        let capture = try captureDirectory(manifest)
        try requireDirectory(capture)
        let originals = try directory("originals", under: capture, create: false)
        try requireDirectory(originals)
        let url = originals.appendingPathComponent(attachment.localFileName)
        try requireRegularFile(url)
        try verifySize(url, expected: attachment.byteCount)
        return url
    }

    /// Idempotent removal, restricted to the manifest's frozen scope and UUID.
    public func acknowledge(_ manifest: CaptureManifest) throws {
        try validate(manifest)
        try ensureRoot()
        let capture = try captureDirectory(manifest)
        guard manager.fileExists(atPath: capture.path) else { return }
        try requireDirectory(capture)
        let manifestURL = capture.appendingPathComponent("manifest.json")
        try requireRegularFile(manifestURL)
        let stored = try CaptureCoding.decoder().decode(CaptureManifest.self, from: Data(contentsOf: manifestURL))
        guard stored.id == manifest.id, stored.scopeID == manifest.scopeID,
              stored.destination.generation == manifest.destination.generation else {
            throw BookmarkCoreError.captureConflict
        }
        do { try manager.removeItem(at: capture) }
        catch {
            // Concurrent acknowledgements are also safe across app processes.
            if manager.fileExists(atPath: capture.path) { throw error }
        }
    }

    private func validate(_ manifest: CaptureManifest) throws {
        try validateScope(manifest.scopeID)
        try ImportPolicy.validate(selectionCount: manifest.attachments.count)
        guard manifest.url != nil || !manifest.attachments.isEmpty else {
            throw BookmarkCoreError.invalidManifest("Choose a link or at least one file.")
        }
        if let url = manifest.url { _ = try LinkValidator.validate(url.absoluteString) }
        var names = Set<String>()
        var identities = Set<UUID>()
        for attachment in manifest.attachments {
            try validateName(attachment.localFileName)
            try ImportPolicy.validate(byteCount: attachment.byteCount)
            guard attachment.kind != .link,
                  names.insert(attachment.localFileName).inserted,
                  identities.insert(attachment.id).inserted else {
                throw BookmarkCoreError.invalidManifest("Original file identities must be unique.")
            }
        }
    }

    private func validateScope(_ scopeID: String) throws {
        guard !scopeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              scopeID.utf8.count <= 128 else {
            throw BookmarkCoreError.invalidManifest("Invalid library scope.")
        }
    }

    private func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\\"), !name.contains("\0"), name.utf8.count <= 240 else {
            throw BookmarkCoreError.invalidPath(name)
        }
    }

    private func ensureRoot() throws {
        guard rootURL.isFileURL else { throw BookmarkCoreError.invalidPath(rootURL.absoluteString) }
        if !manager.fileExists(atPath: rootURL.path) {
            try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        try requireDirectory(rootURL)
    }

    private func scopeDirectory(_ scopeID: String, create: Bool) throws -> URL {
        try validateScope(scopeID)
        let scopes = try directory("scopes", under: rootURL, create: create)
        let name = Data(scopeID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try directory(name, under: scopes, create: create)
    }

    private func captureDirectory(_ manifest: CaptureManifest) throws -> URL {
        let scope = try scopeDirectory(manifest.scopeID, create: false)
        return scope.appendingPathComponent(manifest.id.uuidString.lowercased(), isDirectory: true)
    }

    private func directory(_ name: String, under parent: URL, create: Bool) throws -> URL {
        try validateName(name)
        if manager.fileExists(atPath: parent.path) { try requireDirectory(parent) }
        let url = parent.appendingPathComponent(name, isDirectory: true)
        if create && !manager.fileExists(atPath: url.path) {
            do { try manager.createDirectory(at: url, withIntermediateDirectories: false) }
            catch { if !manager.fileExists(atPath: url.path) { throw error } }
        }
        if manager.fileExists(atPath: url.path) { try requireDirectory(url) }
        return url
    }

    private func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              url.standardizedFileURL.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
            throw BookmarkCoreError.invalidPath(url.lastPathComponent)
        }
    }

    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw BookmarkCoreError.invalidPath(url.lastPathComponent)
        }
    }

    private func verifySize(_ url: URL, expected: Int) throws {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value == Int64(expected) else {
            throw BookmarkCoreError.invalidManifest("The original file size changed during import.")
        }
    }

    private func verifyOriginals(_ manifest: CaptureManifest, directory capture: URL) throws {
        let originals = try directory("originals", under: capture, create: false)
        try requireDirectory(originals)
        for attachment in manifest.attachments {
            let file = originals.appendingPathComponent(attachment.localFileName)
            try requireRegularFile(file)
            try verifySize(file, expected: attachment.byteCount)
        }
    }

    private func verifyExisting(_ manifest: CaptureManifest, directory capture: URL, expectedBytes: Data) throws {
        try requireDirectory(capture)
        let manifestURL = capture.appendingPathComponent("manifest.json")
        try requireRegularFile(manifestURL)
        guard try Data(contentsOf: manifestURL) == expectedBytes else { throw BookmarkCoreError.captureConflict }
        try verifyOriginals(manifest, directory: capture)
    }

    private func synchronizedWrite(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url, options: .atomic)
        try synchronize(url)
    }

    private func synchronize(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
