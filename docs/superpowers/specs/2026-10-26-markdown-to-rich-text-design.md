# Markdown → Rich Text beim Einfügen — Design

Datum: 2026-10-26 · Fork: `dEeds83/Maccy` (Basis: upstream `54fb9f0`, Maccy 2.7.1+)

## Warum

KI-Tools (Claude, ChatGPT, …) liefern Antworten als Markdown. Kopiert man
sie und fügt in Microsoft Teams ein, kommt Rohtext an: `# Überschrift`,
`**fett**`, `- Liste`. Teams versteht beim Einfügen aber HTML — die
Formatierung (Überschriften, Fett, Listen, Einrückungen, Tabellen) soll
dort ankommen, ohne Umweg über einen Online-Konverter.

## Ziele

1. **Hotkey „Markdown formatiert einfügen“** (Standard `⌘⇧V`, in den
   Einstellungen änderbar).
   - Nur aktiv, solange eine App aus einer **App-Liste** im Vordergrund ist
     (Default-Eintrag: Microsoft Teams, Bundle-ID `com.microsoft.teams2`).
     In allen anderen Apps ist der Hotkey nicht registriert — `⌘⇧V` behält
     dort seine native Bedeutung.
   - Ablauf: aktuellen Zwischenablage-Inhalt (alle Typen) sichern →
     Markdown aus `.string` in HTML + RTF umwandeln → Zwischenablage mit
     HTML, RTF und originalem Markdown als `.string` belegen → `⌘V` posten
     (bestehendes `Clipboard.paste()`) → nach kurzer Verzögerung
     **Original-Inhalt wiederherstellen**.
   - Weder die konvertierte Version noch das Wiederherstellen erzeugen
     neue Einträge in der Maccy-Historie.
   - Enthält die Zwischenablage keinen Text, oder sieht der Text nicht nach
     Markdown aus: unverändert einfügen (normales `⌘V` posten).
2. **Menüeintrag „Markdown → Rich Text“** im Popup-Footer (neues
   `FooterItem` neben „Clear“/„Preferences“).
   - Wandelt den aktuellen Zwischenablage-Inhalt **dauerhaft** um (HTML +
     RTF + Markdown als `.string`), fügt nicht ein, stellt nichts wieder her.
   - Unabhängig von der App-Liste, funktioniert für jede Ziel-App.
   - Ergebnis landet als normaler neuer Eintrag in der Historie.
   - Kein Markdown/kein Text in der Zwischenablage → Eintrag deaktiviert.
3. **Einstellungen**: neuer Abschnitt (eigener Settings-Pane oder Abschnitt
   in „General“): Hotkey-Recorder (`KeyboardShortcuts.Recorder`) und
   App-Liste mit Hinzufügen/Entfernen — UI nach Vorbild von
   `IgnoreApplicationsSettingsView`.
4. **Unterstützte Markdown-Elemente (v1)**: Überschriften H1–H6, fett,
   kursiv, durchgestrichen, Inline-Code, Codeblöcke (inkl. Sprach-Info,
   ohne Syntax-Highlighting), ungeordnete/geordnete Listen inkl.
   Verschachtelung, Task-Listen (`- [ ]`/`- [x]` als ☐/☑), Links, Zitate,
   horizontale Linie, Tabellen (GFM), Absätze/harte Zeilenumbrüche.

## Nicht-Ziele (v1)

- **Mermaid-Diagramme** → Ausbaustufe 2. In v1 bleibt ein
  ` ```mermaid `-Block ein normaler Codeblock.
- Automatische Umwandlung bei normalem `⌘V` oder beim App-Wechsel (kein
  Hintergrund-Umschreiben der Zwischenablage, kein Event-Tap auf `⌘V`).
- Umwandlung älterer Historie-Einträge aus dem Popup heraus.
- Syntax-Highlighting in Codeblöcken, Bilder, HTML-Passthrough, Fußnoten,
  Mathe.
- Upstream-PR (kann später erfolgen, ist kein Ziel).

## Anti-Ziele (wäre ein Fehlschlag, selbst wenn es „funktioniert“)

- `⌘⇧V` wird in Apps außerhalb der Liste geschluckt.
- Nach dem Einfügen ist die Zwischenablage verändert oder leer, oder die
  Historie ist mit Zwischenständen zugemüllt.
- Normaler Text ohne Markdown wird „verschlimmbessert“ (z. B. Zeilen
  zusammengezogen, Sternchen verschwinden aus normalem Text).
- Teams zeigt HTML-Quelltext (`<h1>…`) statt Formatierung.

## Rahmenbedingungen

- Swift/SwiftUI, macOS 14+ (Deployment Target des Projekts).
- Bestehende Bausteine nutzen: `KeyboardShortcuts` (Hotkey, wie
  `.popup`), `Defaults` (Settings), `Clipboard.paste()` (synthetisches
  `⌘V`, Accessibility-Recht ist bereits vorhanden),
  `NSWorkspace.didActivateApplicationNotification` für das Ein-/Ausschalten
  des Hotkeys je nach Vordergrund-App.
- Markdown-Parsing über `apple/swift-markdown` (SPM); HTML-Erzeugung als
  eigener `MarkupVisitor`. RTF entsteht aus dem HTML via
  `NSAttributedString(html:…)` → `rtf(from:…)`.
- HTML-Fragment mit Inline-Styles, kein externes CSS (Teams ignoriert
  `<style>`-Blöcke weitgehend). UTF-8 mit `<meta charset="utf-8">`.
- Code-Stil wie im Rest des Repos (2 Spaces, SwiftLint-Regeln des Repos).
- Neue UI-Strings in `en.lproj` und `de.lproj`; andere Sprachen fallen auf
  Englisch zurück.

## Wie es gebaut wird (entschieden)

- Neuer Typ `MarkdownConverter` (reine Logik: `String` → HTML-String,
  plus Heuristik `looksLikeMarkdown(_:)`) — gut unit-testbar.
- Erweiterung in `Clipboard`: Snapshot/Restore aller Pasteboard-Items,
  „Markdown formatiert einfügen“, „Zwischenablage umwandeln“.
- Historie-Unterdrückung für den Hotkey-Pfad: nach jedem eigenen
  Schreibvorgang `changeCount` auf den aktuellen Pasteboard-Stand setzen,
  damit `checkForChangesInPasteboard()` die Änderung nicht als neue Kopie
  sieht.
- Neue `KeyboardShortcuts.Name.pasteMarkdown` mit Default `⌘⇧V`;
  `KeyboardShortcuts.enable/disable` beim App-Wechsel.
- Neuer `Defaults`-Key `markdownApps: [String]` (Bundle-IDs), Default
  `["com.microsoft.teams2"]`.

## Vom Nutzer entschieden

- **Vorhandenes HTML/RTF in der Zwischenablage:** Sieht der
  `.string`-Inhalt nach Markdown aus, wird immer daraus umgewandelt und
  vorhandenes HTML/RTF ersetzt (gilt für Hotkey und Menüeintrag). So
  funktioniert es auch mit Quellen wie VS Code, die Markdown-Quelltext als
  syntaxgefärbtes HTML ablegen.
- **Installation:** Der Fork ersetzt das installierte Maccy (`/Applications/Maccy.app`,
  2.7.1) mit **gleicher Bundle-ID** — Historie und Einstellungen bleiben.
  Maccy wird danach nicht mehr über App Store/Homebrew aktualisiert. Die
  Bedienungshilfen-Berechtigung muss nach der Installation neu erteilt
  werden.

## Entscheidungen von Claude (zur Prüfung)

- **Signatur:** Auf dem Rechner ist kein Codesigning-Zertifikat
  vorhanden → Build mit lokaler Ad-hoc-Signatur („Sign to Run Locally“).
  Folge: Nach jedem neuen Build muss die Bedienungshilfen-Berechtigung
  erneut erteilt werden (Eintrag in Systemeinstellungen entfernen und neu
  hinzufügen). Ein kleines Build-/Install-Skript (`scripts/install-local.sh`:
  bauen, alte App beenden, nach `/Applications` kopieren, starten) gehört
  zum Umfang.

- **Menüeintrag und Speicher-Typen:** Der umgewandelte Eintrag speichert
  HTML und RTF immer, auch wenn diese Typen in den Storage-Einstellungen
  abgeschaltet sind. Sonst würde ihn die Duplikat-Erkennung mit dem
  Markdown-Original zusammenlegen, und beim späteren Einfügen aus der
  Historie wäre die Formatierung weg. Umsetzung über einen eigenen
  Marker-Typ auf dem Pasteboard, den `checkForChangesInPasteboard`
  erkennt.
- **Updates:** Im Fork wird Sparkle-Auto-Update deaktiviert (`SUFeedURL`
  entfernen bzw. Update-Check abschalten). Sonst würde ein Upstream-Update
  den Fork stillschweigend ersetzen und das Feature wäre weg.

## Dem Builder überlassen

- Exakte Verzögerung bis zum Wiederherstellen (Startwert ~500 ms; durch
  Test in Teams bestätigen).
- Konkrete Heuristik für `looksLikeMarkdown` (Vorschlag: mindestens ein
  Block-Element wie Überschrift/Liste/Codeblock/Tabelle/Zitat oder
  Inline-Auszeichnung `**…**`, `` `…` ``, `[…](…)`).
- Ob die Einstellungen ein eigener Pane oder ein Abschnitt sind.
- Ob zusätzlich ein App-Intent (Kurzbefehle) entsteht — optional.

## Verifikation

- Unit-Tests für `MarkdownConverter` (jedes Element aus Ziel 4, plus
  „kein Markdown“-Fälle) in `MaccyTests` (Swift Testing).
- Unit-Test für Snapshot/Restore der Zwischenablage (mehrere Typen).
- Manueller Test in Teams: Hotkey formatiert einfügen, Zwischenablage
  danach wieder Original, keine neuen Historie-Einträge; `⌘⇧V` in einer
  App außerhalb der Liste unverändert; Menüeintrag wandelt dauerhaft um.

## Ausbaustufe 2: Mermaid (Skizze, nicht Teil von v1)

` ```mermaid `-Blöcke zu PNG rendern (z. B. versteckte `WKWebView` mit
gebündeltem mermaid.js) und als Bild einbetten. Offene Frage: Nimmt Teams
`<img src="data:image/png;base64,…">` aus eingefügtem HTML an? Falls nein:
Bild separat als `.png` auf das Pasteboard — Machbarkeit vorab prüfen.
