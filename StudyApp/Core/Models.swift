import Foundation

struct Folder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
}
struct Deck: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var folder_id: UUID
    var title: String
}
struct Card: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var deck_id: UUID
    var question: String
    var answer: String
    var status: String
    var streak: Int
    var due_at: Date
    var position: Int
}
/// Manual status changes set an absolute state, so retrying does not grow a streak.
enum CardProgressChange: String, Sendable {
    case secure, uncertain, reset
    var status: String { self == .reset ? "new" : rawValue }
    func apply(to card: Card, now: Date) -> Card {
        var updated = card
        updated.status = status
        updated.streak = self == .secure ? 1 : 0
        let delay: TimeInterval = self == .secure ? 86400 : self == .uncertain ? 600 : 0
        updated.due_at = now.addingTimeInterval(delay)
        return updated
    }
}

struct AuthUser: Codable, Sendable { let id: UUID; let email: String? }
struct AuthSession: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_at: Double
    let user: AuthUser
}
struct ImportDocument: Codable, Sendable {
    let version: Int
    let folder: String
    let decks: [ImportDeck]
    var cardCount: Int { decks.reduce(0) { $0 + $1.cards.count } }

    static func parse(_ data: Data) throws -> ImportDocument {
        guard data.count <= 5_000_000 else { throw AppError.message("Die Datei darf höchstens 5 MB groß sein.") }
        let document: ImportDocument
        do { document = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw AppError.message("Die JSON-Datei entspricht nicht dem Importformat. Benötigt werden version, folder und decks mit title und cards (question/answer).") }
        guard document.version == 1 else { throw AppError.message("Dieses Importformat wird noch nicht unterstützt. Verwende version: 1.") }
        guard !document.folder.trimmed.isEmpty, document.folder.count <= 120,
              !document.decks.isEmpty, document.decks.count <= 100,
              document.cardCount <= 2000 else {
            throw AppError.message("Erlaubt sind ein Ordnername (1–120 Zeichen), 1–100 Stapel und maximal 2.000 Karten.")
        }
        for deck in document.decks {
            guard !deck.title.trimmed.isEmpty, deck.title.count <= 200, !deck.cards.isEmpty else {
                throw AppError.message("Jeder Stapel braucht einen Titel (1–200 Zeichen) und mindestens eine Karte.")
            }
            for card in deck.cards {
                guard !card.question.trimmed.isEmpty, !card.answer.trimmed.isEmpty,
                      card.question.count <= 10000, card.answer.count <= 20000 else {
                    throw AppError.message("Jede Karte braucht eine Frage (max. 10.000 Zeichen) und eine Antwort (max. 20.000 Zeichen).")
                }
            }
        }
        return document
    }
}
struct ImportDeck: Codable, Sendable { let title: String; let cards: [ImportCard] }
struct ImportCard: Codable, Sendable { let question: String; let answer: String }

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

/// A finite round contains all new/uncertain cards and a small sample of secure cards.
/// Each initially uncertain card may be repeated once after at least three other cards.
struct StudyRound {
    private(set) var queue: [Card]
    private(set) var completed = 0
    private(set) var secure = 0
    private(set) var uncertain = 0
    private var repeated: Set<UUID> = []
    var current: Card? { queue.first }
    var total: Int { completed + queue.count }
    init(cards: [Card], now: Date = Date(), includeAll: Bool = false) {
        if includeAll {
            queue = cards.shuffled()
            return
        }
        let priority = cards.filter { $0.status != "secure" }.shuffled()
        let known = cards.filter { $0.status == "secure" }.sorted { $0.due_at < $1.due_at }
        let due = known.filter { $0.due_at <= now }
        let sampleCount = priority.isEmpty ? min(20, max(1, due.count)) : max(1, Int(ceil(Double(priority.count) * 0.15)))
        let selected = Array(known.prefix(sampleCount))
        var result = priority
        for (index, card) in selected.enumerated() {
            result.insert(card, at: min(result.count, (index + 1) * 5))
        }
        queue = result
    }
    mutating func advance(secure isSecure: Bool) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        completed += 1
        if isSecure { secure += 1 } else {
            uncertain += 1
            if !repeated.contains(card.id), queue.count >= 3 {
                queue.insert(card, at: min(4, queue.count))
                repeated.insert(card.id)
            }
        }
    }
}
