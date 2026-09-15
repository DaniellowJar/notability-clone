import SwiftUI

/// Settings / onboarding (Phase 13): DeepInfra API key (BYOK) and OwnCloud
/// sync credentials, stored in the Keychain only.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var deepInfraKey = ""
    @State private var ownCloudURL = ""
    @State private var ownCloudUser = ""
    @State private var ownCloudPassword = ""
    @State private var message: String?
    @State private var showKey = false
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bring-your-own-key: keys are stored in the iOS Keychain, never in app storage or logs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("DeepInfra (AI)") {
                    HStack {
                        Group {
                            if showKey {
                                TextField("API key", text: $deepInfraKey)
                            } else {
                                SecureField("API key", text: $deepInfraKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                    }
                    .accessibilityIdentifier("deepInfraKey")
                }

                Section("OwnCloud sync") {
                    TextField("Server URL (https://…)", text: $ownCloudURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ownCloudURL")
                    TextField("Username", text: $ownCloudUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ownCloudUser")
                    SecureField("Password", text: $ownCloudPassword)
                        .accessibilityIdentifier("ownCloudPassword")
                }

                Section {
                    Button("Save") { save() }
                        .accessibilityIdentifier("settingsSave")
                }

                Section("Sync") {
                    Button {
                        Task { await syncNow() }
                    } label: {
                        HStack {
                            Text("Sync with OwnCloud now")
                            Spacer()
                            if syncing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(syncing)
                    .accessibilityIdentifier("syncNow")
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(message.contains("saved") || message.contains("Synced") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let secrets = AppSecrets.shared
        deepInfraKey = secrets.deepInfraKey ?? ""
        ownCloudURL = secrets.ownCloudURL ?? ""
        ownCloudUser = secrets.ownCloudUser ?? ""
        ownCloudPassword = secrets.ownCloudPassword ?? ""
    }

    private func save() {
        do {
            try AppSecrets.shared.saveDeepInfraKey(deepInfraKey.trimmingCharacters(in: .whitespacesAndNewlines))
            try AppSecrets.shared.saveOwnCloud(
                url: ownCloudURL.trimmingCharacters(in: .whitespacesAndNewlines),
                user: ownCloudUser.trimmingCharacters(in: .whitespacesAndNewlines),
                password: ownCloudPassword
            )
            message = "Saved to Keychain."
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    private func syncNow() async {
        syncing = true
        let service = SyncService(store: AppStore.shared.store)
        do {
            try await service.sync()
            message = "Synced with OwnCloud."
        } catch {
            message = "Sync failed: \(error.localizedDescription)"
        }
        syncing = false
    }
}
