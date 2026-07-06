import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
}

/// Recent transcripts, newest first. Stored locally in UserDefaults, capped.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private static let storageKey = "history"
    private static let cap = 50

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
        items.insert(HistoryItem(text: text), at: 0)
        if items.count > Self.cap {
            items.removeLast(items.count - Self.cap)
        }
        persist()
    }

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
