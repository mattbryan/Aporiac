import Foundation

/// A journal entry that expires after seven days unless it contains a gem.
struct Entry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    var gratitudeContent: String
    var content: String
    var contentBlocks: [PersistedEntryBlock]?
    let createdAt: Date
    let expiresAt: Date
    var hasGem: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case gratitudeContent = "gratitude_content"
        case content
        case contentBlocks = "content_blocks"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case hasGem = "has_gem"
    }
}
