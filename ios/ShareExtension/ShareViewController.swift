import SwiftUI
import UIKit

/// NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController
@MainActor
public final class ShareViewController: UIViewController {
    private var captureModel: ShareCaptureModel?

    public override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let model = ShareCaptureModel(providers: providers)
        captureModel = model
        let content = ShareCaptureView(model: model,
                                       cancel: { [weak self] in self?.cancelCapture() },
                                       done: { [weak self] in self?.completeCapture() })
        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        model.start()
    }

    private func cancelCapture() {
        captureModel?.cancel()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func completeCapture() {
        guard captureModel?.phase == .saved else { return }
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct ShareCaptureView: View {
    @ObservedObject var model: ShareCaptureModel
    let cancel: () -> Void
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("Preparing your save…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    review
                case .saving:
                    ProgressView("Saving on this iPhone…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .saved:
                    ContentUnavailableView {
                        Label("Saved", systemImage: "checkmark.circle")
                    } description: {
                        Text("Saved on this iPhone. Open Universal Bookmarker to sync.")
                    } actions: {
                        Button("Done", action: done).buttonStyle(.borderedProminent)
                    }
                case .failed:
                    ContentUnavailableView {
                        Label("Couldn’t save", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(model.errorMessage ?? "Try sharing this item again.")
                    } actions: {
                        Button("Try again", action: model.retry).buttonStyle(.borderedProminent)
                        Button("Cancel", role: .cancel, action: cancel)
                    }
                }
            }
            .navigationTitle("Save to library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.phase != .saved {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: cancel)
                            .disabled(model.phase == .saving)
                    }
                }
                if model.phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: model.save).fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(model.phase == .saving)
        }
    }

    private var review: some View {
        Form {
            Section {
                TextField("Title (optional)", text: $model.title)
                TextField("Note (optional)", text: $model.note, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Saving to") {
                Label(model.destinationName, systemImage: "tray")
                Text("No collection required")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Shared content") {
                if let url = model.content.url {
                    Label(url.absoluteString, systemImage: "link")
                        .lineLimit(3).textSelection(.enabled)
                }
                ForEach(model.content.attachments, id: \.id) { attachment in
                    Label(attachment.filename, systemImage: "doc")
                }
            }
            if !model.content.issues.isEmpty {
                Section("Some items couldn’t be included") {
                    ForEach(Array(model.content.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                    Text("Save will include only the content listed above.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
