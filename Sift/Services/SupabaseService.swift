import Foundation
import Supabase

/// Shared Supabase client. Configured for the `sift` schema.
@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private(set) var currentUser: User?

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                db: .init(schema: "sift"),
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    var isAuthenticated: Bool { currentUser != nil }

    /// Restores an existing session or signs in anonymously on first launch.
    func initialize() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            print("[Auth] Restored session for \(session.user.id)")
        } catch {
            print("[Auth] No existing session — signing in anonymously")
            await signInAnonymously()
        }
    }

    private func signInAnonymously() async {
        do {
            let session = try await client.auth.signInAnonymously()
            currentUser = session.user
            print("[Auth] Anonymous sign-in succeeded: \(session.user.id)")
        } catch {
            print("[Auth] Anonymous sign-in failed: \(error)")
        }
    }

    /// Today's entry row if one exists, without creating a new row.
    func fetchTodayEntry() async throws -> Entry? {
        guard let userID = currentUser?.id else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        let formatter = ISO8601DateFormatter()
        let entries: [Entry] = try await client
            .from("entries")
            .select()
            .eq("user_id", value: userID.uuidString)
            .gte("created_at", value: formatter.string(from: today))
            .lt("created_at", value: formatter.string(from: tomorrow))
            .limit(1)
            .execute()
            .value

        return entries.first
    }

    /// Loads the signed-in user’s `public.user_settings` row, creating one if missing.
    func fetchOrCreateUserSettings() async throws -> UserSettings {
        guard let user = currentUser else {
            throw SupabaseUserSettingsError.notAuthenticated
        }
        let rows: [UserSettings] = try await client.schema("public").from("user_settings")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .limit(1)
            .execute()
            .value
        if let existing = rows.first {
            return existing
        }
        let toInsert = UserSettings(userID: user.id, lastThemeReview: nil, lastHabitReview: nil)
        do {
            return try await client.schema("public").from("user_settings")
                .insert(toInsert)
                .select()
                .single()
                .execute()
                .value
        } catch {
            let retry: [UserSettings] = try await client.schema("public").from("user_settings")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .limit(1)
                .execute()
                .value
            if let created = retry.first {
                return created
            }
            throw error
        }
    }

    /// Sets `last_theme_review` to now for the current user.
    func updateLastThemeReview() async throws {
        guard let user = currentUser else {
            throw SupabaseUserSettingsError.notAuthenticated
        }
        try await client.schema("public").from("user_settings")
            .update(ThemeReviewUpdate(lastThemeReview: Date.now))
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }

    /// Sets `last_habit_review` to now for the current user.
    func updateLastHabitReview() async throws {
        guard let user = currentUser else {
            throw SupabaseUserSettingsError.notAuthenticated
        }
        try await client.schema("public").from("user_settings")
            .update(HabitReviewUpdate(lastHabitReview: Date.now))
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }
}

private struct ThemeReviewUpdate: Encodable, Sendable {
    let lastThemeReview: Date

    enum CodingKeys: String, CodingKey {
        case lastThemeReview = "last_theme_review"
    }
}

private struct HabitReviewUpdate: Encodable, Sendable {
    let lastHabitReview: Date

    enum CodingKeys: String, CodingKey {
        case lastHabitReview = "last_habit_review"
    }
}

private enum SupabaseUserSettingsError: Error {
    case notAuthenticated
}
