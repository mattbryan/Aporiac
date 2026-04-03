import Foundation
import Observation

/// Pairs a gem with its associated themes for list and filter UI.
struct GemWithThemes: Identifiable, Sendable {
    var gem: Gem
    var themes: [Theme]
    var id: UUID { gem.id }
}

private struct GemThemeRow: Codable, Sendable {
    let gemID: UUID
    let themeID: UUID

    enum CodingKeys: String, CodingKey {
        case gemID = "gem_id"
        case themeID = "theme_id"
    }
}

private struct GemThemeInsert: Encodable, Sendable {
    let gemID: UUID
    let themeID: UUID

    enum CodingKeys: String, CodingKey {
        case gemID = "gem_id"
        case themeID = "theme_id"
    }
}

/// Manages the state and actions for the gems collection.
@MainActor
@Observable
final class GemViewModel {
    private(set) var gemsWithThemes: [GemWithThemes] = []
    private(set) var allThemes: [Theme] = []
    var searchText: String = ""
    var selectedThemeID: UUID? = nil

    private var service: SupabaseService { .shared }

    var filteredGems: [GemWithThemes] {
        var result = gemsWithThemes

        if let themeID = selectedThemeID {
            result = result.filter { $0.themes.contains { $0.id == themeID } }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.gem.content.lowercased().contains(query) }
        }

        return result
    }

    /// Fetches the user’s gems, `gem_themes` rows, and active themes; joins them in memory.
    func load() async throws {
        guard let userID = service.currentUser?.id else {
            throw GemViewModelError.notAuthenticated
        }

        let gems: [Gem] = try await service.client
            .from("gems")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        let gemIDs = gems.map(\.id)

        let gemThemeRows: [GemThemeRow]
        if gemIDs.isEmpty {
            gemThemeRows = []
        } else {
            gemThemeRows = try await service.client
                .from("gem_themes")
                .select()
                .in("gem_id", values: gemIDs)
                .execute()
                .value
        }

        let themes: [Theme] = try await service.client
            .from("themes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .order("created_at")
            .execute()
            .value

        let themeByID = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })

        var themesByGemID: [UUID: [Theme]] = [:]
        for row in gemThemeRows {
            guard let theme = themeByID[row.themeID] else { continue }
            themesByGemID[row.gemID, default: []].append(theme)
        }

        gemsWithThemes = gems.map { gem in
            GemWithThemes(gem: gem, themes: themesByGemID[gem.id] ?? [])
        }
        allThemes = themes
    }

    /// Inserts a `gem_themes` association and updates local state when this gem is already in memory; otherwise inserts only (e.g. gem just flagged from an entry).
    func addTheme(themeID: UUID, toGemID gemID: UUID) async throws {
        guard let theme = allThemes.first(where: { $0.id == themeID }) else {
            throw GemViewModelError.themeNotFound
        }

        if let index = gemsWithThemes.firstIndex(where: { $0.gem.id == gemID }) {
            if gemsWithThemes[index].themes.contains(where: { $0.id == themeID }) {
                return
            }

            let snapshot = gemsWithThemes
            var nextThemes = gemsWithThemes[index].themes
            nextThemes.append(theme)
            gemsWithThemes[index].themes = nextThemes

            do {
                try await service.client
                    .from("gem_themes")
                    .insert(GemThemeInsert(gemID: gemID, themeID: themeID))
                    .execute()
            } catch {
                gemsWithThemes = snapshot
                throw error
            }
        } else {
            try await service.client
                .from("gem_themes")
                .insert(GemThemeInsert(gemID: gemID, themeID: themeID))
                .execute()
        }
    }
}

private enum GemViewModelError: Error {
    case notAuthenticated
    case themeNotFound
}
