import Foundation
import SwiftData
import BookmarkCore
import BookmarkCloud

extension LibraryStore {
    func queue(_ item: BookmarkItem, action: String = "upsert", migrationSourceKey: String? = nil) throws {
        guard item.scopeID != LibraryScope.device.id else { return }
        guard let owner = session?.userID, LibraryScope.account(userID: owner).id == item.scopeID else { throw LibraryError.notSignedIn }
        var payload: [String: JSONValue] = [
            "title": .string(item.title), "kind": .string(item.kind.rawValue),
            "url": item.url.map { .string($0.absoluteString) } ?? .null,
            "filename": item.filename.map(JSONValue.string) ?? .null,
            "contentType": item.contentType.map(JSONValue.string) ?? .null,
            "byteCount": item.byteCount.map { .number(Double($0)) } ?? .null,
            "note": .string(item.note),
            "collectionID": item.collectionID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "createdAt": .string(BackendDate.string(item.createdAt))
        ]
        if item.kind != .link, let row = try itemRecord(id: item.id, scope: item.scopeID),
           let attachment = row.attachmentID, let hash = row.sha256 {
            let path = "\(owner.uuidString.lowercased())/\(item.id.uuidString.lowercased())/\(attachment)"
            row.storagePath = path
            payload["attachmentID"] = .string(attachment)
            payload["storagePath"] = .string(path)
            payload["sha256"] = .string(hash)
        }
        try enqueue(CloudOperation(operationID: UUID(), entity: "item", action: action, id: item.id,
                                   expectedVersion: item.version, payload: payload),
                    scope: item.scopeID, migrationSourceKey: migrationSourceKey)
    }

    func queue(_ collection: BookmarkCollection, action: String = "upsert") throws {
        guard collection.scopeID != LibraryScope.device.id else { return }
        try enqueue(CloudOperation(operationID: UUID(), entity: "collection", action: action, id: collection.id,
                                   expectedVersion: collection.version,
                                   payload: ["name": .string(collection.name), "tint": .string(collection.tint),
                                             "createdAt": .string(BackendDate.string(collection.createdAt))]), scope: collection.scopeID)
    }

    private func enqueue(_ op: CloudOperation, scope: String, migrationSourceKey: String? = nil) throws {
        let matching = try allPending().filter { $0.scopeID == scope && $0.entity == op.entity && $0.entityID == op.id }
        let source = migrationSourceKey ?? matching.compactMap(\.migrationSourceKey).first
        for pending in matching where (!pending.attempted && !pending.blocked) || (pending.blocked && pending.conflict == nil) { context.delete(pending) }
        // A never-published create can be cancelled locally. An attempted request must be reconciled first.
        if op.action == "delete", op.expectedVersion == 0, !matching.contains(where: \.attempted) {
            if op.entity == "item", let row = try itemRecord(id: op.id, scope: scope) { context.delete(row) }
            if op.entity == "collection", let row = try collectionRecord(id: op.id, scope: scope) { context.delete(row) }
            return
        }
        context.insert(try PendingOperation(op, scopeID: scope, migrationSourceKey: source))
    }

    func validSession() async throws -> AuthSession {
        guard let current = session, let client else { throw LibraryError.notSignedIn }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current }
        let renewed = try await client.refresh(refreshToken: current.refreshToken)
        guard session?.userID == current.userID else { throw LibraryError.notSignedIn }
        try vault.save(renewed)
        session = renewed
        return renewed
    }

    func retrySync() async {
        guard !isSyncing, let client, session != nil, scopeID != LibraryScope.device.id else { return }
        isSyncing = true
        syncFailure = nil
        let syncingScope = scopeID
        defer { isSyncing = false; try? reload() }
        do {
            let authenticated = try await validSession()
            // Manual/foreground retry of rejected requests uses a new identity. Actual
            // transport retries keep their existing operation ID and exact payload.
            for rejected in try allPending() where rejected.scopeID == syncingScope && rejected.blocked && rejected.conflict == nil {
                let old = try rejected.operation()
                let fresh = CloudOperation(operationID: UUID(), entity: old.entity, action: old.action, id: old.id,
                                           expectedVersion: old.expectedVersion, payload: old.payload)
                context.insert(try PendingOperation(fresh, scopeID: syncingScope, migrationSourceKey: rejected.migrationSourceKey))
                context.delete(rejected)
            }
            try context.save()
            try await ingestCaptures()
            while let pending = try allPending().first(where: { $0.scopeID == syncingScope && !$0.blocked }) {
                guard scopeID == syncingScope, session?.userID == authenticated.userID else { return }
                let blockers = try allPending().contains { $0.scopeID == syncingScope && $0.entity == pending.entity && $0.entityID == pending.entityID && $0.blocked }
                if blockers {
                    pending.blocked = true
                    try context.save()
                    continue
                }
                pending.attempted = true
                try context.save()
                let operation = try pending.operation()
                if operation.entity == "item", operation.action == "upsert",
                   let row = try itemRecord(id: operation.id, scope: syncingScope), !row.originalUploaded,
                   let path = row.storagePath, let hash = row.sha256 {
                    let item = try row.value()
                    guard let name = item.localFileName else { throw LibraryError.fileUnavailable }
                    try await client.uploadOriginal(fileURL: originals.url(scopeID: syncingScope, name: name), path: path,
                                                    contentType: item.contentType ?? "application/octet-stream", sha256: hash, session: authenticated)
                    guard session?.userID == authenticated.userID else { return }
                    row.originalUploaded = true
                    try context.save()
                }
                let outcome = try await client.apply(operation, session: authenticated)
                guard scopeID == syncingScope, session?.userID == authenticated.userID else { return }
                if outcome.status == "applied", let record = outcome.record {
                    let later = try allPending().filter { $0.scopeID == syncingScope && $0.entity == pending.entity && $0.entityID == pending.entityID && $0.id != pending.id }
                    if later.isEmpty {
                        try applyRemote(entity: pending.entity, record: record, scope: syncingScope)
                    } else {
                        let version = Int64(record["version"]?.numberValue ?? 0)
                        try rebaseLocal(entity: pending.entity, id: pending.entityID, scope: syncingScope, version: version)
                        for next in later where !next.attempted {
                            let old = try next.operation()
                            let rebased = CloudOperation(operationID: UUID(), entity: old.entity, action: old.action,
                                                         id: old.id, expectedVersion: version, payload: old.payload)
                            context.insert(try PendingOperation(rebased, scopeID: syncingScope, migrationSourceKey: next.migrationSourceKey))
                            context.delete(next)
                        }
                    }
                    if let sourceKey = pending.migrationSourceKey,
                       let source = try context.fetch(FetchDescriptor<StoredItem>()).first(where: { $0.key == sourceKey }) {
                        context.delete(source)
                    }
                    context.delete(pending)
                } else if outcome.status == "conflict" || outcome.record != nil {
                    pending.blocked = true
                    pending.conflict = try JSONEncoder().encode(outcome)
                } else {
                    pending.blocked = true
                    syncFailure = outcome.code ?? "The server could not accept this change."
                }
                try saveAndReload()
            }
            let cursor = try cursorRecord(scope: syncingScope)
            var more = true
            while more {
                let page = try await client.changes(afterRevision: cursor.revision, session: authenticated)
                guard scopeID == syncingScope, session?.userID == authenticated.userID else { return }
                for change in page.changes {
                    try applyChange(change, scope: syncingScope)
                }
                guard page.nextRevision >= cursor.revision, !page.hasMore || page.nextRevision > cursor.revision else {
                    throw LibraryError.remote("Sync received an invalid change cursor. Your local data is safe.")
                }
                cursor.revision = page.nextRevision
                try saveAndReload()
                more = page.hasMore
            }
            hasPulled = true
            retryAttempt = 0
            // Metadata deletion is durable already. Storage cleanup remains
            // retryable through its server queue if this opportunistic call fails.
            try? await client.cleanupOriginals(session: authenticated)
        } catch {
            context.rollback()
            syncFailure = error.localizedDescription
            if let backend = error as? BackendError, backend == .unauthorized || backend == .sessionExpired {
                needsReauthentication = true
            } else if error is URLError || (error as? BackendError).map({ if case .httpStatus(let status) = $0 { return status >= 500 || status == 429 }; return false }) == true {
                retryAttempt += 1
                let delay = min(60.0, pow(2.0, Double(min(retryAttempt, 6))))
                retryTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self, self.scopeID == syncingScope else { return }
                    await self.retrySync()
                }
            }
        }
    }

    func applyChange(_ change: CloudChange, scope: String) throws {
        let pending = try allPending().filter { $0.scopeID == scope && $0.entity == change.entity && $0.entityID == change.id }
        if pending.isEmpty {
            try applyRemote(entity: change.entity, record: change.record, scope: scope)
        } else {
            for blocked in pending where blocked.blocked && blocked.conflict != nil {
                let prior = try JSONDecoder().decode(CloudOutcome.self, from: blocked.conflict!)
                if (change.record["version"]?.numberValue ?? 0) >= (prior.record?["version"]?.numberValue ?? 0) {
                    blocked.conflict = try JSONEncoder().encode(CloudOutcome(status: "conflict", code: "remote_changed", record: change.record, revision: change.revision))
                }
            }
        }
    }

    private func cursorRecord(scope: String) throws -> LibraryCursor {
        if let existing = try context.fetch(FetchDescriptor<LibraryCursor>()).first(where: { $0.scopeID == scope }) { return existing }
        let record = LibraryCursor(scopeID: scope)
        context.insert(record)
        return record
    }

    private func rebaseLocal(entity: String, id: UUID, scope: String, version: Int64) throws {
        if entity == "item", let row = try itemRecord(id: id, scope: scope) {
            var value = try row.value(); value.version = version; try row.setValue(value)
        } else if entity == "collection", let row = try collectionRecord(id: id, scope: scope) {
            var value = try row.value(); value.version = version; try row.setValue(value)
        }
    }

    func applyRemote(entity: String, record: [String: JSONValue], scope: String) throws {
        guard let rawID = record["id"]?.stringValue, let id = UUID(uuidString: rawID),
              let created = record["createdAt"]?.stringValue.flatMap(BackendDate.parse),
              let updated = record["updatedAt"]?.stringValue.flatMap(BackendDate.parse),
              let rawVersion = record["version"]?.numberValue else { throw LibraryError.invalidRecord }
        let deleted = record["deletedAt"]?.stringValue.flatMap(BackendDate.parse)
        if entity == "item" {
            guard let kindValue = record["kind"]?.stringValue, let kind = BookmarkKind(rawValue: kindValue),
                  let title = record["title"]?.stringValue else { throw LibraryError.invalidRecord }
            let existing = try itemRecord(id: id, scope: scope)
            let old = try existing?.value()
            let attachmentID = record["attachmentID"]?.stringValue
            let sameOriginal = existing?.attachmentID == attachmentID
            let value = BookmarkItem(id: id, title: title, kind: kind,
                                     url: record["url"]?.stringValue.flatMap(URL.init(string:)),
                                     filename: record["filename"]?.stringValue,
                                     localFileName: sameOriginal ? old?.localFileName : nil,
                                     contentType: record["contentType"]?.stringValue,
                                     byteCount: record["byteCount"]?.numberValue.map(Int.init),
                                     note: record["note"]?.stringValue ?? "",
                                     collectionID: record["collectionID"]?.stringValue.flatMap(UUID.init(uuidString:)),
                                     createdAt: created, updatedAt: updated, deletedAt: deleted,
                                     version: Int64(rawVersion), scopeID: scope, syncStatus: .synced)
            let row = try existing ?? StoredItem(value)
            if existing == nil { context.insert(row) } else { try row.setValue(value) }
            row.attachmentID = attachmentID
            row.sha256 = record["sha256"]?.stringValue
            row.storagePath = record["storagePath"]?.stringValue
            row.originalUploaded = true
        } else if entity == "collection" {
            guard let name = record["name"]?.stringValue else { throw LibraryError.invalidRecord }
            let value = BookmarkCollection(id: id, name: name, tint: record["tint"]?.stringValue ?? "blue",
                                            createdAt: created, updatedAt: updated, deletedAt: deleted,
                                            version: Int64(rawVersion), scopeID: scope)
            if let row = try collectionRecord(id: id, scope: scope) { try row.setValue(value) }
            else { context.insert(try StoredCollection(value)) }
        } else { throw LibraryError.invalidRecord }
    }

    func downloadOriginal(for item: BookmarkItem) async throws -> URL {
        if let local = fileURL(for: item) { return local }
        guard item.scopeID == scopeID, let client, let row = try itemRecord(id: item.id),
              let path = row.storagePath, let attachmentID = row.attachmentID else { throw LibraryError.fileUnavailable }
        let authenticated = try await validSession()
        let data = try await client.downloadOriginal(path: path, session: authenticated)
        guard scopeID == item.scopeID, session?.userID == authenticated.userID else { throw LibraryError.notSignedIn }
        let ext = (item.filename as NSString?)?.pathExtension ?? ""
        let name = attachmentID + (ext.isEmpty ? "" : "." + ext.filter { $0.isLetter || $0.isNumber })
        let target = try await originals.storeDownload(data, scopeID: item.scopeID, name: name, expectedHash: row.sha256)
        var value = try row.value(); value.localFileName = name; try row.setValue(value)
        try saveAndReload()
        return target
    }

    func resolveConflict(_ conflict: SyncConflict, keepLocal: Bool) throws {
        guard let pending = try allPending().first(where: { $0.id == conflict.id && $0.scopeID == scopeID }),
              let data = pending.conflict,
              let record = try JSONDecoder().decode(CloudOutcome.self, from: data).record else {
            throw LibraryError.remote("This sync issue needs a retry after reconnecting.")
        }
        let related = try allPending().filter { $0.scopeID == scopeID && $0.entity == pending.entity && $0.entityID == pending.entityID }
        let localItem = try itemRecord(id: pending.entityID)?.value()
        let localCollection = try collectionRecord(id: pending.entityID)?.value()
        let originalRow = try itemRecord(id: pending.entityID)
        let originalAttachment = originalRow?.attachmentID
        let originalHash = originalRow?.sha256
        for op in related { context.delete(op) }
        try applyRemote(entity: pending.entity, record: record, scope: scopeID)
        if keepLocal, var item = localItem, pending.entity == "item" {
            if conflict.serverDeleted {
                item.id = UUID(); item.version = 0; item.deletedAt = nil; item.createdAt = Date()
                let copied = try StoredItem(item, attachmentID: originalAttachment == nil ? nil : UUID().uuidString.lowercased(), sha256: originalHash)
                context.insert(copied)
            } else {
                item.version = Int64(record["version"]?.numberValue ?? 0)
            }
            item.syncStatus = .queued
            item.updatedAt = Date()
            if let row = try itemRecord(id: item.id) { try row.setValue(item) }
            try queue(item, action: item.deletedAt == nil ? "upsert" : "delete")
        } else if keepLocal, var collection = localCollection, pending.entity == "collection" {
            if conflict.serverDeleted {
                collection.id = UUID(); collection.version = 0; collection.deletedAt = nil
                context.insert(try StoredCollection(collection))
            } else { collection.version = Int64(record["version"]?.numberValue ?? 0) }
            collection.updatedAt = Date()
            if let row = try collectionRecord(id: collection.id) { try row.setValue(collection) }
            try queue(collection, action: collection.deletedAt == nil ? "upsert" : "delete")
        }
        try saveAndReload()
        scheduleSync()
    }
}
