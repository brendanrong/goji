import AppKit
import SwiftUI

/// "Fix Last Dictation": a small window with the last transcript in an
/// editor. As you fix it, changed words become suggested replacement rules;
/// Save applies the ticked rules, updates History, and swaps the pasted text
/// for the corrected one when the target app is still in front.
/// Same NSWindow pattern as SettingsWindow (see notes there).
@MainActor
final class CorrectionWindow: NSObject, NSWindowDelegate {
    static let shared = CorrectionWindow()

    private var window: NSWindow?

    func show(controller: DictationController) {
        guard let last = HistoryStore.shared.last else { return }
        DispatchQueue.main.async { [self] in reallyShow(item: last, controller: controller) }
    }

    private func reallyShow(item: HistoryItem, controller: DictationController) {
        window?.close()
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Fix Last Dictation"
        win.titlebarAppearsTransparent = true
        win.collectionBehavior = [.moveToActiveSpace]
        win.isReleasedWhenClosed = false
        win.delegate = self

        let view = CorrectionView(item: item) { [weak self] corrected, rules in
            controller.applyCorrection(of: item, corrected: corrected, rules: rules)
            self?.window?.close()
        } onCancel: { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        win.contentView = hosting
        win.center()
        window = win

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        SettingsStore.shared.applyDockPolicy()
    }
}

struct CorrectionView: View {
    let item: HistoryItem
    let onSave: (String, [CorrectionDiff.Suggestion]) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var accepted: Set<CorrectionDiff.Suggestion> = []
    @State private var seen: Set<CorrectionDiff.Suggestion> = []

    init(item: HistoryItem,
         onSave: @escaping (String, [CorrectionDiff.Suggestion]) -> Void,
         onCancel: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: item.text)
    }

    private var suggestions: [CorrectionDiff.Suggestion] {
        CorrectionDiff.suggestions(original: item.text, corrected: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fix what Goji heard")
                .font(.title3.bold())
                .padding(.top, 28)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 90)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
                .onChange(of: text) { _, _ in
                    // New suggestions start ticked; ones the user unticked stay unticked.
                    for s in suggestions where !seen.contains(s) {
                        seen.insert(s)
                        accepted.insert(s)
                    }
                }

            if !suggestions.isEmpty {
                Text("Remember these fixes as rules")
                    .font(.headline)
                ForEach(suggestions, id: \.self) { s in
                    Toggle(isOn: Binding(
                        get: { accepted.contains(s) },
                        set: { on in if on { accepted.insert(s) } else { accepted.remove(s) } }
                    )) {
                        HStack(spacing: 6) {
                            Text(s.find).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Text(s.replace).fontWeight(.medium)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                Text("A rule swaps that exact word or phrase every time, in any dictation. Untick anything that was a one-off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Edit the text above. Changed words show up here as rules you can keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(text, suggestions.filter { accepted.contains($0) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
