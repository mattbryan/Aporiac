import Foundation

/// A daily log entry for a habit, recording partial or full credit.
struct HabitLog: Identifiable, Codable, Sendable {
    let id: UUID
    let habitID: UUID
    var date: Date
    /// Credit awarded: 0, 0.5, or 1.
    var credit: Float

    enum CodingKeys: String, CodingKey {
        case id
        case habitID = "habit_id"
        case date
        case credit
    }
}
