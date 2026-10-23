import SwiftUI
import BookmarkCore

struct AccountView: View {
    let store: LibraryStore
    @State private var email = ""
    @State private var code = ""
    @State private var codeRequested = false
    @State private var resendAvailableAt = Date.distantPast
    @State private var working = false
    @State private var errorMessage: String?
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var showImport = false
    @State private var showDemo = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                AccountAtmosphere().frame(height: 430)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("UNIVERSAL\nBOOKMARKER")
                                .font(.title2).bold().tracking(3)
                                .accessibilityLabel("Universal Bookmarker")
                            Text(store.authEmail == nil ? "A home for everything\nyou want to keep." : "Your library,\nwherever you are.")
                                .font(.largeTitle).bold().fixedSize(horizontal: false, vertical: true)
                            Text(store.syncMessage).foregroundStyle(.secondary)
                                .accessibilityIdentifier("account.syncStatus")
                        }.padding(.top, 25)
                        if let accountEmail = store.authEmail {
                            AccountConnectedView(store: store, email: accountEmail, working: working, importSaves: { showImport = true }, signOut: { showSignOut = true }, deleteAccount: { showDelete = true }, perform: perform)
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                Text("Connect sync").font(.title2).bold()
                                Text("Keep saving on this iPhone, or connect your account to sync your private library.")
                                    .foregroundStyle(.secondary)
                                if store.hasCloudConfiguration {
                                    TextField("Email address", text: $email)
                                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                                        .padding().background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
                                        .disabled(working || codeRequested)
                                        .accessibilityIdentifier("account.email")
                                    if codeRequested {
                                        TextField("Email code", text: $code)
                                            .textContentType(.oneTimeCode).keyboardType(.numberPad)
                                            .padding().background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
                                            .accessibilityIdentifier("account.code")
                                        Text("Enter the latest code from your email. If it has expired, request a new one.")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        Button("Connect library", action: verifyCode)
                                            .buttonStyle(.borderedProminent).controlSize(.large)
                                            .disabled(working || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        TimelineView(.periodic(from: .now, by: 1)) { context in
                                            let remaining = max(0, Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up)))
                                            Button(remaining > 0 ? "Resend code in \(remaining)s" : "Resend code", action: requestCode)
                                                .disabled(working || remaining > 0)
                                        }
                                        Button("Use another email") { codeRequested = false; code = "" }
                                            .disabled(working)
                                    } else {
                                        Button("Email me a code", action: requestCode)
                                            .buttonStyle(.borderedProminent).controlSize(.large)
                                            .disabled(working || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                            .accessibilityIdentifier("account.requestCode")
                                    }
                                } else {
                                    Label("Saving on this iPhone", systemImage: "iphone")
                                    Text("Cloud sync is not configured for this build. Your local library is ready to use.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                if store.items.isEmpty {
                                    Button("Explore an example library") { showDemo = true }.disabled(working)
                                }
                            }
                        }
                        if working { ProgressView("Please wait…") }
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red)
                                .accessibilityIdentifier("account.error")
                        } else if let storeError = store.errorMessage {
                            Text(storeError).foregroundStyle(.red)
                        }
                        Text(store.authStatus).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(LibraryDesign.inset)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Sign out?", isPresented: $showSignOut, titleVisibility: .visible) {
                if store.hasPendingChanges {
                    Button("Sync and sign out") {
                        perform { await store.retrySync(); try await store.signOut() }
                    }
                    Button("Discard pending work and sign out", role: .destructive) {
                        perform { try await store.signOut(discardPending: true) }
                    }
                } else {
                    Button("Sign out", role: .destructive) { perform { try await store.signOut() } }
                }
            } message: {
                Text(store.hasPendingChanges ? "Some account changes or Share captures have not synced. Sync them first, or explicitly discard this account’s pending local work." : "This account’s cached library will be removed from this iPhone.")
            }
            .confirmationDialog("Permanently delete your account?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete account and all cloud saves", role: .destructive) { perform { try await store.deleteAccount() } }
            } message: { Text("This permanently removes your account, saved items, collections, and cloud originals. This cannot be undone.") }
            .confirmationDialog("Import this iPhone’s saves?", isPresented: $showImport, titleVisibility: .visible) {
                Button("Import into my account") { perform { try await store.importDeviceLibrary() } }
                Button("Keep separate", role: .cancel) {}
            } message: { Text("Copies will be added to the connected account. Device originals stay safe until upload is acknowledged. You can keep using the separate On this iPhone library.") }
            .confirmationDialog("Load example saves?", isPresented: $showDemo, titleVisibility: .visible) {
                Button("Load example library") { perform { try store.loadDemoLibrary() } }
            } message: { Text("This adds clearly labelled example links to your current library.") }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private func requestCode() {
        perform {
            try await store.requestSignInCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            codeRequested = true
            resendAvailableAt = .now.addingTimeInterval(60)
        }
    }

    private func verifyCode() {
        perform {
            try await store.verifySignInCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            code = ""
            codeRequested = false
            showImport = true
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
