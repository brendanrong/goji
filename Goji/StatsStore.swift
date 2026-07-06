import Foundation

/// Cumulative local dictation stats for the History header. UserDefaults
/// only, like everything else: the numbers never leave this Mac.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var totalWords: Int
    @Published private(set) var totalRecordSeconds: Double
    @Published private(set) var streakDays: Int
    private var lastUseDay: String

    private enum Keys {
        static let words = "statsTotalWords"
        static let seconds = "statsRecordSeconds"
        static let streak = "statsStreakDays"
        static let lastDay = "statsLastUseDay"
    }

    private init() {
        let d = UserDefaults.standard
        totalWords = d.integer(forKey: Keys.words)
        totalRecordSeconds = d.double(forKey: Keys.seconds)
        streakDays = max(d.integer(forKey: Keys.streak), 0)
        lastUseDay = d.string(forKey: Keys.lastDay) ?? ""
    }

    func record(words: Int, seconds: Double) {
        guard words > 0 else { return }
        totalWords += words
        totalRecordSeconds += max(seconds, 0)

        let today = Self.dayStamp(Date())
        if lastUseDay != today {
            let yesterday = Self.dayStamp(Date().addingTimeInterval(-86_400))
            streakDays = (lastUseDay == yesterday) ? streakDays + 1 : 1
            lastUseDay = today
        } else if streakDays == 0 {
            streakDays = 1
        }
        persist()
    }

    /// Marketing math, honestly labeled: minutes to type these words at
    /// 40 wpm, minus the time actually spent dictating.
    var minutesSaved: Int {
        let typingMinutes = Double(totalWords) / 40.0
        let saved = typingMinutes - totalRecordSeconds / 60.0
        return max(Int(saved.rounded()), 0)
    }

    var averageWPM: Int {
        guard totalRecordSeconds > 5 else { return 0 }
        return Int((Double(totalWords) / (totalRecordSeconds / 60.0)).rounded())
    }

    /// Back to zero: words, time, streak, all of it.
    func reset() {
        totalWords = 0
        totalRecordSeconds = 0
        streakDays = 0
        lastUseDay = ""
        persist()
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(totalWords, forKey: Keys.words)
        d.set(totalRecordSeconds, forKey: Keys.seconds)
        d.set(streakDays, forKey: Keys.streak)
        d.set(lastUseDay, forKey: Keys.lastDay)
    }

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
