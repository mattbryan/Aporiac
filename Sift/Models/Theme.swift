import Foundation

/// A thinking theme that informs AI daily prompts.
struct Theme: Identifiable, Codable, Sendable {
    let id: UUID
    let userID: UUID
    var title: String
    var description: String?
    var active: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case description
        case active
        case createdAt = "created_at"
    }
}
