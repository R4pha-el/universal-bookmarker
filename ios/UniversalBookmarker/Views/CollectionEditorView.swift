import SwiftUI

struct CollectionEditorView: View {
    @State var name = ""
    @State var tint = "lavender"
    var isRenaming = false
    let save: (String, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    private let colors = ["lavender", "rose", "peach", "mint", "blue"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Collection name", text: $name).focused($focused)
                    .accessibilityIdentifier("collection.name")
                if !isRenaming {
                    Picker("Color", selection: $tint) {
                        ForEach(colors, id: \.self) { color in
                            Label(color.capitalized, systemImage: "folder.fill")
                                .foregroundStyle(LibraryDesign.tint(color)).tag(color)
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(isRenaming ? "Rename collection" : "New collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveCollection)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveCollection() {
        do {
            try save(name.trimmingCharacters(in: .whitespacesAndNewlines), tint)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
