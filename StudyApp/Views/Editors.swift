import SwiftUI

struct NameEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let limit: Int
    let save: (String) async throws -> Void
    @State private var value: String
    @State private var busy = false
    @State private var error: String?
    init(title: String, value: String, limit: Int, save: @escaping (String) async throws -> Void) {
        self.title = title; self.limit = limit; self.save = save; _value = State(initialValue: value)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $value)
                if let error { Text(error).foregroundStyle(Theme.errorText) }
            }.navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { busy = true; Task { defer { busy = false }; do { try await save(value.trimmed); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(value.trimmed.isEmpty || value.count > limit || busy) }
                }.interactiveDismissDisabled(busy)
        }.presentationDetents([.medium])
    }
}

struct DeckEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let deck: Deck?
    @State private var title: String
    @State private var folderID: UUID
    @State private var busy = false
    @State private var error: String?
    init(folderID: UUID, deck: Deck? = nil) { self.deck = deck; _title = State(initialValue: deck?.title ?? ""); _folderID = State(initialValue: deck?.folder_id ?? folderID) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Kapiteltitel", text: $title)
                Picker("Ordner", selection: $folderID) { ForEach(store.folders) { Text($0.name).tag($0.id) } }
                if let error { Text(error).foregroundStyle(Theme.errorText) }
            }.navigationTitle(deck == nil ? "Neuer Stapel" : "Stapel bearbeiten")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                        busy = true
                        Task { defer { busy = false }; do { try await store.createDeck(title, folderID: folderID, id: deck?.id); dismiss() } catch { self.error = error.localizedDescription } }
                    }.disabled(title.trimmed.isEmpty || title.count > 200 || busy) }
                }.interactiveDismissDisabled(busy)
        }.presentationDetents([.medium])
    }
}

struct CardEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let card: Card?
    @State private var deckID: UUID
    @State private var question: String
    @State private var answer: String
    @State private var busy = false
    @State private var error: String?
    init(deckID: UUID, card: Card? = nil) {
        self.card = card; _deckID = State(initialValue: card?.deck_id ?? deckID)
        _question = State(initialValue: card?.question ?? ""); _answer = State(initialValue: card?.answer ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Vorderseite · Frage") { TextEditor(text: $question).frame(minHeight: 100).accessibilityLabel("Frage") }
                Section("Rückseite · Antwort") { TextEditor(text: $answer).frame(minHeight: 160).accessibilityLabel("Antwort") }
                Section { Picker("Stapel", selection: $deckID) { ForEach(store.decks) { Text($0.title).tag($0.id) } } }
                if let error { Section { Text(error).foregroundStyle(Theme.errorText) } }
            }.navigationTitle(card == nil ? "Neue Karte" : "Karte bearbeiten")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                        busy = true
                        Task { defer { busy = false }; do { try await store.saveCard(question: question, answer: answer, deckID: deckID, card: card); dismiss() } catch { self.error = error.localizedDescription } }
                    }.disabled(question.trimmed.isEmpty || answer.trimmed.isEmpty || question.count > 10000 || answer.count > 20000 || busy) }
                }.interactiveDismissDisabled(busy)
        }
    }
}
