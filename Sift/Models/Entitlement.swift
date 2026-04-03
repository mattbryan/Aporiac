import Foundation

/// The subscription entitlement status for a user.
struct Entitlement: Codable, Sendable {
    let userID: UUID
    /// Payment source: `apple` or `stripe`.
    var source: String
    /// Subscription status: `trial`, `active`, or `expired`.
    var status: String
    /// Plan tier: `monthly` or `annual`.
    var plan: String
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case source
        case status
        case plan
        case expiresAt = "expires_at"
    }
}
