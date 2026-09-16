import NotabilityCore
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
    @State private var allowFingerDrawing = false
    @State private var headerAlignment = "center"
    @State private var dateFormat = ""
    @State private var timeFormat = ""

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

                Section("Drawing") {
                    Toggle("Draw with finger", isOn: $allowFingerDrawing)
                        .accessibilityIdentifier("fingerPaintingToggle")
                        .onChange(of: allowFingerDrawing) { _, new in
                            AppSettings.shared.allowFingerDrawing = new
                        }
                    Text("First Pencil scribble turns finger painting off. Turning it back on here keeps it on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Page") {
                    Picker("Date alignment", selection: $headerAlignment) {
                        Text("Left").tag("leading")
                        Text("Center").tag("center")
                        Text("Right").tag("trailing")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("headerAlignment")
                    .onChange(of: headerAlignment) { _, new in
                        AppSettings.shared.pageHeaderAlignmentRaw = new
                    }
                    TextField("Date format (e.g. MMM d, yyyy)", text: $dateFormat)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("dateFormat")
                        .onChange(of: dateFormat) { _, new in
                            if new.isEmpty || PageHeaderFormat.isValidFormat(new) {
                                AppSettings.shared.pageDateFormat = new
                            }
                        }
                    TextField("Time format (e.g. h:mm a)", text: $timeFormat)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("timeFormat")
                        .onChange(of: timeFormat) { _, new in
                            if new.isEmpty || PageHeaderFormat.isValidFormat(new) {
                                AppSettings.shared.pageTimeFormat = new
                            }
                        }
                    if !dateFormat.isEmpty, !PageHeaderFormat.isValidFormat(dateFormat) {
                        Text("Date format not recognized — keeping previous value.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !timeFormat.isEmpty, !PageHeaderFormat.isValidFormat(timeFormat) {
                        Text("Time format not recognized — keeping previous value.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Blank formats fall back to the default. Applies when a page is opened.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        allowFingerDrawing = AppSettings.shared.allowFingerDrawing
        headerAlignment = AppSettings.shared.pageHeaderAlignmentRaw
        dateFormat = AppSettings.shared.pageDateFormat
        timeFormat = AppSettings.shared.pageTimeFormat
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
