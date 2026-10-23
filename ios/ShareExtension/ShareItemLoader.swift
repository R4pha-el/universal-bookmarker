import Foundation
@preconcurrency import UIKit
import UniformTypeIdentifiers
import BookmarkCore

struct LoadedShareContent {
    var url: URL?
    var attachments: [CaptureAttachment] = []
    var files: [String: URL] = [:]
    var issues: [String] = []

    var isEmpty: Bool { url == nil && attachments.isEmpty }
    var defaultTitle: String { url?.host ?? attachments.first?.filename ?? "Saved item" }
}

/// Item providers remain confined to the extension's main actor. Their file URLs are copied
/// synchronously inside the provider callback, before the provider may delete them.
@MainActor
final class ShareItemLoader {
    private var progress: Progress?

    func cancel() { progress?.cancel() }

    func load(_ providers: [NSItemProvider], stagingURL: URL) async throws -> LoadedShareContent {
        var result = LoadedShareContent()
        for provider in providers {
            try Task.checkCancellation()
            do {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    try await appendFile(provider, stagingURL: stagingURL, to: &result)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let url = try await loadWebURL(provider)
                    if result.url == nil { result.url = url }
                    else { result.issues.append("An additional web link was skipped. Share it separately.") }
                } else {
                    try await appendFile(provider, stagingURL: stagingURL, to: &result)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result.issues.append(error.localizedDescription)
            }
        }
        try Task.checkCancellation()
        return result
    }

    private func appendFile(_ provider: NSItemProvider, stagingURL: URL, to result: inout LoadedShareContent) async throws {
        guard result.attachments.count < ImportPolicy.maximumSelectionCount else {
            result.issues.append("Only the first 20 readable files were included. Share the remaining files separately.")
            return
        }
        let isFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        let identifier = isFileURL ? UTType.data.identifier : preferredFileType(for: provider)
        guard let identifier else { throw StagingError.unsupportedContent }
        let offeredType = UTType(identifier) ?? .data
        let id = UUID()
        let fileExtension = offeredType.preferredFilenameExtension ?? "bin"
        var localName = "\(id.uuidString).\(fileExtension)"
        let destination = stagingURL.appendingPathComponent(localName, isDirectory: false)
        let info: CopiedRepresentation
        if isFileURL { info = try await copyFileURL(provider, destination: destination) }
        else { info = try await copyRepresentation(provider, typeIdentifier: identifier, destination: destination) }
        let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = info.originalName ?? suggestedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Shared file.\(fileExtension)"
        let sourceType = info.typeIdentifier.flatMap { UTType($0) }
        let filenameType = UTType(filenameExtension: (filename as NSString).pathExtension)
        let type = sourceType == nil || sourceType == .data ? (filenameType ?? offeredType) : (sourceType ?? offeredType)
        var stagedFile = destination
        if let actualExtension = type.preferredFilenameExtension, actualExtension != fileExtension {
            localName = "\(id.uuidString).\(actualExtension)"
            stagedFile = stagingURL.appendingPathComponent(localName, isDirectory: false)
            try FileManager.default.moveItem(at: destination, to: stagedFile)
        }
        let kind: BookmarkKind = type.conforms(to: .image) ? .photo : (type.conforms(to: .pdf) ? .pdf : .file)
        result.attachments.append(CaptureAttachment(id: id, kind: kind, filename: filename,
                                                    localFileName: localName, contentType: type.preferredMIMEType,
                                                    byteCount: info.byteCount))
        result.files[localName] = stagedFile
    }

    private func preferredFileType(for provider: NSItemProvider) -> String? {
        for preferred in [UTType.pdf, .image] {
            if let identifier = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: preferred) == true
            }) { return identifier }
        }
        return provider.registeredTypeIdentifiers.first {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .url)
        }
    }

    private func loadWebURL(_ provider: NSItemProvider) async throws -> URL {
        progress = nil
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, error in
                if let error { continuation.resume(throwing: error); return }
                let rawURL: URL?
                if let url = value as? URL { rawURL = url }
                else if let string = value as? String { rawURL = URL(string: string) }
                else { rawURL = nil }
                guard let url = rawURL,
                      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      url.host?.isEmpty == false else {
                    continuation.resume(throwing: StagingError.invalidURL)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    private struct CopiedRepresentation: Sendable {
        let byteCount: Int
        let originalName: String?
        var typeIdentifier: String? = nil
    }

    private enum RepresentationError: Error { case unavailable }

    private func copyFileURL(_ provider: NSItemProvider, destination: URL) async throws -> CopiedRepresentation {
        progress = nil
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url = value as? URL, url.isFileURL else {
                    continuation.resume(throwing: StagingError.missingProviderFile)
                    return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let count = try CaptureStaging.copyFile(from: url, to: destination,
                                                           maximumByteCount: ImportPolicy.maximumByteCount)
                    let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
                    continuation.resume(returning: CopiedRepresentation(byteCount: count, originalName: url.lastPathComponent,
                                                                         typeIdentifier: type?.identifier))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func copyRepresentation(_ provider: NSItemProvider, typeIdentifier: String,
                                    destination: URL) async throws -> CopiedRepresentation {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                progress = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let url else {
                        // A missing file representation can still have a data representation.
                        continuation.resume(throwing: RepresentationError.unavailable)
                        return
                    }
                    do {
                        let count = try CaptureStaging.copyFile(from: url, to: destination,
                                                               maximumByteCount: ImportPolicy.maximumByteCount)
                        continuation.resume(returning: CopiedRepresentation(byteCount: count, originalName: url.lastPathComponent))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } catch let error as StagingError {
            // A real original that fails size/type validation must not be retried as an alternate encoding.
            throw error
        } catch {
            try Task.checkCancellation()
            // Some image providers offer only data representations. File representations remain preferred.
            return try await withCheckedThrowingContinuation { continuation in
                progress = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let data else {
                        continuation.resume(throwing: StagingError.unsupportedContent)
                        return
                    }
                    do {
                        let count = try CaptureStaging.writeData(data, to: destination,
                                                               maximumByteCount: ImportPolicy.maximumByteCount)
                        continuation.resume(returning: CopiedRepresentation(byteCount: count, originalName: nil))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
