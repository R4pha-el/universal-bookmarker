import SwiftUI

struct AddToLibraryView: View {
    let choose: (AddSource) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { choose(.link) } label: {
                        Label("Add a link", systemImage: "link")
                    }.accessibilityIdentifier("add.link")
                    Button { choose(.photos) } label: {
                        Label("Choose photos", systemImage: "photo.on.rectangle")
                    }.accessibilityIdentifier("add.photos")
                    Button { choose(.files) } label: {
                        Label("Choose files", systemImage: "doc")
                    }.accessibilityIdentifier("add.files")
                } footer: {
                    Text("Screenshots are photos. PDFs are files. Choose up to 20 items, up to 25 MB each. You can organise them later.")
                }
            }
            .navigationTitle("Add to library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
