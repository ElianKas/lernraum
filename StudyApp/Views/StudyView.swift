import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    @State private var round: StudyRound
    @State private var revealed = false
    @State private var drag: CGFloat = 0
    @State private var saving = false
    @State private var error: String?
    @State private var reviewID = UUID()
    @State private var pendingRating: Bool?
    @State private var showExit = false

    init(cards: [Card], title: String, includeAll: Bool = false) {
        self.title = title
        _round = State(initialValue: StudyRound(cards: cards, includeAll: includeAll))
    }
    var body: some View {
        VStack(spacing: 20) {
            if let card = round.current {
                progressHeader
                StudyCardFace(card: card, revealed: revealed, drag: drag, reduceMotion: reduceMotion)
                    .simultaneousGesture(swipeGesture)
                    .onTapGesture { if !revealed { withAnimation { revealed = true } } }
                    .accessibilityAction(named: "Antwort aufdecken") { revealed = true }
                    .accessibilityAction(named: "Als unsicher bewerten") { if canRate { rate(false) } }
                    .accessibilityAction(named: "Als sicher bewerten") { if canRate { rate(true) } }
                errorView
                if saving { ProgressView("Bewertung wird gespeichert …").font(.caption) }
                controls
            } else {
                summary
            }
        }
        .padding(22).frame(maxWidth: .infinity).background(Theme.paper)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Beenden", systemImage: "xmark") { showExit = true }.disabled(saving)
            }
        }
        .confirmationDialog("Lernrunde beenden? Gespeicherte Bewertungen bleiben erhalten.", isPresented: $showExit, titleVisibility: .visible) {
            Button("Runde beenden", role: .destructive) { dismiss() }
        }
    }
    private var canRate: Bool { revealed && !saving && pendingRating == nil }
    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(round.completed + 1) / \(round.total)").monospacedDigit()
                Spacer()
                Text("\(round.secure) sicher").foregroundStyle(Theme.secondaryText)
            }.font(.subheadline)
            ProgressView(value: Double(round.completed), total: Double(max(round.total, 1))).tint(Theme.ink)
        }
    }
    @ViewBuilder private var errorView: some View {
        if let error {
            VStack(spacing: 8) {
                Text(error).font(.footnote).foregroundStyle(Theme.errorText)
                if let pendingRating {
                    Button("Bewertung erneut speichern") { rate(pendingRating) }.disabled(saving)
                }
            }
        }
    }
    @ViewBuilder private var controls: some View {
        if revealed {
            HStack(spacing: 14) {
                Button { rate(false) } label: {
                    Label("Unsicher", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity).padding(18)
                        .background(Theme.warningBackground, in: RoundedRectangle(cornerRadius: 16))
                }.tint(Theme.warningText)
                Button { rate(true) } label: {
                    Label("Sicher", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity).padding(18)
                        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 16))
                }
            }.fontWeight(.semibold).disabled(!canRate)
            Text("Links: wiederholen · Rechts: sitzt").font(.caption).foregroundStyle(Theme.secondaryText)
        } else {
            PrimaryButton(title: "Antwort aufdecken") { withAnimation { revealed = true } }
        }
    }
    private var summary: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.ink)
            Text("Wieder ein Stück weiter.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
            Text("Du hast \(round.completed) Bewertungen abgegeben.\n\(round.secure) sicher · \(round.uncertain) unsicher")
                .multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            Text("Unsichere Karten haben in der nächsten Runde Vorrang. Sichere Karten bleiben zur Überprüfung dabei.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            Spacer()
            PrimaryButton(title: "Runde abschließen") { dismiss() }
        }
    }
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onChanged { value in
                guard canRate, abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                defer { withAnimation { drag = 0 } }
                guard canRate, abs(value.translation.width) > 100,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                rate(value.translation.width > 0)
            }
    }
    private func rate(_ secure: Bool) {
        guard revealed, !saving, let card = round.current else { return }
        saving = true; error = nil; pendingRating = secure
        Task {
            defer { saving = false }
            do {
                let latest = store.cards.first { $0.id == card.id } ?? card
                try await store.review(latest, secure: secure, reviewID: reviewID)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    round.advance(secure: secure); revealed = false; drag = 0
                }
                pendingRating = nil; reviewID = UUID()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct StudyCardFace: View {
    let card: Card
    let revealed: Bool
    let drag: CGFloat
    let reduceMotion: Bool
    private var ratingColor: Color { drag > 0 ? Theme.ink : Theme.warningText }
    private var contentFont: Font {
        revealed ? .title3 : .system(.title2, design: .serif, weight: .medium)
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(revealed ? "ANTWORT" : "FRAGE").font(.caption.weight(.bold)).tracking(2)
                Spacer()
                if abs(drag) > 25 {
                    Text(drag > 0 ? "SICHER" : "UNSICHER").font(.caption.bold()).foregroundStyle(ratingColor)
                }
            }.foregroundStyle(Theme.secondaryText)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if revealed {
                        Text(card.question).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        Divider()
                    }
                    Text(revealed ? card.answer : card.question)
                        .font(contentFont).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(revealed ? "Antwort: \(card.answer)" : "Frage: \(card.question)")
                }.padding(.vertical, 16)
            }
            if !revealed { Text("Erst erinnern, dann aufdecken.").font(.caption).foregroundStyle(Theme.secondaryText) }
        }
        .padding(26).frame(maxWidth: 620, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(drag == 0 ? Color.clear : ratingColor.opacity(0.5), lineWidth: 2) }
        .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
        .offset(x: reduceMotion ? 0 : drag * 0.4)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag / 45)))
    }
}
