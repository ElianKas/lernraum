import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showImport = false
    @State private var showFolder = false
    @State private var showAccount = false
    @State private var editing: Folder?
    @State private var deleting: Folder?
    private var secureCount: Int { store.cards.filter { $0.status == "secure" }.count }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ein bisschen heute.\nMehr im Kopf morgen.").font(.system(.title, design: .serif, weight: .semibold))
                        HStack(spacing: 24) {
                            metric("\(store.cards.count)", "Karten")
                            metric("\(secureCount)", "Sicher")
                            metric("\(store.folders.count)", "Module")
                        }
                        if !store.cards.isEmpty {
                            NavigationLink { StudyView(cards: store.cards, title: "Alle Module") } label: {
                                Label("Modulübergreifend lernen", systemImage: "play.fill").fontWeight(.semibold).padding(.vertical, 6)
                            }
                        }
                    }.padding(.vertical, 12)
                }.listRowBackground(Theme.mint)
                Section("Deine Module") {
                    if store.folders.isEmpty {
                        ContentUnavailableView("Platz für neues Wissen", systemImage: "folder.badge.plus", description: Text("Lege einen Ordner an oder importiere deine Kapitel und Karten als JSON-Datei."))
                        Button("Karten importieren", systemImage: "square.and.arrow.down") { showImport = true }
                    }
                    ForEach(store.folders) { folder in
                        NavigationLink { FolderView(folderID: folder.id) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill").foregroundStyle(Theme.ink).font(.title2).frame(width: 38)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(folder.name).font(.headline)
                                    Text("\(store.decks(in: folder).count) Stapel").font(.caption).foregroundStyle(Theme.secondaryText)
                                }.padding(.vertical, 8)
                            }
                        }
                        .swipeActions {
                            Button("Löschen", role: .destructive) { deleting = folder }
                            Button("Umbenennen") { editing = folder }.tint(.gray)
                        }
                        .contextMenu {
                            Button("Umbenennen", systemImage: "pencil") { editing = folder }
                            Button("Löschen", systemImage: "trash", role: .destructive) { deleting = folder }
                        }
                    }
                }
                if store.demo { Section { Label("Demo · Änderungen bleiben nur bis zum Abmelden", systemImage: "info.circle").font(.caption).foregroundStyle(Theme.secondaryText) } }
            }
            .navigationTitle("Dein Lernraum")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Konto", systemImage: "person.crop.circle") { showAccount = true } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Ordner erstellen", systemImage: "folder.badge.plus") { showFolder = true }
                        Button("Karten importieren", systemImage: "square.and.arrow.down") { showImport = true }
                    } label: { Image(systemName: "plus").accessibilityLabel("Hinzufügen") }
                }
            }
            .refreshable { await store.reload() }
            .overlay { if store.loading && store.folders.isEmpty { ProgressView() } }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(isPresented: $showFolder) { NameEditor(title: "Neuer Ordner", value: "", limit: 120) { try await store.createFolder($0) } }
            .sheet(item: $editing) { folder in NameEditor(title: "Ordner umbenennen", value: folder.name, limit: 120) { try await store.createFolder($0, id: folder.id) } }
            .sheet(isPresented: $showAccount) {
                NavigationStack {
                    Form {
                        Section("Angemeldet als") { Text(store.email) }
                        Section { Text("Karten werden online in deinem Supabase-Konto gespeichert. Zum Laden und Bewerten brauchst du eine Internetverbindung.") }
                        Button("Abmelden", role: .destructive) { Task { await store.logout() } }
                    }.navigationTitle("Dein Konto").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showAccount = false } } }
                }.presentationDetents([.medium])
            }
            .confirmationDialog("Ordner und alle enthaltenen Stapel und Karten löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Endgültig löschen", role: .destructive) {
                    guard let folder = deleting else { return }
                    Task { do { try await store.delete("folders", id: folder.id) } catch { store.error = error.localizedDescription } }; deleting = nil
                }
            }
        }
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value).font(.title2.bold()); Text(label).font(.caption).foregroundStyle(Theme.secondaryText) }
    }
}

struct FolderView: View {
    @EnvironmentObject private var store: AppStore
    let folderID: UUID
    @State private var adding = false
    @State private var editing: Deck?
    @State private var deleting: Deck?
    private var folder: Folder? { store.folders.first { $0.id == folderID } }
    var body: some View {
        List {
            if let folder {
                let decks = store.decks(in: folder)
                let moduleCards = store.cards(in: folder)
                if !moduleCards.isEmpty {
                    Section {
                        NavigationLink { StudyView(cards: moduleCards, title: folder.name) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Gezielt wiederholen", systemImage: "play.fill").font(.headline)
                                Text("\(moduleCards.count) Karten aus \(decks.count) Stapeln · nur dieses Modul")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }.padding(.vertical, 8)
                        }
                        NavigationLink {
                            StudyView(cards: moduleCards, title: folder.name, includeAll: true)
                        } label: {
                            Label("Alle Karten dieses Moduls lernen", systemImage: "rectangle.stack")
                        }
                    }.listRowBackground(Theme.mint)
                }
                if decks.isEmpty {
                    ContentUnavailableView("Dein erstes Kapitel", systemImage: "rectangle.stack.badge.plus", description: Text("Erstelle einen Stapel und füge deine Fragen hinzu."))
                }
                ForEach(decks) { deck in
                    NavigationLink { DeckView(deckID: deck.id) } label: {
                        let cards = store.cards(in: deck)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(deck.title).font(.headline)
                            HStack { Text("\(cards.count) Karten"); Spacer(); Text("\(cards.filter { $0.status == "secure" }.count) sicher") }.font(.caption).foregroundStyle(Theme.secondaryText)
                            ProgressView(value: Double(cards.filter { $0.status == "secure" }.count), total: Double(max(1, cards.count))).tint(Theme.ink)
                        }.padding(.vertical, 10)
                    }.swipeActions {
                        Button("Löschen", role: .destructive) { deleting = deck }
                        Button("Bearbeiten") { editing = deck }.tint(.gray)
                    }.contextMenu {
                        Button("Bearbeiten", systemImage: "pencil") { editing = deck }
                        Button("Löschen", systemImage: "trash", role: .destructive) { deleting = deck }
                    }
                }
            }
        }.navigationTitle(folder?.name ?? "Ordner")
            .toolbar { Button("Stapel erstellen", systemImage: "plus") { adding = true } }
            .refreshable { await store.reload() }
            .sheet(isPresented: $adding) { DeckEditor(folderID: folderID) }
            .sheet(item: $editing) { DeckEditor(folderID: folderID, deck: $0) }
            .confirmationDialog("Stapel mit allen Karten löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Endgültig löschen", role: .destructive) {
                    guard let deck = deleting else { return }
                    Task { do { try await store.delete("decks", id: deck.id) } catch { store.error = error.localizedDescription } }; deleting = nil
                }
            }
    }
}

struct DeckView: View {
    @EnvironmentObject private var store: AppStore
    let deckID: UUID
    @State private var adding = false
    @State private var editing: Card?
    @State private var deleting: Card?
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmingReset = false
    @State private var busy = false
    @State private var operationError: String?
    @State private var notice: String?
    private var deck: Deck? { store.decks.first { $0.id == deckID } }
    private var cards: [Card] { store.cards.filter { $0.deck_id == deckID } }
    private var allIDs: Set<UUID> { Set(cards.map(\.id)) }

    var body: some View {
        List {
            if let deck {
                if !cards.isEmpty {
                    if !selecting {
                        Section {
                            NavigationLink { StudyView(cards: cards, title: deck.title) } label: {
                                Label("Diesen Stapel lernen", systemImage: "play.fill").font(.headline).padding(.vertical, 8)
                            }
                        }.listRowBackground(Theme.mint)
                    } else {
                        selectionControls
                    }
                } else {
                    ContentUnavailableView("Noch keine Karten", systemImage: "rectangle.on.rectangle", description: Text("Füge deine erste Frage und Antwort hinzu."))
                }
                if let operationError {
                    Section { Text(operationError).font(.callout).foregroundStyle(Theme.errorText) }
                }
                if let notice {
                    Section { Label(notice, systemImage: "checkmark.circle").font(.callout).foregroundStyle(Theme.ink) }
                }
                Section {
                    ForEach(cards) { card in
                        cardRow(card)
                    }
                } header: {
                    Text("Alle Karten · \(cards.count)")
                } footer: {
                    if !selecting && !cards.isEmpty {
                        Text("Wische eine Karte nach rechts, um ihren Status zu ändern, oder nutze das Menü durch langes Drücken. Mit Auswählen änderst du mehrere Karten gleichzeitig.")
                    }
                }
            }
        }
        .disabled(busy)
        .navigationTitle(deck?.title ?? "Stapel")
        .navigationBarBackButtonHidden(busy)
        .toolbar { deckToolbar }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionActions }
        }
        .overlay {
            if busy {
                ProgressView("Wird gespeichert …").padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .refreshable { if !busy { await store.reload() } }
        .onChange(of: allIDs) { _, ids in selectedIDs.formIntersection(ids) }
        .sheet(isPresented: $adding) { CardEditor(deckID: deckID) }
        .sheet(item: $editing) { CardEditor(deckID: deckID, card: $0) }
        .confirmationDialog("Diese Karte löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                guard let card = deleting else { return }
                deleting = nil
                perform { try await store.delete("cards", id: card.id) }
            }
        }
        .confirmationDialog("Lernfortschritt des gesamten Stapels zurücksetzen?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Alle Karten auf neu zurücksetzen", role: .destructive) {
                guard let deck else { return }
                perform {
                    try await store.resetProgress(in: deck)
                    selectedIDs = []; selecting = false
                    notice = "Lernfortschritt zurückgesetzt. Alle Karten sind wieder neu."
                }
            }
        } message: {
            Text("Alle \(cards.count) Karten werden als neu markiert. Sicherheitsmarkierungen und Wiederholungsserien werden zurückgesetzt. Fragen und Antworten bleiben erhalten. Das lässt sich nicht rückgängig machen.")
        }
    }

    private var selectionControls: some View {
        Section {
            HStack {
                Button("Alle auswählen") { selectedIDs = allIDs }
                    .disabled(selectedIDs == allIDs)
                Spacer()
                Button("Alle abwählen") { selectedIDs = [] }
                    .disabled(selectedIDs.isEmpty)
            }.buttonStyle(.borderless)
            Text("\(selectedIDs.count) von \(cards.count) Karten ausgewählt")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
    }
    private var selectionActions: some View {
        VStack(spacing: 10) {
            Text("Status für \(selectedIDs.count) ausgewählte Karten")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button { setStatus(.uncertain, ids: selectedIDs) } label: {
                    Label("Unsicher", systemImage: "arrow.clockwise.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.warningBackground, in: RoundedRectangle(cornerRadius: 14))
                }.tint(Theme.warningText)
                Button { setStatus(.secure, ids: selectedIDs) } label: {
                    Label("Sicher", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 14))
                }.tint(Theme.ink)
            }.fontWeight(.semibold)
        }
        .padding(.horizontal).padding(.vertical, 12).background(.bar)
        .disabled(selectedIDs.isEmpty || busy)
    }
    @ToolbarContentBuilder private var deckToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                if !cards.isEmpty {
                    Button(selecting ? "Fertig" : "Auswählen") {
                        selecting.toggle(); selectedIDs = []; operationError = nil; notice = nil
                    }
                }
                Menu {
                    Button("Karte erstellen", systemImage: "plus") { adding = true }
                    Button("Stapel zurücksetzen", systemImage: "arrow.counterclockwise", role: .destructive) {
                        confirmingReset = true
                    }.disabled(cards.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("Stapel-Aktionen")
                }
            }.disabled(busy)
        }
    }
    private func cardRow(_ card: Card) -> some View {
        Button {
            if selecting {
                if selectedIDs.contains(card.id) { selectedIDs.remove(card.id) }
                else { selectedIDs.insert(card.id) }
            } else { editing = card }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if selecting {
                    Image(systemName: selectedIDs.contains(card.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(Theme.ink)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(statusTitle(card), systemImage: statusIcon(card))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(card.status == "secure" ? Theme.ink : Theme.secondaryText)
                    Text(card.question).font(.headline).foregroundStyle(.primary).lineLimit(3)
                    Text(card.answer).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityValue(selecting ? (selectedIDs.contains(card.id) ? "Ausgewählt" : "Nicht ausgewählt") : statusTitle(card))
        .contextMenu {
            if !selecting {
                Button("Als unsicher markieren", systemImage: "arrow.clockwise.circle") { setStatus(.uncertain, ids: [card.id]) }
                Button("Als sicher markieren", systemImage: "checkmark.circle") { setStatus(.secure, ids: [card.id]) }
                Button("Bearbeiten", systemImage: "pencil") { editing = card }
                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = card }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !selecting {
                Button("Sicher") { setStatus(.secure, ids: [card.id]) }.tint(Theme.buttonBackground)
                Button("Unsicher") { setStatus(.uncertain, ids: [card.id]) }.tint(Color(red: 0.48, green: 0.23, blue: 0.02))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !selecting { Button("Löschen", role: .destructive) { deleting = card } }
        }
    }
    private func statusTitle(_ card: Card) -> String {
        card.status == "secure" ? "Sicher" : card.status == "uncertain" ? "Unsicher" : "Neu"
    }
    private func statusIcon(_ card: Card) -> String {
        card.status == "secure" ? "checkmark.circle.fill" : card.status == "uncertain" ? "arrow.clockwise.circle" : "circle.dotted"
    }
    private func setStatus(_ change: CardProgressChange, ids: Set<UUID>) {
        guard let deck else { return }
        perform {
            try await store.setCardStatus(change, ids: ids, in: deck)
            notice = "\(ids.count) \(ids.count == 1 ? "Karte" : "Karten") als \(change == .secure ? "sicher" : "unsicher") markiert."
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; operationError = nil; notice = nil
        Task {
            defer { busy = false }
            do { try await action() }
            catch { operationError = error.localizedDescription }
        }
    }
}
