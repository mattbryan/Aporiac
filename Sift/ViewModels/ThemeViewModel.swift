import Foundation
import Observation

/// Manages active and archived thinking themes for the current user.
@MainActor
@Observable
final class ThemeViewModel {
    private(set) var activeThemes: [Theme] = []
    private(set) var archivedThemes: [Theme] = []
    /// `true` until the in-flight `load()` finishes.
    private(set) var isLoading = true

    private var service: SupabaseService { .shared }

    /// Loads active themes (newest last by `created_at`) and archived themes (newest archive first).
    func load() async throws {
        isLoading = true
        defer { isLoading = false }

        guard let userID = service.currentUser?.id else {
            throw ThemeViewModelError.notAuthenticated
        }

        let active: [Theme] = try await service.client
            .from("themes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .order("created_at")
            .execute()
            .value

        let archived: [Theme] = try await service.client
            .from("themes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: false)
            .order("archived_at", ascending: false)
            .execute()
            .value

        activeThemes = active
        archivedThemes = archived
    }

    /// Inserts a new active theme and appends it to `activeThemes`, reverting on failure.
    func create(title: String, description: String?) async throws {
        guard let user = service.currentUser else {
            throw ThemeViewModelError.notAuthenticated
        }

        let theme = Theme(
            id: UUID(),
            userID: user.id,
            title: title,
            description: description,
            active: true,
            archivedAt: nil,
            createdAt: Date()
        )

        let insert = ThemeInsert(
            id: theme.id,
            userID: theme.userID,
            title: theme.title,
            description: theme.description,
            active: theme.active,
            archivedAt: theme.archivedAt,
            createdAt: theme.createdAt
        )

        let snapshot = activeThemes
        activeThemes.append(theme)

        do {
            try await service.client
                .from("themes")
                .insert(insert)
                .execute()
        } catch {
            activeThemes = snapshot
            throw error
        }
    }

    /// Updates title and description in Supabase and in `activeThemes`, reverting on failure.
    func update(theme: Theme, title: String, description: String?) async throws {
        guard let userID = service.currentUser?.id else {
            throw ThemeViewModelError.notAuthenticated
        }
        guard let index = activeThemes.firstIndex(where: { $0.id == theme.id }) else {
            throw ThemeViewModelError.themeNotInActiveList
        }

        let snapshot = activeThemes
        var updated = activeThemes[index]
        updated.title = title
        updated.description = description
        activeThemes[index] = updated

        do {
            try await service.client
                .from("themes")
                .update(ThemeContentUpdate(title: title, description: description))
                .eq("id", value: theme.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            activeThemes = snapshot
            throw error
        }
    }

    /// Marks the theme archived remotely and moves it from `activeThemes` to `archivedThemes`, reverting on failure.
    func archive(_ theme: Theme) async throws {
        guard let userID = service.currentUser?.id else {
            throw ThemeViewModelError.notAuthenticated
        }
        guard let index = activeThemes.firstIndex(where: { $0.id == theme.id }) else {
            throw ThemeViewModelError.themeNotInActiveList
        }

        let archivedAt = Date.now
        var archivedTheme = activeThemes[index]
        archivedTheme.active = false
        archivedTheme.archivedAt = archivedAt

        let activeSnapshot = activeThemes
        let archivedSnapshot = archivedThemes

        activeThemes.remove(at: index)
        archivedThemes.insert(archivedTheme, at: 0)

        do {
            try await service.client
                .from("themes")
                .update(ArchiveUpdate(active: false, archivedAt: archivedAt))
                .eq("id", value: theme.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            activeThemes = activeSnapshot
            archivedThemes = archivedSnapshot
            throw error
        }
    }

    /// Marks the theme active remotely and moves it from `archivedThemes` back to `activeThemes`, reverting on failure.
    func unarchive(_ theme: Theme) async throws {
        guard let userID = service.currentUser?.id else {
            throw ThemeViewModelError.notAuthenticated
        }
        guard let index = archivedThemes.firstIndex(where: { $0.id == theme.id }) else {
            throw ThemeViewModelError.themeNotInArchivedList
        }

        var activeTheme = archivedThemes[index]
        activeTheme.active = true
        activeTheme.archivedAt = nil

        let activeSnapshot = activeThemes
        let archivedSnapshot = archivedThemes

        archivedThemes.remove(at: index)
        activeThemes.insert(activeTheme, at: 0)

        do {
            try await service.client
                .from("themes")
                .update(ArchiveUpdate(active: true, archivedAt: nil))
                .eq("id", value: theme.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            activeThemes = activeSnapshot
            archivedThemes = archivedSnapshot
            throw error
        }
    }
}

private struct ThemeInsert: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let title: String
    let description: String?
    let active: Bool
    let archivedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case description
        case active
        case archivedAt = "archived_at"
        case createdAt = "created_at"
    }
}

private struct ThemeContentUpdate: Encodable, Sendable {
    let title: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
    }
}

private struct ArchiveUpdate: Encodable, Sendable {
    let active: Bool
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case active
        case archivedAt = "archived_at"
    }
}

private enum ThemeViewModelError: Error {
    case notAuthenticated
    case themeNotInActiveList
    case themeNotInArchivedList
}
