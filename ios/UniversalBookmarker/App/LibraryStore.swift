import Foundation
import Observation
import SwiftData
import BookmarkCore
import BookmarkCloud

@MainActor @Observable
final class LibraryStore {
    var items: [BookmarkItem] = []
    var collections: [BookmarkCollection] = []
    var scopeID = LibraryScope.device.id
    var errorMessage: String?
    var isBusy = false
    var syncConflicts: [SyncConflict] = []
    var needsReauthentication = false
    var authEmail: String? { needsReauthentication ? nil : session?.email }
    var authStatus: String { needsReauthentication ? "Sign in again to resume sync. Your local saves are safe." : session == nil ? "Save locally or connect your private library." : "Connected to your private library." }
    var hasCloudConfiguration: Bool { client != nil }
    var scopes: [LibraryScope] {
        [.device] + (session.map { [LibraryScope.account(userID: $0.userID)] } ?? [])
    }
    var hasPendingChanges: Bool { accountPendingCount > 0 || accountCaptureCount > 0 }
    var syncMessage: String {
        if scopeID == LibraryScope.device.id { return "On this iPhone" }
        if syncFailure != nil || !syncConflicts.isEmpty { return "Needs attention" }
        if isSyncing { return "Syncing" }
        return pendingCount > 0 ? "Waiting to sync" : (hasPulled ? "Synced" : "Waiting to sync")
    }

    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let originals: OriginalFileStore
    @ObservationIgnored let captureInbox: CaptureInbox?
    @ObservationIgnored let vault = SessionVault()
    @ObservationIgnored let client: BackendClient?
    var session: AuthSession?
    var isSyncing = false
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored var captureImportRunning = false
    @ObservationIgnored var retryAttempt = 0
    var pendingCount = 0
    var accountPendingCount = 0
    var accountCaptureCount = 0
    var syncFailure: String?
    var hasPulled = false

    init(inMemory: Bool = false, baseDirectory: URL? = nil, configuration: BackendConfiguration? = .load()) throws {
        let base = baseDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("UniversalBookmarker")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let schema = Schema([StoredItem.self, StoredCollection.self, PendingOperation.self, LibraryCursor.self, ImportMapping.self])
        let modelConfiguration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: base.appendingPathComponent("Library.store"))
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        originals = OriginalFileStore(rootURL: base.appendingPathComponent("Originals"))
        client = configuration.map { BackendClient(configuration: $0) }
        session = configuration == nil || inMemory ? nil : try vault.read()
        if !inMemory,
           let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
           let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            captureInbox = CaptureInbox(rootURL: directory.appendingPathComponent("CaptureInbox"))
        } else { captureInbox = nil }
        if let session { scopeID = LibraryScope.account(userID: session.userID).id }
        try reload()
    }

    func start() async {
        do {
            try await publishDestination()
            try await refreshCaptureCount()
            try await ingestCaptures()
            try await refreshCaptureCount()
            await retrySync()
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() throws {
        items = try context.fetch(FetchDescriptor<StoredItem>()).filter { $0.scopeID == scopeID }
            .map { try $0.value() }.filter { $0.deletedAt == nil }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        collections = try context.fetch(FetchDescriptor<StoredCollection>()).filter { $0.scopeID == scopeID }
            .map { try $0.value() }.filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let pending = try allPending().filter { $0.scopeID == scopeID }
        pendingCount = pending.count
        accountPendingCount = try allPending().filter { $0.scopeID == session.map({ LibraryScope.account(userID: $0.userID).id }) }.count
        syncConflicts = pending.filter { $0.blocked && $0.conflict != nil }.map { op in
            let title = items.first { $0.id == op.entityID }?.title ?? collections.first { $0.id == op.entityID }?.name ?? "Saved item"
            let outcome = op.conflict.flatMap { try? JSONDecoder().decode(CloudOutcome.self, from: $0) }
            let deleted = outcome?.record?["deletedAt"]?.stringValue != nil
            return SyncConflict(id: op.id, title: title, serverDeleted: deleted)
        }
    }

    func itemRecord(id: UUID, scope: String? = nil) throws -> StoredItem? {
        let key = StoredItem.key(scopeID: scope ?? scopeID, id: id)
        return try context.fetch(FetchDescriptor<StoredItem>()).first { $0.key == key }
    }

    func collectionRecord(id: UUID, scope: String? = nil) throws -> StoredCollection? {
        let key = StoredItem.key(scopeID: scope ?? scopeID, id: id)
        return try context.fetch(FetchDescriptor<StoredCollection>()).first { $0.key == key }
    }

    func allPending() throws -> [PendingOperation] {
        try context.fetch(FetchDescriptor<PendingOperation>()).sorted { $0.createdAt < $1.createdAt }
    }

    func saveAndReload() throws {
        do { try context.save(); try reload() }
        catch { context.rollback(); try? reload(); throw error }
    }

    func addLink(_ input: String, allowDuplicate: Bool = false) async throws {
        let url = try LinkValidator.validate(input)
        if !allowDuplicate, items.contains(where: { $0.url == url }) { throw LibraryError.duplicateLink }
        var item = BookmarkItem(title: url.host ?? url.absoluteString, kind: .link, url: url, scopeID: scopeID)
        item.syncStatus = scopeID == LibraryScope.device.id ? .local : .queued
        let record = try StoredItem(item)
        context.insert(record)
        try queue(item)
        try saveAndReload()
        scheduleSync()
    }

    func importFiles(_ urls: [URL]) async throws {
        guard urls.count <= 20 else { throw LibraryError.remote("Choose up to 20 files at a time.") }
        let destination = scopeID
        isBusy = true
        defer { isBusy = false }
        var failures: [String] = []
        for url in urls {
            do {
                let imported = try await originals.importFile(url, scopeID: destination)
                do {
                    try insertOriginal(imported, scope: destination)
                    try saveAndReload()
                } catch {
                    context.rollback()
                    await originals.remove(scopeID: destination, name: imported.localFileName)
                    throw error
                }
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        scheduleSync()
        if !failures.isEmpty { throw LibraryError.importFailed(failures) }
    }

    func insertOriginal(_ original: ImportedOriginal, scope: String, id: UUID = UUID(), title: String? = nil,
                        note: String = "", collectionID: UUID? = nil, migrationSourceKey: String? = nil) throws {
        let item = BookmarkItem(id: id, title: title ?? original.filename, kind: original.kind,
                                filename: original.filename, localFileName: original.localFileName,
                                contentType: original.contentType, byteCount: original.byteCount, note: note,
                                collectionID: collectionID, scopeID: scope,
                                syncStatus: scope == LibraryScope.device.id ? .local : .queued)
        let record = try StoredItem(item, attachmentID: original.attachmentID.uuidString.lowercased(), sha256: original.sha256)
        context.insert(record)
        try queue(item, migrationSourceKey: migrationSourceKey)
    }

    func updateItem(_ item: BookmarkItem) throws {
        guard item.scopeID == scopeID, let record = try itemRecord(id: item.id) else { throw LibraryError.invalidRecord }
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.remote("Give this save a title.") }
        var edited = try record.value().applyingUserEdits(from: item)
        edited.updatedAt = Date()
        edited.syncStatus = scopeID == LibraryScope.device.id ? .local : .queued
        try record.setValue(edited)
        try queue(edited)
        try saveAndReload()
        scheduleSync()
    }

    func deleteItem(_ item: BookmarkItem) throws {
        guard item.scopeID == scopeID, let record = try itemRecord(id: item.id) else { throw LibraryError.invalidRecord }
        var deleted = try record.value()
        deleted.deletedAt = Date()
        deleted.updatedAt = Date()
        deleted.syncStatus = scopeID == LibraryScope.device.id ? .local : .queued
        try record.setValue(deleted)
        try queue(deleted, action: "delete")
        try saveAndReload()
        scheduleSync()
    }

    func createCollection(name: String, tint: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw LibraryError.remote("Give the collection a name.") }
        let value = BookmarkCollection(name: clean, tint: tint, scopeID: scopeID)
        context.insert(try StoredCollection(value))
        try queue(value)
        try saveAndReload()
        scheduleSync()
    }

    func renameCollection(_ collection: BookmarkCollection, name: String) throws {
        guard collection.scopeID == scopeID, let record = try collectionRecord(id: collection.id) else { throw LibraryError.invalidCollection }
        var edited = collection
        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.name.isEmpty else { throw LibraryError.remote("Give the collection a name.") }
        edited.updatedAt = Date()
        try record.setValue(edited)
        try queue(edited)
        try saveAndReload()
        scheduleSync()
    }

    func deleteCollection(_ collection: BookmarkCollection) throws {
        guard collection.scopeID == scopeID, let record = try collectionRecord(id: collection.id) else { throw LibraryError.invalidCollection }
        var deleted = collection
        deleted.deletedAt = Date()
        deleted.updatedAt = Date()
        try record.setValue(deleted)
        for row in try context.fetch(FetchDescriptor<StoredItem>()) where row.scopeID == scopeID {
            var item = try row.value()
            guard item.collectionID == collection.id, item.deletedAt == nil else { continue }
            item.collectionID = nil
            item.updatedAt = Date()
            item.syncStatus = scopeID == LibraryScope.device.id ? .local : .queued
            try row.setValue(item)
            try queue(item)
        }
        try queue(deleted, action: "delete")
        try saveAndReload()
        scheduleSync()
    }

    func moveItem(_ item: BookmarkItem, to collectionID: UUID?) throws {
        if let collectionID, !collections.contains(where: { $0.id == collectionID }) { throw LibraryError.invalidCollection }
        var moved = item
        moved.collectionID = collectionID
        try updateItem(moved)
    }

    func fileURL(for item: BookmarkItem) -> URL? {
        guard item.scopeID == scopeID, let name = item.localFileName else { return nil }
        let url = originals.url(scopeID: item.scopeID, name: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func loadDemoLibrary() throws {
        guard scopeID == LibraryScope.device.id, items.isEmpty, collections.isEmpty else {
            throw LibraryError.remote("Sample content can only be added to an empty on-device library.")
        }
        let names = [("Travel", "green"), ("Reading", "blue"), ("Inspiration", "purple"), ("Work", "yellow")]
        for (name, tint) in names { context.insert(try StoredCollection(BookmarkCollection(name: name, tint: tint))) }
        let samples = [("Japan travel guide", "https://www.japan-guide.com"), ("Apple Human Interface Guidelines", "https://developer.apple.com/design/human-interface-guidelines/"), ("A place for your ideas", "https://www.are.na/")]
        for (title, link) in samples {
            context.insert(try StoredItem(BookmarkItem(title: title, kind: .link, url: URL(string: link), note: "Sample content", scopeID: scopeID)))
        }
        try saveAndReload()
    }

    func scheduleSync() {
        guard client != nil, session != nil, scopeID != LibraryScope.device.id else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.retrySync()
        }
    }

    func publishDestination() async throws {
        if let captureInbox { try await captureInbox.writeDestination(DestinationDescriptor(scopeID: scopeID)) }
    }

    func refreshCaptureCount() async throws {
        guard let session, let captureInbox else { accountCaptureCount = 0; return }
        accountCaptureCount = try await captureInbox.pending(scopeID: LibraryScope.account(userID: session.userID).id).count
    }

    func ingestCaptures() async throws {
        guard !captureImportRunning, let captureInbox else { return }
        captureImportRunning = true
        defer { captureImportRunning = false }
        let destination = scopeID
        for manifest in try await captureInbox.pending(scopeID: destination) {
            // Capture UUID maps to the first item; attachment IDs map to subsequent items.
            // This survives a crash after save but before manifest acknowledgement.
            let firstID = manifest.id
            if let url = manifest.url, try itemRecord(id: firstID, scope: destination) == nil {
                let item = BookmarkItem(id: firstID, title: manifest.title.isEmpty ? (url.host ?? url.absoluteString) : manifest.title,
                                        kind: .link, url: url, note: manifest.note, scopeID: destination,
                                        syncStatus: destination == LibraryScope.device.id ? .local : .queued)
                context.insert(try StoredItem(item))
                try queue(item)
                try saveAndReload()
            }
            for (index, attachment) in manifest.attachments.enumerated() {
                let id = manifest.url == nil && index == 0 ? firstID : attachment.id
                if try itemRecord(id: id, scope: destination) != nil { continue }
                let source = try await captureInbox.fileURL(for: attachment, in: manifest)
                let copied = try await originals.importFile(source, scopeID: destination)
                let original = ImportedOriginal(attachmentID: copied.attachmentID, localFileName: copied.localFileName,
                                                 filename: attachment.filename, kind: attachment.kind,
                                                 contentType: attachment.contentType ?? copied.contentType,
                                                 byteCount: copied.byteCount, sha256: copied.sha256)
                do {
                    try insertOriginal(original, scope: destination, id: id,
                                       title: manifest.title.isEmpty ? attachment.filename : manifest.title, note: manifest.note)
                    try saveAndReload()
                } catch {
                    context.rollback()
                    await originals.remove(scopeID: destination, name: original.localFileName)
                    throw error
                }
            }
            try await captureInbox.acknowledge(manifest)
        }
    }
}
