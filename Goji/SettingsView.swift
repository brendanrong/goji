import AppKit
import SwiftUI

/// Sidebar-style settings shell (same pattern as LiveWall): navigation on the
/// left, one pane at a time on the right. Pane content lives in SettingsPanes.swift.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general
        case microphone
        case transcription
        case models
        case history
        case about

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return "General"
            case .microphone: return "Microphone"
            case .transcription: return "Transcription"
            case .models: return "Models"
            case .history: return "History"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .microphone: return "mic"
            case .transcription: return "wand.and.stars"
            case .models: return "cpu"
            case .history: return "clock"
            case .about: return "info.circle"
            }
        }
    }

    @State private var pane: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 780, height: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { item in
                SidebarRow(label: item.label, icon: item.icon, selected: pane == item) {
                    pane = item
                }
            }
            Spacer()
            Divider()
                .padding(.vertical, 6)
            SidebarRow(label: "Buy me a coffee", icon: "cup.and.saucer", selected: false) {
                NSWorkspace.shared.open(URL(string: "https://ko-fi.com/livewall")!)
            }
            SidebarRow(label: "Quit Goji", icon: "power", selected: false) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 52) // clears the transparent title bar
        .padding(.bottom, 12)
        .frame(width: 190)
        // windowBackgroundColor sits close to the detail pane in both modes.
        // underPageBackgroundColor looked right in dark but is Preview's
        // mid-gray "behind the page" color in light: way too much contrast.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detail: some View {
        Group {
            switch pane {
            case .general: GeneralPane()
            case .microphone: MicrophonePane()
            case .transcription: TranscriptionPane()
            case .models: ModelsPane()
            case .history: HistoryPane()
            case .about: AboutPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One sidebar entry with explicit hover and selection states.
struct SidebarRow: View {
    let label: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(label)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.22)
                    : hovering ? Color.primary.opacity(0.07)
                    : Color.clear)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
