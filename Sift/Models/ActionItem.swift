import Foundation

/// A verbatim text fragment flagged as an action item from a journal entry.
struct ActionItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    var entryID: UUID?
    var content: String
    var completed: Bool
    /// Character offsets in combined entry text (`gratitude` + `"\n"` + mind dump), when the action was created from a highlight.
    var rangeStart: Int?
    var rangeEnd: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case completed
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
        case createdAt = "created_at"
    }
}

extension ActionItem {
    static let mock: [ActionItem] = [
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Follow up with the insurance company", completed: false, rangeStart: nil, rangeEnd: nil, createdAt: Date()),
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Book the dentist", completed: false, rangeStart: nil, rangeEnd: nil, createdAt: Date()),
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Reply to Marcus", completed: false, rangeStart: nil, rangeEnd: nil, createdAt: Date()),
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Review the lease renewal", completed: true, rangeStart: nil, rangeEnd: nil, createdAt: Date()),
    ]
}
