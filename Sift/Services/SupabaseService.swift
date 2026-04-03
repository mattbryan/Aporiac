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
}
