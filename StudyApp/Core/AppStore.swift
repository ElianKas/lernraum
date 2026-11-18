import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    let api: SupabaseAPI?
    @Published var user: AuthUser?
    @Published var folders: [Folder] = []
    @Published var decks: [Deck] = []
    @Published var cards: [Card] = []
    @Published var error: String?
    @Published var loading = false
    @Published var ready = false
    @Published var demo = false
    var email: String { user?.email ?? "Demo" }
    init() { api = BackendConfig.current.map { SupabaseAPI(config: $0) } }

    func restore() async {
        defer { ready = true }
        guard let api else { return }
        user = await api.storedUser()
        if user != nil { await reload() }
    }
    func login(email: String, password: String, register: Bool) async throws -> Bool {
        guard let api else { throw AppError.message("Bitte hinterlege zuerst deine Supabase-Konfiguration in Config.xcconfig.") }
        user = try await api.authenticate(email: email.trimmed, password: password, register: register)
        if user != nil { await reload() }
        return user != nil
    }
    func logout() async {
        if !demo { await api?.signOut() }
        demo = false; user = nil; folders = []; decks = []; cards = []; error = nil
    }
    func reload() async {
        guard !demo, let api, user != nil else { return }
        loading = true
        defer { loading = false }
        do {
            // Paginate: PostgREST's default 1,000-row limit must not silently hide cards.
            let folders: [Folder] = try await fetchAll("folders", order: "name.asc,id.asc", api: api)
            let decks: [Deck] = try await fetchAll("decks", order: "title.asc,id.asc", api: api)
            let cards: [Card] = try await fetchAll("cards", order: "position.asc,id.asc", api: api)
            self.folders = folders; self.decks = decks; self.cards = cards
        } catch { self.error = error.localizedDescription }
    }
    private func fetchAll<T: Decodable & Sendable>(_ table: String, order: String, api: SupabaseAPI) async throws -> [T] {
        var result: [T] = []
        var offset = 0
        while true {
            let page: [T] = try await api.request("\(table)?select=*&order=\(order)&limit=500&offset=\(offset)")
            result += page
            if page.count < 500 { return result }
            offset += page.count
        }
    }
    func cards(in deck: Deck) -> [Card] { cards.filter { $0.deck_id == deck.id } }
    func cards(in folder: Folder) -> [Card] {
        let deckIDs = Set(decks(in: folder).map(\.id))
        return cards.filter { deckIDs.contains($0.deck_id) }
    }
    func decks(in folder: Folder) -> [Deck] { decks.filter { $0.folder_id == folder.id } }
    func createFolder(_ name: String, id: UUID? = nil) async throws {
        let folder = Folder(id: id ?? UUID(), name: name.trimmed)
        if demo {
            if let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i] = folder } else { folders.append(folder) }
            return
        }
        try await write("folders", id: id, payload: ["id": folder.id.uuidString, "name": folder.name])
        await reload()
    }
    func createDeck(_ title: String, folderID: UUID, id: UUID? = nil) async throws {
        let deck = Deck(id: id ?? UUID(), folder_id: folderID, title: title.trimmed)
        if demo {
            if let i = decks.firstIndex(where: { $0.id == deck.id }) { decks[i] = deck } else { decks.append(deck) }
            return
        }
        try await write("decks", id: id, payload: ["id": deck.id.uuidString, "folder_id": folderID.uuidString, "title": deck.title])
        await reload()
    }
    func saveCard(question: String, answer: String, deckID: UUID, card: Card?) async throws {
        let id = card?.id ?? UUID()
        if demo {
            if let i = cards.firstIndex(where: { $0.id == id }) { cards[i].question = question.trimmed; cards[i].answer = answer.trimmed; cards[i].deck_id = deckID }
            else { cards.append(Card(id: id, deck_id: deckID, question: question.trimmed, answer: answer.trimmed, status: "new", streak: 0, due_at: .now, position: cards.count)) }
            return
        }
        var payload: [String: Any] = ["id": id.uuidString, "deck_id": deckID.uuidString, "question": question.trimmed, "answer": answer.trimmed]
        if card == nil { payload["position"] = cards.filter { $0.deck_id == deckID }.count }
        try await write("cards", id: card?.id, payload: payload)
        await reload()
    }
    private func write(_ table: String, id: UUID?, payload: [String: Any]) async throws {
        guard let api else { throw AppError.message("Supabase ist nicht eingerichtet.") }
        try await api.mutate(table + (id.map { "?id=eq.\($0.uuidString)" } ?? ""), method: id == nil ? "POST" : "PATCH", body: JSONSerialization.data(withJSONObject: payload))
    }
    func delete(_ table: String, id: UUID) async throws {
        if !demo {
            guard let api else { throw AppError.message("Supabase ist nicht eingerichtet.") }
            try await api.mutate("\(table)?id=eq.\(id.uuidString)", method: "DELETE")
        }
        switch table {
        case "folders":
            let deckIDs = Set(decks.filter { $0.folder_id == id }.map(\.id))
            cards.removeAll { deckIDs.contains($0.deck_id) }; decks.removeAll { $0.folder_id == id }; folders.removeAll { $0.id == id }
        case "decks": cards.removeAll { $0.deck_id == id }; decks.removeAll { $0.id == id }
        default: cards.removeAll { $0.id == id }
        }
    }
    func importCards(_ document: ImportDocument, requestID: UUID) async throws {
        if demo {
            let folder = Folder(id: requestID, name: document.folder)
            guard !folders.contains(where: { $0.id == requestID }) else { return }
            folders.append(folder)
            for imported in document.decks {
                let deck = Deck(id: UUID(), folder_id: folder.id, title: imported.title)
                decks.append(deck)
                cards += imported.cards.enumerated().map { i, card in
                    Card(id: UUID(), deck_id: deck.id, question: card.question, answer: card.answer, status: "new", streak: 0, due_at: .now, position: i)
                }
            }
        } else {
            guard let api else { throw AppError.message("Supabase ist nicht eingerichtet.") }
            let payload: [String: Any] = ["document": try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)), "request_id": requestID.uuidString]
            try await api.mutate("rpc/import_cards", method: "POST", body: JSONSerialization.data(withJSONObject: payload))
            await reload()
        }
    }
    func review(_ card: Card, secure: Bool, reviewID: UUID) async throws {
        var updated: Card
        if demo {
            updated = card
            updated.status = secure ? "secure" : "uncertain"
            updated.streak = secure ? card.streak + 1 : 0
            updated.due_at = Date().addingTimeInterval(secure ? min(pow(2, Double(updated.streak - 1)), 30) * 86400 : 600)
        } else {
            guard let api else { throw AppError.message("Supabase ist nicht eingerichtet.") }
            let result: [Card] = try await api.request("rpc/review_card", method: "POST", body: JSONSerialization.data(withJSONObject: ["card_id": card.id.uuidString, "is_secure": secure, "review_id": reviewID.uuidString]))
            guard let first = result.first else { throw AppError.message("Die Karte wurde nicht gefunden.") }
            updated = first
        }
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = updated }
    }
    func setCardStatus(_ change: CardProgressChange, ids: Set<UUID>, in deck: Deck) async throws {
        guard change != .reset else { throw AppError.message("Nutze zum Zurücksetzen die Stapel-Aktion.") }
        guard !ids.isEmpty else { throw AppError.message("Wähle zuerst mindestens eine Karte aus.") }
        let existing = Set(cards(in: deck).map(\.id))
        guard ids.isSubset(of: existing) else { throw AppError.message("Die Auswahl enthält Karten, die nicht mehr in diesem Stapel liegen. Lade den Stapel neu.") }
        if !demo {
            guard let api else { throw AppError.message("Supabase ist nicht eingerichtet.") }
            let payload: [String: Any] = ["target_deck": deck.id.uuidString,
                "selected_ids": ids.map(\.uuidString), "new_status": change.status]
            let count: Int = try await api.request("rpc/set_cards_status", method: "POST", body: JSONSerialization.data(withJSONObject: payload))
            guard count == ids.count else { throw AppError.message("Die Auswahl wurde auf dem Server geändert. Bitte lade den Stapel neu.") }
        }
        let now = Date()
        cards = cards.map { $0.deck_id == deck.id && ids.contains($0.id) ? change.apply(to: $0, now: now) : $0 }
    }
    func resetProgress(in deck: Deck) async throws {
        if !demo {
            guard let api else { throw AppError.message("Supabase ist nicht eingerichtet.") }
            try await api.mutate("rpc/reset_deck_progress", method: "POST", body: JSONSerialization.data(withJSONObject: ["target_deck": deck.id.uuidString]))
        }
        let now = Date()
        cards = cards.map { $0.deck_id == deck.id ? CardProgressChange.reset.apply(to: $0, now: now) : $0 }
    }
    func startDemo() {
        demo = true
        user = AuthUser(id: UUID(), email: "demo@study.app")
        let folder = Folder(id: UUID(), name: "Lineare Algebra")
        let deck = Deck(id: UUID(), folder_id: folder.id, title: "01 · Vektorräume")
        folders = [folder]; decks = [deck]
        let examples = [
            ("Was ist ein Vektorraum?", "Eine Menge von Vektoren mit Addition und skalarer Multiplikation, die die Vektorraumaxiome erfüllt."),
            ("Wann ist eine Teilmenge ein Untervektorraum?", "Sie enthält den Nullvektor und ist unter Addition und skalarer Multiplikation abgeschlossen."),
            ("Was bedeutet lineare Unabhängigkeit?", "Nur die triviale Linearkombination (alle Koeffizienten gleich null) ergibt den Nullvektor."),
            ("Was ist eine Basis?", "Ein linear unabhängiges Erzeugendensystem eines Vektorraums."),
            ("Was gibt die Dimension an?", "Die Anzahl der Vektoren in einer Basis des Vektorraums."),
            ("Was ist der Spann einer Vektormenge?", "Die Menge aller Linearkombinationen dieser Vektoren.")]
        cards = examples.enumerated().map { i, pair in Card(id: UUID(), deck_id: deck.id, question: pair.0, answer: pair.1, status: i == 5 ? "secure" : "new", streak: i == 5 ? 1 : 0, due_at: .now, position: i) }
    }
}
