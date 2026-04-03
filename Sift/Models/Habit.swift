import Foundation

/// A recurring habit tracked against journaling sessions.
struct Habit: Identifiable, Codable, Sendable {
    let id: UUID
    let userID: UUID
    var title: String
    var fullCriteria: String
    var partialCriteria: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case fullCriteria = "full_criteria"
        case partialCriteria = "partial_criteria"
        case createdAt = "created_at"
    }
}
