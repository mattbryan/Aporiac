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
    /// References active themes when provided and the chosen philosophical lens.
    func dailyPrompt(themes: [String] = [], philosophy: Philosophy = .stoicism) async -> String {
        let themeContext = themes.isEmpty
            ? ""
            : " The user has these active themes on their mind: \(themes.joined(separator: ", "))."

        let systemPrompt = """
        You generate a single introspective journal prompt. \(philosophy.promptGuidance) \
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

        return await complete(system: systemPrompt, user: "Give me today's prompt.") ?? "What did you give energy to today that wasn't yours to give?"
    }

    // MARK: - Entry card

    /// A 2–6 word label for the Today tab entry card. Uses the same Haiku model.
    func entryCardBriefSummary(gratitude: String, mindDump: String) async -> String? {
        let gratitude = gratitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let mindDump = mindDump.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gratitude.isEmpty || !mindDump.isEmpty else { return nil }

        let systemPrompt = """
        You label a private journal entry for a home screen card. \
        Output ONLY a very short phrase: 2 to 6 words. \
        Capture the emotional tone or through-line, not a literal summary. \
        No quotation marks, no leading labels like "Summary:", no emojis, no trailing punctuation.
        """

        let user = """
        Gratitude section:
        \(gratitude.isEmpty ? "(empty)" : gratitude)

        Mind dump:
        \(mindDump.isEmpty ? "(empty)" : mindDump)
        """

        guard let raw = await complete(system: systemPrompt, user: user, maxTokens: 48) else { return nil }
        return Self.clampSummaryWords(raw)
    }

    // MARK: - Core

    private static func clampSummaryWords(_ text: String) -> String {
        let parts = text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard parts.count > 6 else { return text }
        return parts.prefix(6).joined(separator: " ")
    }

    private func complete(system: String, user: String, maxTokens: Int = 150) async -> String? {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
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
