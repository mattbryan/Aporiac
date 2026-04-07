import Foundation

/// Review timestamps and related fields from `public.user_settings`.
struct UserSettings: Identifiable, Codable, Sendable {
    let userID: UUID
    var lastThemeReview: Date?
    var lastHabitReview: Date?

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lastThemeReview = "last_theme_review"
        case lastHabitReview = "last_habit_review"
    }
}
