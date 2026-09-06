import AppKit
import SwiftUI

/// Per-app formatting: one row per app, matched on bundle ID. Apps are added
/// from the list of apps currently running (Settings itself is frontmost, so
/// "add the current app" would always mean Goji).
struct AppsPane: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        PaneScaffold(title: "Apps", subtitle: "How text lands in each app. Anything unset follows Transcription.") {
            SectionHeader("Per-app formatting")
            SettingsCard {
                if settings.appProfiles.isEmpty {
                    Text("No app rules yet. Add one below.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
                ForEach($settings.appProfiles) { $profile in
                    AppProfileRow(profile: $profile) {
                        settings.appProfiles.removeAll { $0.id == profile.id }
                    }
                    Divider()
                }
                SettingsRow("Add an app", subtitle: "Pick from what's running right now.") {
                    Menu("Add App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button {
                                add(app)
                            } label: {
                                Label {
                                    Text(app.localizedName ?? app.bundleIdentifier ?? "App")
                                } icon: {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                    }
                                }
                            }
                            .disabled(settings.appProfiles.contains { $0.bundleID == app.bundleIdentifier })
                        }
                    }
                    .frame(width: 110)
                }
            }
            CaptionText("lowercase keeps names, acronyms, and your replacements in their exact case. AI cleanup off means Apple Intelligence never touches text for that app, handy for editors and terminals.")
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0 != .current }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        settings.appProfiles.append(AppProfile(bundleID: bundleID, name: app.localizedName ?? bundleID))
    }
}

private struct AppProfileRow: View {
    @Binding var profile: AppProfile
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: profile.icon ?? NSWorkspace.shared.icon(for: .application))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text(profile.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("Casing", selection: $profile.casing) {
                ForEach(AppProfile.Casing.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
            .help("Casing")
            Picker("Full stop", selection: $profile.trailingFullStop) {
                ForEach(AppProfile.TrailingFullStop.allCases, id: \.self) { Text("Full stop: \($0.label)").tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            .help("Full stop at the end")
            Toggle("AI", isOn: $profile.aiCleanup)
                .toggleStyle(.checkbox)
                .help("Apple Intelligence cleanup for this app")
            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }
}
