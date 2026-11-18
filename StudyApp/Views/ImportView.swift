import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var promptCopied = false
    @State private var showingGuide = false
    @State private var choosing = false
    @State private var document: ImportDocument?
    @State private var filename = ""
    @State private var error: String?
    @State private var busy = false
    @State private var imported = false
    @State private var requestID = UUID()
    var body: some View {
        NavigationStack {
            List {
                if imported {
                    ContentUnavailableView("Bereit zum Lernen", systemImage: "checkmark.circle.fill", description: Text("Deine Kapitel und Karten wurden importiert."))
                    Button("Zur Bibliothek") { dismiss() }
                } else {
                    Section {
                        Text("Vom Skript zu deinen Karten").font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Lass deine KI Fragen und Antworten nach Kapiteln erstellen. Importiere anschließend die JSON-Datei im Study-App-Format.").foregroundStyle(Theme.secondaryText)
                        Button {
                            UIPasteboard.general.string = ImportGuideContent.prompt
                            promptCopied = true
                        } label: {
                            Label(promptCopied ? "Prompt kopiert" : "KI-Prompt kopieren", systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                                .fontWeight(.semibold)
                        }
                        Button("Import-Anleitung", systemImage: "questionmark.circle") { showingGuide = true }
                        Button("JSON-Datei auswählen", systemImage: "doc.badge.plus") { choosing = true }.disabled(busy)
                    }
                    if let document {
                        Section("Vorschau · \(filename)") {
                            LabeledContent("Neuer Ordner", value: document.folder)
                            LabeledContent("Stapel", value: "\(document.decks.count)")
                            LabeledContent("Karten", value: "\(document.cardCount)")
                        }
                        ForEach(Array(document.decks.enumerated()), id: \.offset) { _, deck in
                            Section(deck.title) {
                                Text("\(deck.cards.count) Karten").font(.caption).foregroundStyle(Theme.secondaryText)
                                if let first = deck.cards.first {
                                    Text(first.question).font(.headline)
                                    Text(first.answer).foregroundStyle(Theme.secondaryText).lineLimit(5)
                                }
                            }
                        }
                        Section {
                            Text("Jeder Import legt einen neuen Ordner an. Bestehende Karten werden nicht überschrieben.").font(.caption).foregroundStyle(Theme.secondaryText)
                            PrimaryButton(title: "\(document.cardCount) Karten importieren", busy: busy) {
                                busy = true; error = nil
                                Task {
                                    defer { busy = false }
                                    do { try await store.importCards(document, requestID: requestID); imported = true }
                                    catch { self.error = error.localizedDescription }
                                }
                            }.listRowBackground(Color.clear)
                        }
                    } else {
                        Section("Beispielformat") {
                            Text(Self.example).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            ShareLink(item: ExampleJSON(), preview: SharePreview("Study-App Beispiel")) { Label("Beispieldatei teilen", systemImage: "square.and.arrow.up") }
                        }
                    }
                    if let error { Section { Text(error).foregroundStyle(Theme.errorText) } }
                }
            }.navigationTitle("Karten importieren")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(busy) } }
                .sheet(isPresented: $showingGuide) { ImportGuideView() }
                .interactiveDismissDisabled(busy)
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 5_000_000 else { throw AppError.message("Die Datei darf höchstens 5 MB groß sein.") }
                        let parsed = try ImportDocument.parse(Data(contentsOf: url))
                        document = parsed; filename = url.lastPathComponent; requestID = UUID(); error = nil
                    } catch { document = nil; self.error = error.localizedDescription }
                }
        }
    }
    nonisolated static let example = """
    {
      "version": 1,
      "folder": "Mein Modul",
      "decks": [{
        "title": "01 · Grundlagen",
        "cards": [{
          "question": "Was ist eine Basis?",
          "answer": "Ein linear unabhängiges Erzeugendensystem."
        }]
      }]
    }
    """
}
struct ExampleJSON: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { _ in Data(ImportView.example.utf8) }.suggestedFileName("study-import.json")
    }
}


private struct ImportGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Dein Skript wird zu Lernkarten")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Du bereitest die Karten mit einer KI deiner Wahl vor. In Lernraum importierst du anschließend die fertige JSON-Datei.")
                        .foregroundStyle(Theme.secondaryText)
                }
                Section("So geht’s") {
                    step("1", title: "Unterlagen an deine KI geben", detail: "Hänge dein Kursskript und optional eine Musterklausur an, zum Beispiel in ChatGPT. Kopiere den Prompt unten dazu. Ergänze bei Bedarf, welche Kapitel oder Themen du lernen möchtest.")
                    step("2", title: "JSON-Datei speichern", detail: "Bitte die KI um eine herunterladbare .json-Datei und speichere sie auf deinem iPhone in der Dateien-App. Falls du nur Text erhältst, lass daraus eine JSON-Datei erstellen. Ein PDF oder das Skript selbst lässt sich hier nicht direkt importieren.")
                    step("3", title: "Vorschau prüfen und importieren", detail: "Wähle in der Importansicht die JSON-Datei aus. Prüfe Modul, Kapitel und Beispielkarten und bestätige den Import. Jede Datei legt einen neuen Modulordner mit Kapitelstapeln an.")
                }
                Section("Vorlage für deine KI") {
                    Text("Der Prompt enthält das benötigte Format und alle Importgrenzen. Du kannst ihn unverändert zusammen mit deinen Unterlagen verwenden.")
                        .foregroundStyle(Theme.secondaryText)
                    Button {
                        UIPasteboard.general.string = ImportGuideContent.prompt
                        copied = true
                    } label: {
                        Label(copied ? "Prompt kopiert" : "KI-Prompt kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .fontWeight(.semibold).padding(.vertical, 6)
                    }
                    ShareLink(item: ImportGuideContent.prompt) {
                        Label("Prompt teilen", systemImage: "square.and.arrow.up")
                    }
                    DisclosureGroup("Vollständigen Prompt ansehen") {
                        Text(ImportGuideContent.prompt).font(.callout).textSelection(.enabled).padding(.vertical, 8)
                    }
                }
                Section("Dateiformat und Grenzen") {
                    LabeledContent("Datei", value: "JSON · UTF-8 · max. 5 MB")
                    LabeledContent("Formatversion", value: "version: 1")
                    LabeledContent("Modulordner", value: "folder · 1–120 Zeichen")
                    LabeledContent("Kapitelstapel", value: "decks · 1–100 Stapel")
                    LabeledContent("Stapeltitel", value: "title · 1–200 Zeichen")
                    LabeledContent("Karten insgesamt", value: "Maximal 2.000 pro Datei")
                    LabeledContent("Frage", value: "question · 1–10.000 Zeichen")
                    LabeledContent("Antwort", value: "answer · 1–20.000 Zeichen")
                    Text("Jeder Stapel braucht mindestens eine Karte. Alle Namen, Fragen und Antworten müssen ausgefüllt sein. Verwende einfachen Text. Bilder, HTML und LaTeX werden nicht dargestellt.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                    DisclosureGroup("JSON-Beispiel ansehen") {
                        Text(ImportView.example).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).padding(.vertical, 8)
                    }
                }
                Section("Vor dem Lernen") {
                    Text("Prüfe die fachliche Richtigkeit der KI-Karten. Bei großen Skripten kannst du einzelne Kapitel nacheinander erstellen lassen. Jeder separate Import erzeugt einen neuen Ordner, auch bei gleichem Namen; Stapel kannst du danach in einen gemeinsamen Ordner verschieben.")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Import-Anleitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .tint(Theme.ink)
    }

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30).background(Theme.mint, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(Theme.secondaryText)
            }
        }.padding(.vertical, 6)
    }
}

private enum ImportGuideContent {
    static let prompt = #"""
    Erstelle aus meinem beigefügten Kursskript Lernkarten zur Klausurvorbereitung. Wenn ich eine Musterklausur beifüge, nutze sie zur Orientierung an Fragetypen und Schwerpunkten. Decke trotzdem die relevanten Inhalte des Skripts ab. Wenn ich bestimmte Kapitel nenne, beschränke dich darauf.

    Inhalt:
    - Ein Modulordner, ein Stapel pro Skriptlektion oder Kapitel. Stelle die Kapitelnummer an den Anfang des Stapeltitels.
    - Pro Karte eine konkrete, eigenständig verständliche Frage mit präziser Antwort. Teile umfangreiche Inhalte in mehrere Karten auf und vermeide Duplikate.
    - Nutze Definitionen, Verständnisfragen, Abgrenzungen und kurze Anwendungsbeispiele. Erfinde keine Informationen. Lass unlesbare oder unklare Inhalte aus und melde sie separat, bevor du die Datei erstellst.
    - Verwende deutschen, einfachen Text. Keine Bilder, kein HTML, keine Markdown- oder LaTeX-Formatierung. Unicode-Zeichen wie λ sind möglich.

    Ausgabe:
    Erstelle eine herunterladbare UTF-8-Datei namens lernkarten.json. Die Datei darf ausschließlich gültiges JSON enthalten: keine Einleitung, keine Kommentare, keine Markdown-Codeblöcke. Falls du keine Datei erstellen kannst, gib nur den reinen JSON-Inhalt aus.

    Verwende genau diese Struktur und Feldnamen:
    {
      "version": 1,
      "folder": "Modulname",
      "decks": [
        {
          "title": "01 · Kapitelname",
          "cards": [
            {
              "question": "Eine konkrete Frage?",
              "answer": "Eine verständliche Antwort."
            }
          ]
        }
      ]
    }

    Verbindliche Importregeln:
    - version ist die Zahl 1, kein Text.
    - folder ist ein nicht leerer Text mit maximal 120 Zeichen.
    - decks enthält 1 bis 100 Stapel.
    - Jeder Stapel hat title (nicht leer, maximal 200 Zeichen) und cards (mindestens eine Karte).
    - Jede Karte hat question (nicht leer, maximal 10.000 Zeichen) und answer (nicht leer, maximal 20.000 Zeichen).
    - Insgesamt maximal 2.000 Karten über alle Stapel und maximal 5 MB pro Datei. Das sind Obergrenzen, keine Zielanzahl. Wähle den Kartenumfang nach dem Lernstoff.
    - Kein Pflichtfeld darf fehlen, null sein oder nur Leerzeichen enthalten. Gib keine IDs, Statuswerte, Lernfortschritte oder sonstigen Zusatzfelder aus; diese verwaltet die App.
    - Halte JSON korrekt: doppelte Anführungszeichen, keine nachgestellten Kommas. Kodiere Zeilenumbrüche innerhalb von Texten als \n und Anführungszeichen innerhalb von Texten als \".
    - Wenn du den Stoff innerhalb dieser Grenzen nicht sinnvoll abdecken kannst, frage mich vor der Dateierstellung nach einer Aufteilung in kleinere Kapitelgruppen.

    Prüfe vor der Ausgabe die JSON-Syntax, alle Pflichtfelder, die Textlängen, die Zahl der Stapel und die Gesamtzahl der Karten.
    """#
}
