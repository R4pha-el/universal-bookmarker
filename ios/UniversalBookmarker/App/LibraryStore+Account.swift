import Foundation
import SwiftData
import BookmarkCore
import BookmarkCloud

extension LibraryStore {
    func requestSignInCode(email: String) async throws {
        guard let client else { throw LibraryError.cloudNotConfigured }
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.contains("@"), clean.contains("."), !clean.contains(" ") else { throw LibraryError.remote("Enter a valid email address.") }
        try await client.requestCode(email: clean)
    }

    func verifySignInCode(email: String, code: String) async throws {
        guard let client else { throw LibraryError.cloudNotConfigured }
        guard !captureImportRunning else { throw LibraryError.remote("Wait for the shared capture to finish importing.") }
        let authenticated = try await client.verifyCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code)
        if let current = session, current.userID != authenticated.userID { throw LibraryError.remote("Sign out before connecting a different account.") }
        try vault.save(authenticated)
        session = authenticated
        needsReauthentication = false
        scopeID = LibraryScope.account(userID: authenticated.userID).id
        hasPulled = false
        syncFailure = nil
        try reload()
        try await publishDestination()
        await retrySync()
    }

    func switchScope(to destination: String) async throws {
        guard scopes.contains(where: { $0.id == destination }) else { throw LibraryError.notSignedIn }
        guard !isSyncing, !isBusy, !captureImportRunning else { throw LibraryError.remote("Wait for the current save or sync to finish, then switch libraries.") }
        scopeID = destination
        errorMessage = nil
        syncFailure = nil
        hasPulled = false
        try reload()
        try await publishDestination()
        try await ingestCaptures()
        await retrySync()
    }

    func signOut(discardPending: Bool = false) async throws {
        guard let authenticated = session else { return }
        guard !isSyncing, !isBusy, !captureImportRunning else { throw LibraryError.remote("Wait for the current save or sync to finish before signing out.") }
        let accountScope = LibraryScope.account(userID: authenticated.userID).id
        let pending = try allPending().filter { $0.scopeID == accountScope }
        let captures = try await captureInbox?.pending(scopeID: accountScope) ?? []
        if !discardPending, !pending.isEmpty || !captures.isEmpty { throw LibraryError.pendingChanges }
        // Stop new captures targeting this account before clearing its local cache.
        scopeID = LibraryScope.device.id
        try await publishDestination()
        if discardPending {
            for capture in captures { try await captureInbox?.acknowledge(capture) }
        }
        try vault.clear()
        session = nil
        needsReauthentication = false
        retryTask?.cancel()
        try purgeAccountCache(scope: accountScope)
        if let client { try? await client.signOut(accessToken: authenticated.accessToken) }
        syncFailure = nil
        hasPulled = false
        try reload()
        // Late manifests retain their old scope and remain quarantined until that account returns.
    }

    func deleteAccount() async throws {
        guard let client else { throw LibraryError.cloudNotConfigured }
        guard !isSyncing, !isBusy, !captureImportRunning else { throw LibraryError.remote("Wait for the current operation to finish before deleting the account.") }
        let authenticated = try await validSession()
        let accountScope = LibraryScope.account(userID: authenticated.userID).id
        try await client.deleteAccount(session: authenticated)
        scopeID = LibraryScope.device.id
        try await publishDestination()
        try vault.clear()
        session = nil
        try purgeAccountCache(scope: accountScope)
        if let captureInbox {
            for capture in try await captureInbox.pending(scopeID: accountScope) { try await captureInbox.acknowledge(capture) }
        }
        syncFailure = nil
        hasPulled = false
        try reload()
    }

    private func purgeAccountCache(scope: String) throws {
        var files: [URL] = []
        for row in try context.fetch(FetchDescriptor<StoredItem>()) where row.scopeID == scope {
            if let name = try row.value().localFileName { files.append(originals.url(scopeID: scope, name: name)) }
            context.delete(row)
        }
        for row in try context.fetch(FetchDescriptor<StoredCollection>()) where row.scopeID == scope { context.delete(row) }
        for row in try allPending() where row.scopeID == scope { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LibraryCursor>()) where row.scopeID == scope { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<ImportMapping>()) where row.key.hasPrefix(scope + "/") { context.delete(row) }
        try saveAndReload()
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    func importDeviceLibrary() async throws {
        guard let authenticated = session else { throw LibraryError.notSignedIn }
        guard !isSyncing, !isBusy, !captureImportRunning else { throw LibraryError.remote("Wait for the current operation to finish before importing.") }
        let destination = LibraryScope.account(userID: authenticated.userID).id
        guard scopeID == destination else { throw LibraryError.remote("Switch to your account library before importing device saves.") }
        isBusy = true
        defer { isBusy = false }
        let deviceItems = try context.fetch(FetchDescriptor<StoredItem>()).filter { $0.scopeID == LibraryScope.device.id }
        let deviceCollections = try context.fetch(FetchDescriptor<StoredCollection>()).filter { $0.scopeID == LibraryScope.device.id }
        var collectionMap: [UUID: UUID] = [:]
        for source in deviceCollections {
            let value = try source.value()
            guard value.deletedAt == nil else { continue }
            let key = destination + "/collection/" + value.id.uuidString
            let mapping = try context.fetch(FetchDescriptor<ImportMapping>()).first { $0.key == key }
            let targetID = mapping?.targetID ?? UUID()
            collectionMap[value.id] = targetID
            if try collectionRecord(id: targetID, scope: destination) == nil {
                let copy = BookmarkCollection(id: targetID, name: value.name, tint: value.tint, scopeID: destination)
                context.insert(try StoredCollection(copy))
                try queue(copy)
                if mapping == nil { context.insert(ImportMapping(key: key, targetID: targetID)) }
            }
        }
        try saveAndReload()
        for source in deviceItems {
            let value = try source.value()
            guard value.deletedAt == nil else { continue }
            if try allPending().contains(where: { $0.scopeID == destination && $0.migrationSourceKey == source.key }) { continue }
            let targetID = UUID()
            let collectionID = value.collectionID.flatMap { collectionMap[$0] }
            if value.kind == .link {
                let copy = BookmarkItem(id: targetID, title: value.title, kind: .link, url: value.url,
                                        note: value.note, collectionID: collectionID, createdAt: value.createdAt,
                                        scopeID: destination, syncStatus: .queued)
                context.insert(try StoredItem(copy))
                try queue(copy, migrationSourceKey: source.key)
                try saveAndReload()
            } else if let name = value.localFileName {
                let original = try await originals.importFile(originals.url(scopeID: LibraryScope.device.id, name: name), scopeID: destination)
                do {
                    try insertOriginal(original, scope: destination, id: targetID, title: value.title,
                                       note: value.note, collectionID: collectionID, migrationSourceKey: source.key)
                    try saveAndReload()
                } catch {
                    context.rollback()
                    await originals.remove(scopeID: destination, name: original.localFileName)
                    throw error
                }
            }
        }
        scheduleSync()
    }
}
