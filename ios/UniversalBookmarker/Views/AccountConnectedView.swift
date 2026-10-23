import SwiftUI
import BookmarkCore

struct AccountConnectedView: View {
    let store: LibraryStore
    let email: String
    let working: Bool
    let importSaves: () -> Void
    let signOut: () -> Void
    let deleteAccount: () -> Void
    let perform: (@escaping @MainActor () async throws -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(email, systemImage: "person.crop.circle").font(.headline)
            Menu {
                ForEach(store.scopes) { scope in
                    Button {
                        perform { try await store.switchScope(to: scope.id) }
                    } label: {
                        if scope.id == store.scopeID { Label(scope.name, systemImage: "checkmark") }
                        else { Text(scope.name) }
                    }
                }
            } label: {
                Label(store.scopes.first(where: { $0.id == store.scopeID })?.name ?? "Current library", systemImage: "books.vertical")
            }.disabled(working)
            Button("Retry sync", systemImage: "arrow.triangle.2.circlepath") {
                perform { await store.retrySync() }
            }.disabled(working || !store.hasCloudConfiguration)
            if store.scopeID != LibraryScope.device.id {
                Button("Import saves from this iPhone", systemImage: "square.and.arrow.up.on.square", action: importSaves)
                    .disabled(working)
            }
            ForEach(store.syncConflicts) { conflict in
                VStack(alignment: .leading, spacing: 12) {
                    Label("Changes need a decision", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.headline)
                    Text(conflict.title).foregroundStyle(.secondary)
                    Button(conflict.serverDeleted ? "Save as new item" : "Keep this device’s edit") {
                        perform { try store.resolveConflict(conflict, keepLocal: true) }
                    }
                    Button("Use synced version") {
                        perform { try store.resolveConflict(conflict, keepLocal: false) }
                    }
                }.padding().background(.white.opacity(0.06), in: .rect(cornerRadius: 15))
            }
            Divider()
            Button("Sign out", action: signOut).disabled(working)
            Button("Delete account", role: .destructive, action: deleteAccount).disabled(working)
        }
    }
}
