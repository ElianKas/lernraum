# Lernraum · Study App

Lernraum ist eine native iOS-App für Karteikarten. Du kannst Lernkarten als JSON importieren, nach Modulen und Kapiteln organisieren und in Lernrunden wiederholen. Die App verwendet SwiftUI ab iOS 17. Supabase speichert Lernkarten und Fortschritt für angemeldete Konten.

## Start in Xcode

1. `StudyApp.xcodeproj` öffnen.
2. Scheme **StudyApp**, ein iPhone bzw. einen Simulator wählen.
3. Für ein echtes iPhone unter **Signing & Capabilities** dein Development Team auswählen. Bundle Identifier bei Bedarf anpassen.
4. App starten. Ohne Supabase-Konfiguration ist **Mit Beispielkarten ausprobieren** verfügbar. Demo-Daten bleiben nur im Arbeitsspeicher und werden beim Abmelden verworfen.

Das Xcode-Projekt ist bereits vorhanden und benötigt keinen Projektgenerator. Nach dem Hinzufügen neuer Swift-Dateien lässt es sich mit `python3 scripts/generate_project.py` neu erzeugen. Dabei werden manuelle Projekteinstellungen überschrieben; Signing danach ggf. erneut setzen.

## Supabase verbinden

1. Ein neues Supabase-Projekt anlegen, vorzugsweise in einer europäischen Region.
2. Beide Dateien aus [`supabase/migrations/`](supabase/migrations/) in aufsteigender Reihenfolge im **SQL Editor** ausführen. Wenn du bereits ein eigenes Projekt mit der Supabase-CLI verknüpft hast, kannst du stattdessen `npx supabase db push` verwenden. Bei einer bestehenden Installation wende nur fehlende Migrationen an.
3. Unter **Authentication → Providers / Sign In** E-Mail/Passwort aktivieren. E-Mail-Bestätigung kann eingeschaltet bleiben: nach Registrierung den Bestätigungslink öffnen, dann in der App mit E-Mail/Passwort anmelden. Der Link selbst meldet nicht automatisch in der App an.
4. Projekt-URL und **Publishable Key** oder den älteren **anon public key** aus den Projekteinstellungen übernehmen.
5. Die Datei `StudyApp/Configuration/Config.local.xcconfig` mit folgendem Inhalt erstellen:

```xcconfig
SUPABASE_URL = https:$(SLASH)$(SLASH)DEIN_PROJEKT.supabase.co
SUPABASE_ANON_KEY = DEIN_PUBLISHABLE_ODER_ANON_KEY
```

Die `$(SLASH)`-Schreibweise ist notwendig, weil `//` in xcconfig-Dateien einen Kommentar beginnt. Alternativ die Platzhalter direkt in `Config.xcconfig` ersetzen. Die lokale Konfigurationsdatei wird von Git ignoriert. **Keinen Secret Key oder Service-Role-Key verwenden.** Der öffentliche Client-Key steht zwangsläufig in der gebauten App; die eigentliche Zugriffskontrolle erfolgt über Supabase RLS.

6. App neu bauen und starten. Eigenes Konto anlegen, bestätigen und anmelden.

Tabellen: `folders`, `decks`, `cards`, `review_events`. Jede Zeile gehört einer Supabase-Auth-User-ID. RLS und zusammengesetzte Fremdschlüssel verhindern auch das Zuordnen eigener Karten zu fremden Stapeln oder fremder Stapel zu eigenen Ordnern. Import und Bewertungen laufen als SECURITY INVOKER mit den Rechten des angemeldeten Nutzers.

## Funktionen

- Registrierung, Login, Logout und Wiederherstellung einer Sitzung aus der iOS Keychain.
- Automatische Token-Erneuerung vor Ablauf; kein Speichern von Passwörtern.
- Ordner erstellen, umbenennen und mit allen Inhalten nach Bestätigung löschen.
- Stapel erstellen, bearbeiten, zwischen Ordnern verschieben und löschen.
- Textkarten erstellen, bearbeiten, zwischen Stapeln verschieben und löschen.
- JSON-Datei über den iOS-Dateidialog importieren; Vorschau nach Kapitel, Validierung und atomarer Import.
- Ein komplettes Modul mit allen zugehörigen Kapitelstapeln lernen, ohne Karten anderer Module. Optional einzelne Stapel oder ausdrücklich modulübergreifend lernen.
- Karten einzeln per Wischaktion/Kontextmenü oder per Mehrfachauswahl auf sicher/unsicher setzen. Alle auswählen und alle abwählen sind im Auswahlmodus verfügbar.
- Gesamten Stapelfortschritt nach Bestätigung auf neu zurücksetzen; Fragen und Antworten bleiben erhalten.
- Antwort per Tippen/Button aufdecken, links unsicher und rechts sicher; alternativ Buttons und VoiceOver-Aktionen.
- Bewertung wird vor dem Kartenwechsel bestätigt. Bei Fehler bleibt die Karte mit einem Wiederholen-Button sichtbar.
- Lernfortschritt, Status und Wiederholungsdatum in Supabase.
- Beispielmodus ohne Backend. Dieser Modus ist ausdrücklich kein Offline-Modus des eigenen Kontos.

## Statusverwaltung und Zurücksetzen

Im Modulordner startet **Gezielt wiederholen** eine Runde aus allen zugehörigen Stapeln. Karten anderer Ordner sind ausgeschlossen. Dabei werden sichere Karten stichprobenartig wiederholt. **Alle Karten dieses Moduls lernen** nimmt jede Karte des Moduls in die Runde auf, auch bereits sichere. **Modulübergreifend lernen** auf der Startseite ist bewusst separat beschriftet.

Im Stapel öffnet **Auswählen** den Auswahlmodus. Einzelne Karten antippen, **Alle auswählen** oder **Alle abwählen** nutzen, danach unten **Sicher** oder **Unsicher** wählen. Ohne Auswahl sind die Aktionen deaktiviert. Für eine einzelne Karte gehen auch die Wischaktionen rechtswärts oder das Kontextmenü per langem Drücken. Der aktuelle Status wird zusätzlich als Text angezeigt.

Manuelles Markieren ist ein absoluter Statuswechsel: sicher setzt die Wiederholungsserie auf 1 und das Datum auf morgen, unsicher setzt die Serie auf 0 und das Datum auf zehn Minuten. Wiederholtes manuelles Markieren zählt keine weiteren Lernerfolge. Änderungen werden erst nach Serverbestätigung lokal angezeigt. Eine ungültige Auswahl wird vollständig abgelehnt.

**Stapel-Aktionen → Stapel zurücksetzen** setzt nach Bestätigung alle Karten dieses Stapels auf neu, Serie 0 und sofort fällig. Karteninhalte, andere Stapel und gespeicherte historische Bewertungsereignisse bleiben erhalten; letztere beeinflussen die neu gesetzte Serie nicht.

Für Statusänderungen und den Reset muss die [Migration für Kartenfortschritt](supabase/migrations/202611170002_bulk_card_progress.sql) im eigenen Supabase-Projekt angewendet sein.

## Lernlogik

Alle neuen und unsicheren Karten werden gemischt. Dazu kommt eine Stichprobe sicherer Karten von etwa 15 % der Zahl der neuen/unsicheren Karten (mindestens eine, sofern vorhanden). Am frühesten fällige sichere Karten werden zuerst ausgewählt und etwa nach jeweils fünf anderen Karten eingestreut. Besteht ein Stapel ausschließlich aus sicheren Karten, erscheinen bis zu 20 fällige Karten bzw. eine Kontrollkarte, wenn noch keine fällig ist.

Eine als unsicher bewertete Karte wird innerhalb einer Runde maximal einmal wiederholt, sofern noch mindestens drei andere Karten dazwischen liegen können. Dadurch endet jede Runde. Unsichere Karten am Rundenende bleiben für die nächste Runde priorisiert.

Sicher setzt das nächste Wiederholungsdatum auf 1, 2, 4, 8, 16 und danach 30 Tage; unsicher setzt die Erfolgsserie zurück und das Datum auf zehn Minuten. Neue und unsichere Karten dürfen unabhängig vom Datum in jeder bewusst gestarteten Runde vorkommen. Das ist eine einfache Prototyp-Regel, kein vollständiger FSRS-/SM-2-Algorithmus. Statistiken einer Runde zählen Bewertungen einschließlich Wiederholungen, nicht nur unterschiedliche Karten.

## Importformat

In der Importansicht kopiert **KI-Prompt kopieren** direkt die vollständige Vorlage mit JSON-Struktur und Importgrenzen. **Import-Anleitung** erklärt den Ablauf vom angehängten Skript bis zur Datei in der iOS-Dateien-App. Dort lässt sich der Prompt auch ansehen oder teilen.

Die [Beispieldatei](Examples/lineare-algebra.json) lässt sich direkt importieren. Das [JSON-Schema](Examples/import.schema.json) beschreibt die Felder. Eine Datei erzeugt einen Modulordner mit Kapitelstapeln.

```json
{
  "version": 1,
  "folder": "Mein Modul",
  "decks": [
    {
      "title": "01 · Grundlagen",
      "cards": [
        { "question": "Eine konkrete Frage?", "answer": "Eine präzise Antwort." }
      ]
    }
  ]
}
```

Nur Text, keine HTML-/Markdown-/LaTeX-Darstellung. Zeilenumbrüche werden als `\n` kodiert; Unicode-Zeichen sind möglich. Grenzen: 5 MB, 1–100 Stapel, insgesamt höchstens 2.000 Karten, Ordnername 120, Stapeltitel 200, Frage 10.000 und Antwort 20.000 Zeichen. Alle Felder müssen gefüllt sein.

Jeder bewusst gestartete Import legt einen neuen Ordner an, auch bei gleichem Namen. Ein erneuter Versuch nach einem Netzwerkfehler innerhalb derselben Importansicht verwendet dieselbe Importkennung und erzeugt keine Duplikate. Ein fehlgeschlagener Import hinterlässt keine Teilimporte. Bei erneuter Dateiauswahl oder Schließen und erneutem Öffnen beginnt ein neuer Import.

### Prompt für die externe KI

> Erstelle aus dem beigefügten Kursskript Lernkarten zur Klausurvorbereitung. Nutze eine beigefügte Musterklausur zur Orientierung an Aufgabentypen, ohne den restlichen Skriptstoff zu ignorieren. Ordne die Karten den Lektionen/Kapiteln zu. Pro Karte eine klar beantwortbare Frage; formuliere Antworten verständlich und korrekt. Nimm neben Definitionen auch Verständnisfragen, Abgrenzungen und kurze Anwendungsbeispiele auf. Erfinde keine Aussagen, die du nicht aus dem Material ableiten kannst. Gib ausschließlich eine gültige UTF-8-JSON-Datei zurück, ohne Markdown-Codeblock. Verwende das Schema {"version":1,"folder":"Modulname","decks":[{"title":"01 · Kapitelname","cards":[{"question":"Frage","answer":"Antwort"}]}]}. Nur einfacher Text, keine LaTeX-/HTML-Formatierung. Maximal 2.000 Karten, maximal 100 Stapel. Kodierte Zeilenumbrüche als \n verwenden.

Die KI-Erstellung findet außerhalb der App statt. In der App werden keine Skripte hochgeladen und keine KI-APIs aufgerufen. Prüfe fachliche Inhalte vor dem Lernen.

## Prüfen

```sh
swift test
xcodebuild -project StudyApp.xcodeproj -scheme StudyApp -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/study-app-build \
  CODE_SIGNING_ALLOWED=NO build
```

`Tests/StudyCoreTests.swift` prüft Importgrenzen, ungültige Dateien, Stichproben sicherer Karten, Wiederholungsabstand, das Ende von Lernrunden, Modultrennung, ausgewählte Statusänderungen und Stapel-Reset. `supabase/tests.sql` enthält zusätzliche Transaktionstests für den SQL Editor nach der Migration; alle Testdaten werden zurückgerollt.

### Manuelle End-to-End-Prüfung nach dem Verbinden

1. Registrieren → Bestätigung → Login → App-Neustart → weiterhin angemeldet.
2. Beispiel-JSON importieren → ein Ordner, zwei Stapel, vier Karten.
3. Ordner und Stapel erstellen/umbenennen; Stapel verschieben, Karte erstellen/bearbeiten/verschieben.
4. Antwort aufdecken → links/rechts und Buttons testen → neue Runde öffnen → Status erhalten.
5. Netzwerk trennen: Laden/Bewerten zeigt Fehler; eine ungespeicherte Bewertung darf nicht weiterschalten. Netzwerk wiederherstellen und erneut speichern.
6. Mit Konto B anmelden: Keine Ordner, Karten oder Fortschritte von Konto A sichtbar.
7. Löschbestätigung abbrechen, dann bestätigen; kontrollieren, dass nur der gewählte Inhalt entfernt wird.

## Bewusste Grenzen

Kein Offline-Modus, keine KI-Generierung in der App, kein Passwort-zurücksetzen-Flow, keine Accountlöschung in der App und keine App-Store-Veröffentlichung. Vor einer Veröffentlichung sind insbesondere Accountlöschung, Datenschutzinformationen, App-Icon und ein vollständiger Test auf einem echten Gerät nachzurüsten. Karten liegen während der Nutzung im Arbeitsspeicher, nicht dauerhaft auf dem Gerät. Aktuell werden alle eigenen Karten paginiert geladen; für große Sammlungen sollte später stapelweise geladen werden.
