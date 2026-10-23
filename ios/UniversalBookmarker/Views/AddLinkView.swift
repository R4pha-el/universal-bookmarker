import SwiftUI
import BookmarkCore

struct AddLinkView: View {
    let store: LibraryStore
    @State private var input = ""
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var showDuplicate = false
    @State private var existingItem: BookmarkItem?
    @State private var showExisting = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $input)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().focused($focused)
                        .accessibilityIdentifier("link.url")
                        .onSubmit { validateAndSave() }
                } header: { Text("Website address") }
                footer: { Text("Saved to your library. A collection is optional.") }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                if saving { ProgressView("Saving link…") }
            }
            .navigationTitle("Add a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: validateAndSave)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                        .accessibilityIdentifier("link.save")
                }
            }
            .confirmationDialog("You’ve saved this link before", isPresented: $showDuplicate, titleVisibility: .visible) {
                Button("Open existing") { showExisting = true }
                Button("Save again") { save(allowDuplicate: true) }
            }
            .navigationDestination(isPresented: $showExisting) {
                if let existingItem { ItemDetailView(store: store, item: existingItem) }
            }
            .onAppear { focused = true }
        }
    }

    private func validateAndSave() {
        guard !saving else { return }
        do {
            let url = try LinkValidator.validate(input)
            existingItem = store.items.first { $0.kind == .link && $0.url == url && $0.deletedAt == nil }
            if existingItem != nil { showDuplicate = true } else { save() }
        } catch { errorMessage = error.localizedDescription }
    }

    private func save(allowDuplicate: Bool = false) {
        saving = true
        errorMessage = nil
        Task {
            do { try await store.addLink(input, allowDuplicate: allowDuplicate); dismiss() }
            catch { errorMessage = error.localizedDescription }
            saving = false
        }
    }
}
