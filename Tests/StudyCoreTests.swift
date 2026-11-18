import XCTest
@testable import StudyCore

final class StudyCoreTests: XCTestCase {
    private func card(_ status: String = "new", due: Date = .distantPast) -> Card {
        Card(id: UUID(), deck_id: UUID(), question: "Frage", answer: "Antwort", status: status, streak: 0, due_at: due, position: 0)
    }
    func testImportAcceptsChaptersAndUnicode() throws {
        let data = Data(#"{"version":1,"folder":"Mathematik","decks":[{"title":"Kapitel 1","cards":[{"question":"Was bedeutet λ?","answer":"Ein Skalar.\nBeispiel: 2"}]}]}"#.utf8)
        let document = try ImportDocument.parse(data)
        XCTAssertEqual(document.cardCount, 1)
        XCTAssertTrue(document.decks[0].cards[0].answer.contains("\n"))
    }
    func testRejectMalformedEmptyAndFutureVersionImports() {
        let invalid = ["{}", #"{"version":2,"folder":"A","decks":[]}"#, #"{"version":1,"folder":" ","decks":[]}"#, #"{"version":1,"folder":"A","decks":[{"title":"B","cards":[{"question":" ","answer":"A"}]}]}"#]
        for json in invalid { XCTAssertThrowsError(try ImportDocument.parse(Data(json.utf8))) }
        XCTAssertThrowsError(try ImportDocument.parse(Data(repeating: 32, count: 5_000_001)))
    }
    func testPriorityIncludesAllNewUncertainAndDueCards() {
        let cards = [card(), card("uncertain"), card("secure"), card("secure", due: .distantFuture), card("secure", due: .distantFuture)]
        let round = StudyRound(cards: cards)
        XCTAssertEqual(round.queue.count, 3)
        XCTAssertTrue(Set(cards.prefix(3).map(\.id)).isSubset(of: Set(round.queue.map(\.id))))
        XCTAssertEqual(Set(round.queue.map(\.id)).count, round.queue.count)
    }
    func testUncertainRepeatsOnlyOnceAndRoundTerminates() {
        var round = StudyRound(cards: (0..<10).map { _ in card() })
        var iterations = 0
        while round.current != nil && iterations < 100 { round.advance(secure: false); iterations += 1 }
        XCTAssertNil(round.current)
        XCTAssertLessThanOrEqual(iterations, 20)
        XCTAssertGreaterThan(iterations, 10)
        XCTAssertEqual(round.uncertain, iterations)
    }
    func testSecureCardsCannotOverwhelmNewCards() {
        let cards = (0..<10).map { _ in card() } + (0..<100).map { _ in card("secure") }
        let round = StudyRound(cards: cards)
        XCTAssertEqual(round.queue.filter { $0.status == "secure" }.count, 2)
        XCTAssertEqual(round.queue.filter { $0.status == "new" }.count, 10)
    }
    func testCompleteRoundIncludesEverySecureCard() {
        let cards = (0..<30).map { _ in card("secure", due: .distantFuture) }
        var round = StudyRound(cards: cards, includeAll: true)
        XCTAssertEqual(Set(round.queue.map(\.id)), Set(cards.map(\.id)))
        for _ in cards { round.advance(secure: true) }
        XCTAssertNil(round.current)
        XCTAssertEqual(round.completed, cards.count)
    }

    func testRepeatWaitsForOtherCards() {
        var round = StudyRound(cards: (0..<6).map { _ in card() })
        let first = round.current!.id
        round.advance(secure: false)
        XCTAssertFalse(round.queue.prefix(3).contains { $0.id == first })
        XCTAssertEqual(round.queue.filter { $0.id == first }.count, 1)
    }
    func testSingleCardCanFinishAndSecureCardsStillAppear() {
        var one = StudyRound(cards: [card()])
        one.advance(secure: false)
        XCTAssertNil(one.current)
        let secure = StudyRound(cards: (0..<20).map { _ in card("secure", due: .distantFuture) })
        XCTAssertEqual(secure.queue.count, 1)
    }
    @MainActor
    func testModuleRoundCannotContainOtherModules() async throws {
        let store = AppStore()
        store.demo = true
        let a = Folder(id: UUID(), name: "Modul A")
        let b = Folder(id: UUID(), name: "Modul B")
        let a1 = Deck(id: UUID(), folder_id: a.id, title: "A1")
        let a2 = Deck(id: UUID(), folder_id: a.id, title: "A2")
        let b1 = Deck(id: UUID(), folder_id: b.id, title: "B1")
        store.folders = [a, b]; store.decks = [a1, a2, b1]
        var first = card(); first.deck_id = a1.id
        var second = card("uncertain"); second.deck_id = a2.id
        var foreign = card(); foreign.deck_id = b1.id
        store.cards = [first, second, foreign]
        let moduleCards = store.cards(in: a)
        XCTAssertEqual(Set(moduleCards.map(\.id)), [first.id, second.id])
        let round = StudyRound(cards: moduleCards)
        XCTAssertFalse(round.queue.contains { $0.id == foreign.id })
        XCTAssertEqual(round.queue.count, 2)
    }

    @MainActor
    func testManualSelectionChangesOnlyChosenCardsAndIsIdempotent() async throws {
        let store = AppStore()
        store.startDemo()
        let deck = store.decks[0]
        let selected = Set(store.cards.prefix(2).map(\.id))
        let untouched = Array(store.cards.dropFirst(2))
        try await store.setCardStatus(.secure, ids: selected, in: deck)
        try await store.setCardStatus(.secure, ids: selected, in: deck)
        let changed = store.cards.filter { selected.contains($0.id) }
        XCTAssertTrue(changed.allSatisfy { $0.status == "secure" && $0.streak == 1 })
        XCTAssertTrue(changed.allSatisfy { $0.due_at > Date().addingTimeInterval(86300) })
        XCTAssertEqual(Array(store.cards.dropFirst(2)), untouched)
        try await store.setCardStatus(.uncertain, ids: selected, in: deck)
        XCTAssertTrue(store.cards.filter { selected.contains($0.id) }.allSatisfy { $0.status == "uncertain" && $0.streak == 0 })
        XCTAssertEqual(Array(store.cards.dropFirst(2)), untouched)
    }

    @MainActor
    func testInvalidSelectionDoesNotPartiallyModifyCards() async throws {
        let store = AppStore()
        store.startDemo()
        let original = store.cards
        do {
            try await store.setCardStatus(.secure, ids: [original[0].id, UUID()], in: store.decks[0])
            XCTFail("Invalid selection must fail atomically")
        } catch { XCTAssertEqual(store.cards, original) }
        do {
            try await store.setCardStatus(.uncertain, ids: [], in: store.decks[0])
            XCTFail("Empty selection must not mark all cards")
        } catch { XCTAssertEqual(store.cards, original) }
    }

    @MainActor
    func testDeckResetRestoresNewStateAndPreservesOtherDecksAndContent() async throws {
        let store = AppStore()
        store.startDemo()
        let deck = store.decks[0]
        let other = Deck(id: UUID(), folder_id: deck.folder_id, title: "Anderes Kapitel")
        store.decks.append(other)
        var foreign = card("secure"); foreign.deck_id = other.id; foreign.streak = 12
        store.cards.append(foreign)
        let original = store.cards(in: deck)
        try await store.setCardStatus(.secure, ids: Set(original.map(\.id)), in: deck)
        let before = Date()
        try await store.resetProgress(in: deck)
        let reset = store.cards(in: deck)
        XCTAssertEqual(reset.map(\.id), original.map(\.id))
        XCTAssertEqual(reset.map(\.question), original.map(\.question))
        XCTAssertEqual(reset.map(\.answer), original.map(\.answer))
        XCTAssertTrue(reset.allSatisfy { $0.status == "new" && $0.streak == 0 && $0.due_at >= before && $0.due_at <= Date() })
        XCTAssertEqual(store.cards(in: other), [foreign])
    }

}
