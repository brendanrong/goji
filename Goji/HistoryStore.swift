import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
}

/// Card-length digit runs (13 to 19 digits, spaces or dashes allowed between
/// groups) never reach History on disk: "4123 4567 8901 2345" is stored as
/// "•••• 2345". Paste Last still has the full text for this session.
enum CardMask {
    private static let run = try! NSRegularExpression(pattern: #"(?<!\d)\d(?:[ -]?\d){12,18}(?!\d)"#)

    static func mask(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for m in run.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let digits = ns.substring(with: m.range).filter(\.isNumber)
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)) + "•••• " + digits.suffix(4)
            cursor = m.range.location + m.range.length
        }
        return out + ns.substring(from: cursor)
    }
}

/// Recent transcripts, newest first. Stored locally in UserDefaults, capped.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private static let storageKey = "history"
    private static let cap = 500

    @Published private(set) var items: [HistoryItem]

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    var last: HistoryItem? { items.first }

    func add(_ text: String) {
        items.insert(HistoryItem(text: CardMask.mask(text)), at: 0)
        if items.count > Self.cap {
            items.removeLast(items.count - Self.cap)
        }
        persist()
    }

    /// Replace the text of one entry (the correction flow).
    func update(_ id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
