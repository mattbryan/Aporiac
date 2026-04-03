import Foundation

/// A daily log entry for a habit, recording partial or full credit.
struct HabitLog: Identifiable, Codable, Sendable {
    let id: UUID
    let habitID: UUID
    /// Postgres `date` column value as `yyyy-MM-dd`.
    var date: String
    /// Credit awarded: 0, 0.5, or 1.
    var credit: Float

    enum CodingKeys: String, CodingKey {
        case id
        case habitID = "habit_id"
        case date
        case credit
    }

    /// The calendar day this log represents.
    var calendarDate: Date? {
        HabitLog.dateFormatter.date(from: date)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Returns a `yyyy-MM-dd` string for today, for use when inserting a log.
    static func todayString() -> String {
        dateFormatter.string(from: Date())
    }
}
