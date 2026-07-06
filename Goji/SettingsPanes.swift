import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralPane: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        PaneScaffold(title: "General", subtitle: "Shortcut and app behavior") {
            SectionHeader("Dictation")
            SettingsCard {
                SettingsRow("Recording shortcut", subtitle: shortcutHint) {
                    Picker("Recording shortcut", selection: hotkeyChoice) {
                        ForEach(HotkeyKey.allCases) { key in
                            Text(key.label).tag(HotkeyChoice.preset(key))
                        }
                        Text("Custom Combo…").tag(HotkeyChoice.custom)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if settings.customHotkey != nil {
                    Divider()
                    SettingsRow("Custom combo",
                                subtitle: "Click record, hold any mix of Fn ⌃ ⌥ ⌘ ⇧ (left and right count as different keys), then release.") {
                        HotkeyRecorder()
                    }
                }
                Divider()
                SettingsRow("Mode") {
                    Picker("Mode", selection: $settings.activationMode) {
                        ForEach(ActivationMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            CaptionText(modeHint)

            SectionHeader("Microphone")
            MicrophoneSection()

            SectionHeader("Fine-tuning")
            SettingsCard {
                SettingsRow("Recording display",
                            subtitle: "Notch blends into the camera housing on MacBooks and draws its own island on external displays.") {
                    Picker("Recording display", selection: $settings.hudStyle) {
                        ForEach(HUDStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                if settings.activationMode == .hold {
                    SettingsRow("Double-tap to lock recording",
                                subtitle: "Tap twice quickly to keep recording hands-free, tap again to finish.") {
                        Toggle("Double-tap to lock recording", isOn: $settings.doubleTapLock)
                            .labelsHidden()
                    }
                    Divider()
                }
                SettingsRow("Play start/stop sounds",
                            subtitle: "Cues when recording begins and ends, in the pack of your choice.") {
                    HStack(spacing: 10) {
                        Picker("Sound pack", selection: $settings.soundPack) {
                            ForEach(SoundPack.allCases) { pack in
                                Text(pack.label).tag(pack)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!settings.playSounds)
                        Toggle("Play start/stop sounds", isOn: $settings.playSounds)
                            .labelsHidden()
                    }
                }
                Divider()
                SettingsRow("While dictating",
                            subtitle: "Quieter ducks your speakers to 20% and restores them after (falls back to Pause on outputs without volume control). Pause stops music or video and resumes it.") {
                    Picker("While dictating", selection: $settings.whileDictating) {
                        ForEach(WhileDictating.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SectionHeader("System")
            SettingsCard {
                SettingsRow("Appearance",
                            subtitle: "Follow the system, or keep Goji light or dark.") {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingsRow("Launch at login",
                            subtitle: "Open Goji automatically when you log in.") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Show in menu bar",
                            subtitle: "The berry icon in the status bar.") {
                    Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                        .labelsHidden()
                }
                Divider()
                SettingsRow("Show in Dock",
                            subtitle: "Clicking the Dock icon opens Settings.") {
                    Toggle("Show in Dock", isOn: $settings.showInDock)
                        .labelsHidden()
                }
            }
            if !settings.showInMenuBar {
                Text("Icon hidden. Launch Goji again from Spotlight or Finder to bring it back.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var hotkeyChoice: Binding<HotkeyChoice> {
        Binding(
            get: {
                settings.customHotkey != nil ? .custom : .preset(settings.hotkeyKey)
            },
            set: { choice in
                switch choice {
                case .preset(let key):
                    settings.customHotkey = nil
                    settings.hotkeyKey = key
                case .custom:
                    if settings.customHotkey == nil {
                        settings.customHotkey = CustomHotkey()
                    }
                }
            }
        )
    }

    private var shortcutHint: String? {
        (settings.effectiveHotkeyMask & NSEvent.ModifierFlags.function.rawValue) != 0
            ? "If pressing Fn also opens emoji or switches input source, set \"Press 🌐 key to\" to \"Do Nothing\" in System Settings > Keyboard."
            : nil
    }

    private var modeHint: String {
        switch settings.activationMode {
        case .hold:
            return settings.doubleTapLock
                ? "Hold \(settings.hotkeyDisplay), speak, release. Double-tap to keep recording hands-free, tap again to finish. Esc cancels."
                : "Hold \(settings.hotkeyDisplay), speak, release. Esc cancels."
        case .toggle:
            return "Tap \(settings.hotkeyDisplay) to start, tap again to finish. Esc cancels."
        }
    }
}

/// Picker selection for the shortcut row: one of the presets, or a recorded combo.
enum HotkeyChoice: Hashable {
    case preset(HotkeyKey)
    case custom
}

/// Mic picker + live level test, embedded in General.
struct MicrophoneSection: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var devices: [MicDevices.Device] = []
    @StateObject private var micPreview = MicLevelPreview()

    var body: some View {
        SettingsCard {
            SettingsRow("Input device",
                        subtitle: "Used from the next recording. Falls back to the system default if unavailable.") {
                Picker("Input device", selection: $settings.micDeviceUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                    if let saved = settings.micDeviceUID, !devices.contains(where: { $0.uid == saved }) {
                        Text("Saved device (unavailable)").tag(String?.some(saved))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingsRow(micPreview.running ? "Listening…" : "Check your input level") {
                HStack(spacing: 12) {
                    if micPreview.running {
                        WaveformBars(level: micPreview.level, color: .green, barCount: 18, maxHeight: 14)
                    }
                    Button(micPreview.running ? "Stop Test" : "Test Mic") {
                        micPreview.toggle(deviceUID: settings.micDeviceUID)
                    }
                }
            }
        }
        .onAppear { devices = MicDevices.inputDevices() }
        .onDisappear { micPreview.stop() }
        .onChange(of: settings.micDeviceUID) { _, _ in
            if micPreview.running {
                micPreview.stop()
                micPreview.toggle(deviceUID: settings.micDeviceUID)
            }
        }
    }
}

struct TranscriptionPane: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var packStatus: String?
    @State private var composerWord = ""
    @State private var suggestions: [String]?
    @State private var selectedSuggestions = Set<String>()
    @State private var suggesting = false
    @State private var composerNote: String?

    var body: some View {
        PaneScaffold(title: "Transcription", subtitle: "What happens to your words, in order") {
            SectionHeader("Names & phrases")
            SettingsCard {
                ForEach($settings.vocabulary) { $word in
                    HStack {
                        TextField("Name, team, or term", text: $word.text)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            settings.vocabulary.removeAll { $0.id == word.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                SettingsRow("Words Goji keeps mishearing",
                            subtitle: "Add each one once: people, teams, product names, jargon.") {
                    Button("Add Word") {
                        settings.vocabulary.append(VocabWord())
                    }
                }
            }
            CaptionText("AI cleanup nudges close mishearings to these exact spellings: 'air pods' becomes 'AirPods', 'sigma' becomes 'Figma'. Needs the cleanup toggle on. Works best with distinctive words; for two of your own terms that sound alike, use a Word replacement below instead.")

            SectionHeader("AI cleanup")
            SettingsCard {
                SettingsRow("Clean up transcripts with Apple Intelligence") {
                    Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
                        .labelsHidden()
                        .disabled(!Cleaner.isSupported)
                }
            }
            CaptionText(Cleaner.unavailabilityHint
                ?? "Removes filler words, applies self-corrections like 'scratch that', and turns 'new line' into a real line break. The only option on this pane that needs Apple Intelligence.")

            SectionHeader("Formatting")
            SettingsCard {
                SettingsRow("Remove the full stop at the end",
                            subtitle: "Drops the final period the model adds to every dictation. Question marks and exclamations stay.") {
                    Toggle("Remove the full stop at the end", isOn: $settings.removeTrailingFullStop)
                        .labelsHidden()
                }
            }

            SectionHeader("Word replacements")
            SettingsCard {
                HStack {
                    TextField("Word or name Goji mishears, e.g. Jira", text: $composerWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { suggestVariations() }
                    if suggestions == nil {
                        Button(suggesting ? "Thinking…" : "Suggest Variations") {
                            suggestVariations()
                        }
                        .disabled(suggesting || !Cleaner.isSupported || composerWord.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help(Cleaner.isSupported ? "Generate likely mishearings to approve as rules" : "Suggestions need Apple Intelligence")
                    } else {
                        Button("Cancel") {
                            resetComposer()
                        }
                    }
                }
                .padding(.vertical, 10)
                if let suggestions {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Likely mishearings, click to exclude:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                SelectableChip(text: suggestion, isOn: selectedSuggestions.contains(suggestion)) {
                                    if selectedSuggestions.contains(suggestion) {
                                        selectedSuggestions.remove(suggestion)
                                    } else {
                                        selectedSuggestions.insert(suggestion)
                                    }
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            Button("Add \(selectedSuggestions.count) Rules") {
                                addSelectedVariations()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedSuggestions.isEmpty)
                            Text("Also adds \"\(composerWord.trimmingCharacters(in: .whitespaces))\" to Names & phrases")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 10)
                }
                if let composerNote {
                    Text(composerNote)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.bottom, 8)
                }
                Divider()
                ForEach($settings.replacements) { $rule in
                    HStack {
                        TextField("Replace", text: $rule.find)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("With", text: $rule.replace)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            settings.replacements.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                SettingsRow("Add a rule") {
                    Button("Add Replacement") {
                        settings.replacements.append(ReplacementRule())
                    }
                }
                Divider()
                SettingsRow("Share or back up",
                            subtitle: "Your rules and Names & phrases as one JSON file. Import merges and never deletes.") {
                    HStack(spacing: 8) {
                        Button("Import…") {
                            importPack()
                        }
                        Button("Export…") {
                            exportPack()
                        }
                    }
                }
            }
            if let packStatus {
                Text(packStatus)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            CaptionText("Literal find and replace, applied last. Case-insensitive, whole words. For name fixes, prefer Names & phrases at the top.")
        }
    }

    private func suggestVariations() {
        let word = composerWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !suggesting, Cleaner.isSupported else { return }
        suggesting = true
        composerNote = nil
        Task {
            let results = await VariationSuggester.suggestions(for: word)
            let existing = Set(settings.replacements.map { $0.find.lowercased() })
            let fresh = results.filter { !existing.contains($0.lowercased()) }
            suggesting = false
            if fresh.isEmpty {
                suggestions = nil
                composerNote = "No suggestions for that one; add rules manually below."
            } else {
                suggestions = fresh
                selectedSuggestions = Set(fresh)
            }
        }
    }

    private func addSelectedVariations() {
        let word = composerWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        for suggestion in selectedSuggestions.sorted() {
            settings.replacements.append(ReplacementRule(find: suggestion, replace: word))
        }
        if !settings.vocabulary.contains(where: { $0.text.compare(word, options: .caseInsensitive) == .orderedSame }) {
            settings.vocabulary.append(VocabWord(text: word))
        }
        let count = selectedSuggestions.count
        resetComposer()
        composerNote = "Added \(count) rules for \(word)."
    }

    private func resetComposer() {
        composerWord = ""
        suggestions = nil
        selectedSuggestions = []
        composerNote = nil
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try JSONDecoder().decode(WordPack.self, from: Data(contentsOf: url))
            let result = settings.merge(pack)
            let name = pack.name ?? url.deletingPathExtension().lastPathComponent
            packStatus = "Imported \"\(name)\": added \(result.rules) rules and \(result.words) words, skipped \(result.skipped) duplicates."
        } catch {
            packStatus = "Couldn't read that file as a word pack."
        }
    }

    private func exportPack() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "goji-words.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(settings.exportPack()).write(to: url)
            packStatus = "Exported \(settings.replacements.count) rules and \(settings.vocabularyTerms.count) words."
        } catch {
            packStatus = "Export failed: \(error.localizedDescription)"
        }
    }

}

struct ModelsPane: View {
    @ObservedObject private var library = ModelLibrary.shared

    var body: some View {
        PaneScaffold(title: "Models", subtitle: "The speech model that turns your voice into text") {
            SettingsCard {
                ForEach(SpeechModel.allCases) { model in
                    if model != SpeechModel.allCases.first {
                        Divider()
                    }
                    ModelRow(model: model)
                }
            }
            if let error = library.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            CaptionText("Everything runs on this Mac. Switching models applies from your next dictation.")

            SectionHeader("Storage")
            SettingsCard {
                SettingsRow("Models on disk",
                            subtitle: "\(library.totalSizeOnDisk()) in Application Support > FluidAudio > Models.") {
                    Button("Show in Finder") {
                        library.revealInFinder()
                    }
                }
            }
        }
    }
}

/// One model in the list: name, badges, description, and the state control
/// (Download with progress, Use, Remove, or In Use).
struct ModelRow: View {
    let model: SpeechModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var library = ModelLibrary.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(.semibold)
                    if model == .standard {
                        TagBadge("Default")
                    }
                }
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(model.languagesLabel)  ·  \(model.approxDownload)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            control
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var control: some View {
        if let progress = library.downloading[model] {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: progress.fraction)
                    .frame(width: 110)
                Text("\(Int(progress.fraction * 100))%  \(progress.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if Transcriber.availableLocally(model) {
            if settings.selectedModel == model {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("In Use")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                HStack(spacing: 8) {
                    Button("Use") {
                        settings.selectedModel = model
                    }
                    if model.isInstalled {
                        Button {
                            library.remove(model)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove the downloaded files")
                    }
                }
            }
        } else {
            Button("Download") {
                library.download(model)
            }
        }
    }
}

/// Small capsule label ("Default").
struct TagBadge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
    }
}

struct HistoryPane: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var stats = StatsStore.shared
    @State private var visibleCount = 20
    @State private var expandedID: UUID?
    @State private var selection: ClosedRange<Int>?
    @State private var replaceWith = ""
    @State private var addToNames = true
    @State private var ruleNote: String?

    var body: some View {
        PaneScaffold(title: "History", subtitle: "Recent transcripts, stored only on this Mac") {
            if stats.totalWords > 0 {
                HStack(spacing: 12) {
                    statTile("Dictated words", stats.totalWords.formatted())
                    statTile("Time saved", "\(stats.minutesSaved) min")
                    statTile("Day streak", "\(stats.streakDays)")
                    statTile("Average speed", stats.averageWPM > 0 ? "\(stats.averageWPM) wpm" : "–")
                }
            }
            if history.items.isEmpty {
                SettingsCard {
                    Text("No transcripts yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            } else {
                SettingsCard {
                    ForEach(history.items.prefix(visibleCount)) { item in
                        row(for: item)
                        if expandedID == item.id {
                            ruleEditor(for: item)
                        }
                        Divider()
                    }
                    if history.items.count > visibleCount {
                        SettingsRow("Showing \(visibleCount) of \(history.items.count)") {
                            Button("Show More") {
                                visibleCount += 20
                            }
                        }
                        Divider()
                    }
                    SettingsRow("Save every transcript to a file") {
                        Button("Export…") {
                            exportHistory()
                        }
                    }
                    Divider()
                    SettingsRow("Remove all transcripts") {
                        Button("Clear History", role: .destructive) {
                            history.clear()
                        }
                    }
                    if stats.totalWords > 0 {
                        Divider()
                        SettingsRow("Start the counters from zero") {
                            Button("Reset Stats", role: .destructive) {
                                stats.reset()
                            }
                        }
                    }
                }
                if let ruleNote {
                    Text(ruleNote)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                CaptionText("Spot a wrong word? Hit the + on its transcript, click the word, type the fix. It becomes an ordinary Word replacement you can see and delete in Transcription.")
            }
        }
    }

    private func row(for item: HistoryItem) -> some View {
        HStack(alignment: .top) {
            Text(item.text)
                .lineLimit(2)
            Spacer()
            Button {
                if expandedID == item.id {
                    collapse()
                } else {
                    expandedID = item.id
                    selection = nil
                    replaceWith = ""
                    addToNames = true
                    ruleNote = nil
                }
            } label: {
                Image(systemName: expandedID == item.id ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Make a replacement rule from this transcript")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(.vertical, 8)
    }

    private func ruleEditor(for item: HistoryItem) -> some View {
        let words = item.text.split(whereSeparator: \.isWhitespace).map(String.init)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Click the words that came out wrong:")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(words.indices, id: \.self) { index in
                    SelectableChip(text: words[index], isOn: isSelected(index)) {
                        tapWord(index)
                    }
                }
            }
            HStack(spacing: 10) {
                Text("Replace \"\(selectedText(in: words))\" with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(selection == nil ? 0.4 : 1)
                TextField("Correct word", text: $replaceWith)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Toggle("add to Names & phrases", isOn: $addToNames)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Button("Add Rule") {
                    addRule(words: words)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil || replaceWith.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") {
                    collapse()
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func isSelected(_ index: Int) -> Bool {
        selection?.contains(index) ?? false
    }

    /// Tap selects a word; tapping a neighbor extends the run; anything else
    /// restarts the selection.
    private func tapWord(_ index: Int) {
        if let current = selection {
            if index == current.upperBound + 1 {
                selection = current.lowerBound...index
            } else if index == current.lowerBound - 1 {
                selection = index...current.upperBound
            } else if current.contains(index), current.count == 1 {
                selection = nil
            } else {
                selection = index...index
            }
        } else {
            selection = index...index
        }
    }

    private func selectedText(in words: [String]) -> String {
        guard let selection else { return "…" }
        return words[selection]
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func addRule(words: [String]) {
        let find = selectedText(in: words)
        let replace = replaceWith.trimmingCharacters(in: .whitespaces)
        guard !find.isEmpty, find != "…", !replace.isEmpty else { return }
        settings.replacements.append(ReplacementRule(find: find, replace: replace))
        if addToNames, !settings.vocabulary.contains(where: { $0.text.compare(replace, options: .caseInsensitive) == .orderedSame }) {
            settings.vocabulary.append(VocabWord(text: replace))
        }
        collapse()
        ruleNote = "Rule added: \(find) → \(replace)"
    }

    private func collapse() {
        expandedID = nil
        selection = nil
        replaceWith = ""
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "goji-history.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lines = history.items.map { "[\(formatter.string(from: $0.date))]  \($0.text)" }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            ruleNote = "Exported \(history.items.count) transcripts."
        } catch {
            ruleNote = "Export failed: \(error.localizedDescription)"
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary))
    }
}

struct AboutPane: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        PaneScaffold(title: "About", subtitle: "Version info and support") {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goji")
                        .font(.title2.bold())
                    Text(version)
                        .foregroundStyle(.secondary)
                    Text("Local, private dictation for macOS")
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                // Re-check whenever About opens, not just at launch.
                Task { await updates.check() }
            }

            Text("Hold a key, talk, release, and your words paste where your cursor is. Speech is transcribed entirely on this Mac.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Signed and notarized by Apple")
                }
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("No cloud, no account, no telemetry. Free forever.")
                }
            }
            .font(.callout)

            Text("Built by Brendan Rong.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                updatesControl
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/brendanrong/goji/issues")!)
                } label: {
                    Label("Report a Problem", systemImage: "envelope")
                }
            }
            Text(updateStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    private var version: String {
        "Version " + UpdateChecker.currentVersion
    }

    @ViewBuilder
    private var updatesControl: some View {
        switch updates.installPhase {
        case .downloading(let fraction):
            ProgressView(value: fraction)
                .frame(width: 110)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Button("Download in Browser") {
                updates.openDownload()
            }
        case .idle:
            if let available = updates.availableVersion {
                Button {
                    updates.installUpdate()
                } label: {
                    Label("Install Goji \(available)", systemImage: "arrow.down.circle")
                }
            } else {
                Button {
                    Task { await updates.check() }
                } label: {
                    Label(updates.checking ? "Checking…" : "Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(updates.checking)
            }
        }
    }

    private var updateStatus: String {
        switch updates.installPhase {
        case .downloading:
            return "Downloading Goji \(updates.availableVersion ?? "")…"
        case .installing:
            return "Installing… Goji will relaunch itself in a moment."
        case .failed(let message):
            return "Couldn't install automatically (\(message)) Grab it in the browser instead."
        case .idle:
            break
        }
        if let available = updates.availableVersion {
            let how = updates.canSelfInstall ? "One click installs and relaunches." : "Opens the download in your browser."
            return "Goji \(available) is ready. You're on \(UpdateChecker.currentVersion). \(how)"
        }
        if updates.lastCheckFailed {
            return "Couldn't reach GitHub to check. Try again in a moment."
        }
        return "You're on the latest version (\(UpdateChecker.currentVersion))."
    }
}

/// Tiny standalone mic monitor for the "Test Mic" row.
@MainActor
final class MicLevelPreview: ObservableObject {
    @Published var level: Float = 0
    @Published var running = false

    private let recorder = AudioRecorder()

    func toggle(deviceUID: String?) {
        if running {
            stop()
        } else {
            start(deviceUID: deviceUID)
        }
    }

    private func start(deviceUID: String?) {
        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            self.level = self.level * 0.5 + level * 0.5
        }
        do {
            try recorder.start(deviceUID: deviceUID)
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        _ = recorder.stop()
        running = false
        level = 0
    }
}
