import Foundation

/// A verbatim text fragment flagged as an action item from a journal entry.
struct ActionItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let userID: UUID
    var entryID: UUID?
    var content: String
    var completed: Bool
    /// When the action was marked complete; used to show completed items on the correct calendar day.
    var completedAt: Date?
    /// Character offsets in combined entry text (`gratitude` + `"\n"` + mind dump), when the action was created from a highlight.
    var rangeStart: Int?
    var rangeEnd: Int?
    let createdAt: Date
    var carriedForward: Bool
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case completed
        case completedAt = "completed_at"
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
        case createdAt = "created_at"
        case carriedForward = "carried_forward"
        case expiresAt = "expires_at"
    }

    init(
        id: UUID,
        userID: UUID,
        entryID: UUID?,
        content: String,
        completed: Bool,
        completedAt: Date? = nil,
        rangeStart: Int?,
        rangeEnd: Int?,
        createdAt: Date,
        carriedForward: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.entryID = entryID
        self.content = content
        self.completed = completed
        self.completedAt = completedAt
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.createdAt = createdAt
        self.carriedForward = carriedForward
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        entryID = try container.decodeIfPresent(UUID.self, forKey: .entryID)
        content = try container.decode(String.self, forKey: .content)
        completed = try container.decode(Bool.self, forKey: .completed)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        rangeStart = try container.decodeIfPresent(Int.self, forKey: .rangeStart)
        rangeEnd = try container.decodeIfPresent(Int.self, forKey: .rangeEnd)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        carriedForward = try container.decodeIfPresent(Bool.self, forKey: .carriedForward) ?? false
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encodeIfPresent(entryID, forKey: .entryID)
        try container.encode(content, forKey: .content)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(rangeStart, forKey: .rangeStart)
        try container.encodeIfPresent(rangeEnd, forKey: .rangeEnd)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(carriedForward, forKey: .carriedForward)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

extension ActionItem {
    static let mock: [ActionItem] = [
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Follow up with the insurance company", completed: false, rangeStart: nil, rangeEnd: nil, createdAt: Date(), carriedForward: false, expiresAt: nil),
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Book the dentist", completed: false, rangeStart: nil, rangeEnd: nil, createdAt: Date(), carriedForward: false, expiresAt: nil),
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Reply to Marcus", completed: false, rangeStart: nil, rangeEnd: nil, createdAt: Date(), carriedForward: false, expiresAt: nil),
        ActionItem(id: UUID(), userID: UUID(), entryID: UUID(), content: "Review the lease renewal", completed: true, completedAt: Date(), rangeStart: nil, rangeEnd: nil, createdAt: Date(), carriedForward: false, expiresAt: nil),
    ]
}
