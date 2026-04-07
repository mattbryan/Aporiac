import Foundation

/// Schools of thought that can shape the daily entry prompt.
enum Philosophy: String, CaseIterable, Identifiable {
    case stoicism
    case existentialism
    case epicureanism
    case buddhism
    case taoism

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stoicism: return "Stoicism"
        case .existentialism: return "Existentialism"
        case .epicureanism: return "Epicureanism"
        case .buddhism: return "Buddhism"
        case .taoism: return "Taoism"
        }
    }

    var description: String {
        switch self {
        case .stoicism:
            return "Control what you can. Let go of what you can't. Virtue is the only real good."
        case .existentialism:
            return "You are entirely free, and that freedom is the weight. Nothing has meaning until you give it one."
        case .epicureanism:
            return "Pleasure matters — but most of what you chase isn't pleasure. Examine what you actually need versus what you've been told to want."
        case .buddhism:
            return "Everything changes. Most suffering comes from pretending it doesn't. What are you clinging to that has already moved?"
        case .taoism:
            return "There's a current to things. You can work with it or against it. Most struggle is the second one."
        }
    }

    /// Guidance passed to the AI system prompt for this philosophy.
    var promptGuidance: String {
        switch self {
        case .stoicism:
            return "Draw from Stoic philosophy — Marcus Aurelius, Epictetus, Seneca. Core ideas: the dichotomy of control, memento mori, amor fati, virtue as the only good, the discipline of desire and action, the view from above, living according to nature."
        case .existentialism:
            return "Draw from Existentialist philosophy — Sartre, Camus, de Beauvoir. Core ideas: radical freedom and responsibility, authenticity, bad faith, the absurd, meaning as something made rather than found, the weight of choice."
        case .epicureanism:
            return "Draw from Epicurean philosophy — Epicurus, Lucretius. Core ideas: distinguishing necessary from unnecessary desires, the pursuit of ataraxia (tranquility) over excitement, friendship and simple pleasures as the highest goods, freedom from fear of death and the gods."
        case .buddhism:
            return "Draw from Buddhist philosophy — the Pali Canon, Zen, Mahayana traditions. Core ideas: impermanence (anicca), suffering arising from attachment (dukkha), non-self (anatta), the middle way, present-moment awareness, the nature of craving."
        case .taoism:
            return "Draw from Taoist philosophy — Laozi, Zhuangzi. Core ideas: wu wei (effortless action), alignment with the natural flow of things, the paradox of striving, yielding as strength, the limits of language and concept, harmony over force."
        }
    }
}

extension Philosophy {
    /// Returns a stable philosophy for today, drawn from the provided set.
    /// The selection is seeded by the calendar day so it doesn't change within a day.
    static func todaysPhilosophy(from selected: Set<Philosophy>) -> Philosophy {
        guard !selected.isEmpty else { return .stoicism }
        let ordered = selected.sorted { $0.rawValue < $1.rawValue }
        let dayOfEra = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return ordered[dayOfEra % ordered.count]
    }
}
