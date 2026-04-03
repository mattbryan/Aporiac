import Foundation

/// Manages all Anthropic AI calls for Sift.
/// Uses Claude Haiku to minimise cost.
final class AIService: Sendable {
    static let shared = AIService()
    private init() {}

    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Daily Prompt

    /// Generates a single introspective question for today's mind dump placeholder.
    /// References active themes when provided.
    func dailyPrompt(themes: [String] = []) async -> String {
        let themeContext = themes.isEmpty
            ? ""
            : " The user has these active themes on their mind: \(themes.joined(separator: ", "))."

        let systemPrompt = """
        You generate a single introspective journal prompt rooted in Stoic philosophy. \
        Draw from the core Stoic tradition — Marcus Aurelius, Epictetus, Seneca — and its central ideas: \
        the dichotomy of control, memento mori, amor fati, virtue as the only good, the discipline of desire and action, \
        the view from above, and living according to nature. \
        The prompt is one short, open-ended question — personal, specific, and genuinely thought-provoking. \
        It should invite honest self-examination, not productivity or positive thinking. \
        Never moralize or lecture. Never use Stoic jargon like "dichotomy of control" or "amor fati" directly. \
        Do not assume the user has any familiarity with Stoicism or its practices. \
        Frame everything as an invitation, not an assumption. \
        Use conditional or suggestive language — "if you were to...", "what might it look like if...", "if you imagined..." — \
        rather than presuming the user already does these things. \
        The question should feel gently curious, not demanding.\(themeContext)
        Respond with only the question. No preamble, no explanation, no punctuation other than the question mark.
        """

        return await complete(system: systemPrompt, user: "Give me today's prompt.") ?? "What did you give energy to today that wasn't yours to control?"
    }

    // MARK: - Gem Thread

    /// Generates one sentence of connective tissue between the provided gem fragments.
    /// Describes the relationship between gems — never summarises or recreates the writing.
    func gemThread(gems: [String]) async -> String? {
        guard gems.count >= 2 else { return nil }

        let gemList = gems.enumerated().map { "- \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You write a single sentence that describes the connective tissue between a set of flagged fragments \
        from a person's journal entry. These fragments are things they chose to keep — the rest of the entry \
        has faded. Your sentence describes the relationship between these fragments. \
        It does not summarise them. It does not recreate the writing that led to them. \
        It should feel like a quiet observation, not a summary. One sentence. No more.
        """

        let user = "Here are the gems from today's entry:\n\(gemList)\n\nWrite the thread."

        return await complete(system: systemPrompt, user: user)
    }

    // MARK: - Core

    private func complete(system: String, user: String) async -> String? {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 150,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AnthropicConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            guard
                let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                let content = (json["content"] as? [[String: Any]])?.first,
                let text = content["text"] as? String
            else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[AI] Request failed: \(error)")
            return nil
        }
    }
}
