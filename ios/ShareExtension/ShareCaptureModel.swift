import Foundation
import SwiftUI
@preconcurrency import UIKit
import BookmarkCore

@MainActor
final class ShareCaptureModel: ObservableObject {
    enum Phase { case loading, review, saving, saved, failed }

    @Published private(set) var phase: Phase = .loading
    @Published var title = ""
    @Published var note = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var content = LoadedShareContent()
    @Published private(set) var destinationName = "Library"

    private let loader = ShareItemLoader()
    private let captureID = UUID()
    private let providers: [NSItemProvider]
    private var inbox: CaptureInbox?
    private var destination: DestinationDescriptor?
    private var stagingURL: URL?
    private var task: Task<Void, Never>?

    init(providers: [NSItemProvider]) { self.providers = providers }

    func start() {
        guard task == nil else { return }
        phase = .loading
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                let inbox = try self.configuredInbox()
                // Read exactly once, before awaiting any item provider. Retain across retries.
                if self.destination == nil {
                    do { self.destination = try await inbox.readDestination() }
                    catch { throw CaptureError.destinationUnavailable }
                }
                self.inbox = inbox
                self.destinationName = self.destination?.scopeID == LibraryScope.device.id
                    ? "On this iPhone" : "Connected library"
                try Task.checkCancellation()
                guard !self.providers.isEmpty else { throw StagingError.unsupportedContent }
                let staging = try self.makeStagingDirectory()
                self.stagingURL = staging
                let loaded = try await self.loader.load(self.providers, stagingURL: staging)
                try Task.checkCancellation()
                guard !loaded.isEmpty else {
                    throw CaptureError.noReadableContent(loaded.issues.first ?? StagingError.unsupportedContent.localizedDescription)
                }
                self.content = loaded
                self.title = loaded.defaultTitle
                self.phase = .review
            } catch is CancellationError {
                self.removeStaging()
            } catch {
                self.removeStaging()
                self.errorMessage = error.localizedDescription
                self.phase = .failed
            }
        }
    }

    func save() {
        guard task == nil, !content.isEmpty, let destination, let inbox else { return }
        phase = .saving
        errorMessage = nil
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifest = CaptureManifest(id: captureID, destination: destination,
                                       title: cleanedTitle.isEmpty ? content.defaultTitle : cleanedTitle,
                                       url: content.url, note: note, attachments: content.attachments)
        let files = content.files
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                try Task.checkCancellation()
                try await inbox.publish(manifest, files: files)
                // This is the only transition that exposes the saved message.
                self.phase = .saved
                self.removeStaging()
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase = .failed
            }
        }
    }

    func retry() {
        if !content.isEmpty { phase = .review; errorMessage = nil }
        else { start() }
    }

    func cancel() {
        // Saving is a short durable transaction. UI disables Cancel until its result is known.
        guard phase != .saving else { return }
        task?.cancel()
        loader.cancel()
        removeStaging()
    }

    private func configuredInbox() throws -> CaptureInbox {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !identifier.isEmpty, !identifier.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw CaptureError.appGroupUnavailable
        }
        return CaptureInbox(rootURL: container.appendingPathComponent("CaptureInbox", isDirectory: true))
    }

    private func makeStagingDirectory() throws -> URL {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw CaptureError.appGroupUnavailable
        }
        let staging = container.appendingPathComponent("CaptureStaging", isDirectory: true)
            .appendingPathComponent(captureID.uuidString, isDirectory: true)
        // Retry imports start from a clean, unpublished staging directory.
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return staging
    }

    private func removeStaging() {
        if let stagingURL { try? FileManager.default.removeItem(at: stagingURL) }
        stagingURL = nil
    }
}

private enum CaptureError: LocalizedError {
    case appGroupUnavailable
    case destinationUnavailable
    case noReadableContent(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "Shared storage is unavailable. Open Universal Bookmarker once, then try sharing again. If this continues, reinstall a build with its App Group configured."
        case .destinationUnavailable:
            "Your saving destination is unavailable. Open Universal Bookmarker once, then try sharing again."
        case .noReadableContent(let reason): reason
        }
    }
}
