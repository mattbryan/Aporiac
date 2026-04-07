import Foundation

/// A flagged fragment of an entry that persists permanently.
/// The gem data shape is shared across the Aporian suite — do not change without suite-wide consideration.
struct Gem: Identifiable, Codable, Sendable {
    let id: UUID
    let userID: UUID
    let entryID: UUID
    /// The flagged fragment, verbatim in the user's own words.
    var content: String
    /// Character offset in combined entry text (gratitude + "\n" + content).
    var rangeStart: Int
    /// Character offset in combined entry text (exclusive end).
    var rangeEnd: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
        case createdAt = "created_at"
    }
}
