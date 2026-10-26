# Markdown → Rich Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maccy-Fork bekommt einen app-gebundenen Hotkey (`⌘⇧V`), der Markdown aus der Zwischenablage als HTML/RTF einfügt und danach das Original wiederherstellt, plus einen Footer-Eintrag, der die Zwischenablage dauerhaft umwandelt.

**Architecture:** Reine Umwandlungslogik in `MarkdownConverter` (swift-markdown → HTML-Visitor, HTML → RTF via `NSAttributedString`). `Clipboard` bekommt Snapshot/Restore und zwei neue Aktionen. Ein neuer `MarkdownPasteHotKey` registriert den Shortcut und schaltet ihn per `NSWorkspace.didActivateApplicationNotification` nur für gelistete Apps ein. Settings-Pane „Markdown“ für Hotkey + App-Liste.

**Tech Stack:** Swift 6 / SwiftUI, macOS 14+, `apple/swift-markdown` (neu, SPM), `KeyboardShortcuts`, `Defaults`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-26-markdown-to-rich-text-design.md`

## Global Constraints

- Deployment Target bleibt `MACOSX_DEPLOYMENT_TARGET = 14.0`.
- Einzige neue Abhängigkeit: `https://github.com/swiftlang/swift-markdown` (Produkt `Markdown`), Version „Up to Next Major“ ab aktuellem Release.
- Code-Stil: 2 Spaces, SwiftLint-Regeln des Repos (`.swiftlint.yml`), keine neuen Warnungen.
- Bundle-ID bleibt `org.p0deje.Maccy` (Fork ersetzt die installierte App).
- Default-App-Liste: `["com.microsoft.teams2"]`. Default-Hotkey: `⌘⇧V`.
- HTML-Ausgabe: Fragment mit Inline-Styles, kein `<style>`-Block, beginnt mit `<meta charset="utf-8">`.
- Pasteboard nach Umwandlung: `.html`, `.rtf` und `.string` (= unverändertes Markdown).
- Neue UI-Strings in `en.lproj` und `de.lproj`.
- Mermaid ist kein Ziel: ` ```mermaid ` wird wie jeder Codeblock gerendert.

## Build- und Test-Befehle

Xcode liegt unter `/Applications/Xcode.app`, aktiv ist aber nur die CLT. Alle Befehle mit:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

- Build: `xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY=- build`
- Einzelne Tests: `xcodebuild -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' CODE_SIGN_IDENTITY=- test -only-testing:MaccyTests/<Suite>`
- Lint: `swiftlint` (falls installiert, sonst überspringen und notieren).

**Neue Dateien ins Projekt aufnehmen:** Das Projekt nutzt keine synchronisierten Ordner. Jede neue `.swift`-Datei braucht in `Maccy.xcodeproj/project.pbxproj` vier Einträge, analog zu einer Nachbardatei derselben Gruppe (z. B. `Clipboard.swift` für `Maccy/`, `ClipboardTests.swift` für `MaccyTests/`): `PBXBuildFile`, `PBXFileReference`, Kind in der `PBXGroup`, Eintrag in der `PBXSourcesBuildPhase` des richtigen Targets. IDs: 24-stellige Hex-Strings, eindeutig im File. Danach Build als Prüfung.

## Review Focus

1. **Text mit einzelnen Sternchen/Rauten, der kein Markdown ist** (z. B. `Preis: 5 * 3`, `Ticket #123`) → muss als „kein Markdown“ gelten und unverändert eingefügt werden.
2. **Wiederherstellen nach dem Einfügen**, wenn das Original mehrere Typen hatte (z. B. HTML + String aus dem Browser, oder ein Bild) → exakt dieselben Typen und Daten wie vorher, kein Historie-Eintrag.
3. **Hotkey in App außerhalb der Liste** → Shortcut ist deregistriert; `⌘⇧V` erreicht die App.
4. **Umlaute, Emoji und `<`/`&` im Markdown** → korrekt escaped und UTF-8 in HTML/RTF (`Größe <10 & mehr 🎉`).
5. **Menü-Umwandlung bei abgeschaltetem HTML/RTF in den Storage-Einstellungen** → Historie-Eintrag enthält trotzdem `.html` und `.rtf`.

---

### Task 0: Baseline

**Files:** keine

- [ ] **Step 1:** Prüfen, dass die Xcode-Lizenz akzeptiert ist (`xcodebuild -list` ohne Lizenzfehler). Falls nicht: stoppen und den Nutzer bitten, `sudo xcodebuild -license` auszuführen.
- [ ] **Step 2:** Build-Befehl ausführen. Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 3:** `-only-testing:MaccyTests` ausführen. Expected: `** TEST SUCCEEDED **` (Ausgangsstand notieren, falls einzelne Tests schon upstream fehlschlagen).

### Task 1: swift-markdown + MarkdownConverter (HTML)

**Files:**
- Modify: `Maccy.xcodeproj/project.pbxproj` (Package-Referenz analog `SwiftHEXColors`: `XCRemoteSwiftPackageReference`, `XCSwiftPackageProductDependency` `Markdown`, `PBXBuildFile` in Frameworks-Phase des Targets `Maccy`, `packageReferences` im Projekt; neue Dateien)
- Modify: `Maccy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (entsteht beim Resolve)
- Create: `Maccy/MarkdownConverter.swift`
- Test: `MaccyTests/MarkdownConverterTests.swift`

**Interfaces:**
- Produces:
  - `enum MarkdownConverter`
  - `static func looksLikeMarkdown(_ text: String) -> Bool`
  - `static func html(from markdown: String) -> String`

- [ ] **Step 1: Failing tests** in `MarkdownConverterTests` (`@Suite struct MarkdownConverterTests`, kein Shared State):

```swift
@Test func headings() {
  #expect(MarkdownConverter.html(from: "# Titel").contains("<h1"))
  #expect(MarkdownConverter.html(from: "### Drei").contains("<h3"))
}
@Test func inline() {
  let html = MarkdownConverter.html(from: "**fett** *kursiv* ~~weg~~ `code` [Link](https://example.com)")
  #expect(html.contains("<strong>fett</strong>"))
  #expect(html.contains("<em>kursiv</em>"))
  #expect(html.contains("<s>weg</s>") || html.contains("<del>weg</del>"))
  #expect(html.contains("<code") && html.contains(">code</code>"))
  #expect(html.contains("<a href=\"https://example.com\">Link</a>"))
}
@Test func nestedLists() {
  let html = MarkdownConverter.html(from: "- a\n  - b\n1. eins\n2. zwei")
  #expect(html.components(separatedBy: "<ul").count - 1 == 2)
  #expect(html.contains("<ol"))
}
@Test func taskList() {
  let html = MarkdownConverter.html(from: "- [ ] offen\n- [x] erledigt")
  #expect(html.contains("☐ offen"))
  #expect(html.contains("☑ erledigt"))
}
@Test func codeBlockKeepsContentEscaped() {
  let html = MarkdownConverter.html(from: "```swift\nlet a = 1 < 2\n```")
  #expect(html.contains("<pre"))
  #expect(html.contains("let a = 1 &lt; 2"))
}
@Test func mermaidIsPlainCodeBlock() {
  #expect(MarkdownConverter.html(from: "```mermaid\ngraph TD; A-->B\n```").contains("<pre"))
}
@Test func table() {
  let html = MarkdownConverter.html(from: "| A | B |\n|---|---|\n| 1 | 2 |")
  #expect(html.contains("<table") && html.contains("<th") && html.contains("<td"))
}
@Test func quoteRuleBreak() {
  let html = MarkdownConverter.html(from: "> Zitat\n\n---\n\nZeile 1  \nZeile 2")
  #expect(html.contains("<blockquote"))
  #expect(html.contains("<hr"))
  #expect(html.contains("<br"))
}
@Test func escapingAndUnicode() {
  let html = MarkdownConverter.html(from: "Größe <10 & mehr 🎉")
  #expect(html.hasPrefix("<meta charset=\"utf-8\">"))
  #expect(html.contains("Größe &lt;10 &amp; mehr 🎉"))
  #expect(!html.contains("<style"))
}
@Test(arguments: ["# Titel", "- Punkt", "1. Eins", "**fett**", "`x`", "[a](b)", "> q", "```\nx\n```", "| a |\n|---|\n| 1 |"])
func detectsMarkdown(_ text: String) { #expect(MarkdownConverter.looksLikeMarkdown(text)) }
@Test(arguments: ["Hallo Welt", "Preis: 5 * 3 = 15", "Ticket #123 ist erledigt", "a_b_c", "", "   "])
func rejectsPlainText(_ text: String) { #expect(!MarkdownConverter.looksLikeMarkdown(text)) }
```

- [ ] **Step 2:** Tests laufen lassen (`-only-testing:MaccyTests/MarkdownConverterTests`). Expected: Build-Fehler „cannot find 'MarkdownConverter'“.
- [ ] **Step 3:** Package hinzufügen, `MarkdownConverter` implementieren. Parsing via `Document(parsing:)`; HTML über eigenen `MarkupVisitor` (nicht `HTMLFormatter`, weil Inline-Styles und Task-Listen-Glyphen nötig sind). Inline-Styles minimal: `pre`/`code` mit `font-family: Menlo, monospace`, `pre` mit hellgrauem Hintergrund, `table`/`td`/`th` mit `border: 1px solid #ccc; padding: 4px 8px; border-collapse: collapse`, `blockquote` mit linkem Rand. `looksLikeMarkdown`: parsen und `true`, wenn das Dokument mindestens ein Nicht-`Paragraph`-Blockelement oder ein `Strong`/`Emphasis`/`InlineCode`/`Link`/`Strikethrough` enthält.
- [ ] **Step 4:** Tests laufen lassen. Expected: alle grün.
- [ ] **Step 5: Commit** — `feat: add markdown to html converter`

### Task 2: RTF-Erzeugung und Pasteboard-Inhalte

**Files:**
- Modify: `Maccy/MarkdownConverter.swift`
- Modify: `Maccy/Extensions/NSPasteboard.PasteboardType+Types.swift`
- Test: `MaccyTests/MarkdownConverterTests.swift`

**Interfaces:**
- Consumes: `MarkdownConverter.html(from:)`
- Produces:
  - `struct RichTextContents { let html: Data; let rtf: Data; let markdown: String }`
  - `@MainActor static func richText(from markdown: String) -> RichTextContents?` (nil, wenn `!looksLikeMarkdown`)
  - `NSPasteboard.PasteboardType.convertedFromMarkdown` = `"org.p0deje.Maccy.markdown-converted"`

- [ ] **Step 1: Failing tests:**

```swift
@MainActor @Test func richTextRoundTrip() throws {
  let contents = try #require(MarkdownConverter.richText(from: "# Größe\n\n**fett** 🎉"))
  let attributed = try #require(NSAttributedString(rtf: contents.rtf, documentAttributes: nil))
  #expect(attributed.string.contains("Größe"))
  #expect(attributed.string.contains("fett"))
  #expect(!attributed.string.contains("**"))
  #expect(String(data: contents.html, encoding: .utf8)?.contains("<h1") == true)
  #expect(contents.markdown == "# Größe\n\n**fett** 🎉")
}
@MainActor @Test func richTextNilForPlainText() {
  #expect(MarkdownConverter.richText(from: "Hallo Welt") == nil)
}
```

- [ ] **Step 2:** Tests laufen lassen. Expected: FAIL (Symbol fehlt).
- [ ] **Step 3:** Implementieren: HTML als UTF-8-`Data`; RTF via `NSAttributedString(html:documentAttributes:)` → `rtf(from:documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])`. Marker-Typ in der Extension ergänzen.
- [ ] **Step 4:** Tests laufen lassen. Expected: grün.
- [ ] **Step 5: Commit** — `feat: generate rtf and pasteboard contents from markdown`

### Task 3: Snapshot/Restore und Menü-Umwandlung im Clipboard

**Files:**
- Modify: `Maccy/Clipboard.swift`
- Test: `MaccyTests/ClipboardTests.swift`

**Interfaces:**
- Consumes: `MarkdownConverter.richText(from:)`, `.convertedFromMarkdown`
- Produces (alle `@MainActor` auf `Clipboard`):
  - `typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]` (ein Dictionary pro Pasteboard-Item)
  - `func snapshot() -> Snapshot`
  - `func restore(_ snapshot: Snapshot)` — schreibt zurück und setzt danach `changeCount = pasteboard.changeCount` (kein Historie-Eintrag)
  - `var canConvertMarkdown: Bool` — `.string` vorhanden und `looksLikeMarkdown`
  - `@discardableResult func convertMarkdownInPlace(recordInHistory: Bool) -> Bool` — schreibt `.html`, `.rtf`, `.string` (+ `.convertedFromMarkdown` wenn `recordInHistory`), ersetzt vorhandenes HTML/RTF; bei `recordInHistory == false` danach `changeCount` synchronisieren. Rückgabe `false`, wenn nichts umgewandelt wurde.
- `checkForChangesInPasteboard()`: Enthält ein Item `.convertedFromMarkdown`, werden `.html` und `.rtf` gespeichert, auch wenn sie in `disabledTypes` stehen; der Marker selbst wird nicht gespeichert.

- [ ] **Step 1: Failing tests** in `ClipboardTests` (Muster `waitForCopies` nutzen):

```swift
@Test("Snapshot and restore keep all types without new copy")
func snapshotRestore() async throws {
  pasteboard.clearContents()
  pasteboard.setString("<b>x</b>", forType: .html)
  pasteboard.setString("x", forType: .string)
  clipboard.checkForChangesInPasteboard()
  let snap = clipboard.snapshot()
  pasteboard.clearContents(); pasteboard.setString("other", forType: .string)
  clipboard.checkForChangesInPasteboard()
  let copies = try await waitForCopies(expectingCopy: false, after: { clipboard.restore(snap) })
  #expect(copies.isEmpty)
  #expect(pasteboard.string(forType: .html) == "<b>x</b>")
  #expect(pasteboard.string(forType: .string) == "x")
}

@Test("Convert in place records html and rtf even if disabled")
func convertInPlaceForcesRichTypes() async throws {
  Defaults[.enabledPasteboardTypes] = [.string]
  pasteboard.clearContents(); pasteboard.setString("# Titel", forType: .string)
  clipboard.checkForChangesInPasteboard()
  let copies = try await waitForCopies(after: { clipboard.convertMarkdownInPlace(recordInHistory: true) })
  let types = Set(try #require(copies.first).contents.map(\.type))
  #expect(types.isSuperset(of: [NSPasteboard.PasteboardType.html.rawValue, NSPasteboard.PasteboardType.rtf.rawValue]))
  #expect(!types.contains(NSPasteboard.PasteboardType.convertedFromMarkdown.rawValue))
}

@Test("Convert in place replaces existing html")
func convertReplacesHTML() {
  pasteboard.clearContents()
  pasteboard.setString("<span>vscode</span>", forType: .html)
  pasteboard.setString("**fett**", forType: .string)
  #expect(clipboard.convertMarkdownInPlace(recordInHistory: false))
  #expect(pasteboard.string(forType: .html)?.contains("<strong>fett</strong>") == true)
  #expect(pasteboard.string(forType: .string) == "**fett**")
}

@Test("Convert in place is a no-op for plain text")
func convertPlainText() {
  pasteboard.clearContents(); pasteboard.setString("Hallo", forType: .string)
  #expect(!clipboard.canConvertMarkdown)
  #expect(!clipboard.convertMarkdownInPlace(recordInHistory: false))
  #expect(pasteboard.string(forType: .html) == nil)
}
```

- [ ] **Step 2:** `-only-testing:MaccyTests/SharedStateTests` laufen lassen. Expected: FAIL (Symbole fehlen).
- [ ] **Step 3:** Implementieren wie in Interfaces beschrieben.
- [ ] **Step 4:** Tests laufen lassen. Expected: neue und bestehende `ClipboardTests` grün.
- [ ] **Step 5: Commit** — `feat: clipboard snapshot/restore and in-place markdown conversion`

### Task 4: Footer-Eintrag „Markdown → Rich Text“

**Files:**
- Modify: `Maccy/Observables/Footer.swift`, `Maccy/Observables/FooterItem.swift`, `Maccy/Views/FooterItemView.swift` (deaktivierter Zustand)
- Modify: `Maccy/Views/en.lproj/…` und `Maccy/Views/de.lproj/…` (dieselbe `.strings`-Datei, in der `clear`/`clear_tooltip` stehen)

**Interfaces:**
- Consumes: `Clipboard.shared.canConvertMarkdown`, `Clipboard.shared.convertMarkdownInPlace(recordInHistory: true)`
- Produces: `FooterItem.isEnabled: () -> Bool` (Default `{ true }`); Footer-Titel-Key `convert_markdown`, Tooltip-Key `convert_markdown_tooltip`

- [ ] **Step 1:** `FooterItem` um `isEnabled` erweitern, `FooterItemView` deaktiviert Button/Auswahl bei `false` (ausgegraut, Aktion ignoriert).
- [ ] **Step 2:** In `Footer.init` vor `preferences` einfügen: `FooterItem(title: "convert_markdown", help: "convert_markdown_tooltip", isEnabled: { Clipboard.shared.canConvertMarkdown }) { Task { @MainActor in Clipboard.shared.convertMarkdownInPlace(recordInHistory: true) } }`. Kein Tastenkürzel.
- [ ] **Step 3:** Strings: en `"Markdown → Rich Text"` / `"Convert Markdown on the clipboard to formatted text"`; de `"Markdown → Rich Text"` / `"Markdown in der Zwischenablage in formatierten Text umwandeln"`.
- [ ] **Step 4:** Build. Expected: `** BUILD SUCCEEDED **`; bestehende `MaccyTests` grün.
- [ ] **Step 5: Commit** — `feat: add markdown conversion footer item`

### Task 5: App-gebundener Hotkey „Markdown formatiert einfügen“

**Files:**
- Modify: `Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift`
- Modify: `Maccy/Extensions/Defaults.Keys+Names.swift`
- Create: `Maccy/MarkdownPasteHotKey.swift`
- Modify: `Maccy/AppDelegate.swift` (Instanz in `applicationDidFinishLaunching` erzeugen und halten)
- Test: `MaccyTests/MarkdownPasteHotKeyTests.swift`

**Interfaces:**
- Consumes: `Clipboard.snapshot()`, `restore(_:)`, `convertMarkdownInPlace(recordInHistory: false)`, `paste()`
- Produces:
  - `KeyboardShortcuts.Name.pasteMarkdown` = `Self("pasteMarkdown", initial: Shortcut(.v, modifiers: [.command, .shift]))`
  - `Defaults.Keys.markdownApps = Key<[String]>("markdownApps", default: ["com.microsoft.teams2"], suite: preferencesSuite)`
  - `@MainActor final class MarkdownPasteHotKey` mit `init(restoreDelay: Duration = .milliseconds(500))`, `static func isEnabled(for bundleIdentifier: String?) -> Bool`, `func updateRegistration(for bundleIdentifier: String?)`, `func pasteMarkdown() async`

- [ ] **Step 1: Failing tests:**

```swift
@Suite(.serialized) @MainActor struct MarkdownPasteHotKeyTests {
  @Test func enabledOnlyForListedApps() {
    let saved = Defaults[.markdownApps]; defer { Defaults[.markdownApps] = saved }
    Defaults[.markdownApps] = ["com.microsoft.teams2"]
    #expect(MarkdownPasteHotKey.isEnabled(for: "com.microsoft.teams2"))
    #expect(!MarkdownPasteHotKey.isEnabled(for: "com.google.Chrome"))
    #expect(!MarkdownPasteHotKey.isEnabled(for: nil))
  }
}
```

- [ ] **Step 2:** Test laufen lassen. Expected: FAIL (Symbol fehlt).
- [ ] **Step 3:** Implementieren. `init`: `KeyboardShortcuts.onKeyDown(for: .pasteMarkdown) { Task { await self.pasteMarkdown() } }`, Observer auf `NSWorkspace.shared.notificationCenter` für `didActivateApplicationNotification` → `updateRegistration(for:)` mit Bundle-ID der aktivierten App; initial mit `frontmostApplication`. Außerdem auf `Defaults.updates(.markdownApps)` reagieren. `updateRegistration`: `KeyboardShortcuts.enable/disable(.pasteMarkdown)`. `pasteMarkdown`: `snapshot()` → `convertMarkdownInPlace(recordInHistory: false)` → `paste()` → falls umgewandelt: `try? await Task.sleep(for: restoreDelay)` und `restore(snapshot)`. Kein Markdown → nur `paste()`. **Achtung:** `Popup` deaktiviert/aktiviert `.popup` selbst; `.pasteMarkdown` ist davon unabhängig, nicht anfassen.
- [ ] **Step 4:** Test laufen lassen. Expected: grün.
- [ ] **Step 5: Commit** — `feat: add app-scoped markdown paste hotkey`

### Task 6: Settings-Pane „Markdown“

**Files:**
- Create: `Maccy/Settings/MarkdownSettingsPane.swift`
- Modify: `Maccy/Extensions/Settings.PaneIdentifier+Panes.swift` (`static let markdown = Self("markdown")`)
- Modify: `Maccy/Observables/AppState.swift` (Pane zwischen `ignore` und `advanced`, Icon `NSImage(systemSymbolName: "text.badge.checkmark", …)` — bestehendes Muster in `NSImage+Names.swift` nutzen)
- Create: `Maccy/Settings/en.lproj/MarkdownSettings.strings`, `Maccy/Settings/de.lproj/MarkdownSettings.strings` (Muster der anderen Pane-Strings übernehmen)

- [ ] **Step 1:** Pane bauen: `KeyboardShortcuts.Recorder(for: .pasteMarkdown)` mit Label „Formatiert einfügen“ / „Paste as rich text“; darunter App-Liste für `Defaults[.markdownApps]` mit Hinzufügen (NSOpenPanel auf `/Applications`, Bundle-ID auslesen) und Entfernen — Aufbau 1:1 nach `IgnoreApplicationsSettingsView`; Hinweistext „Der Kurzbefehl ist nur aktiv, solange eine dieser Apps im Vordergrund ist.“ / „The shortcut is only active while one of these apps is frontmost.“
- [ ] **Step 2:** Build. Expected: `** BUILD SUCCEEDED **`. App starten, Einstellungen öffnen: Pane sichtbar, Teams in Liste, Hotkey-Recorder zeigt `⌘⇧V`.
- [ ] **Step 3: Commit** — `feat: add markdown settings pane`

### Task 7: Updates abschalten, Install-Skript, End-to-End-Test

**Files:**
- Modify: `Maccy/Info.plist` (`SUFeedURL` entfernen, `SUEnableAutomaticChecks` = `false`)
- Modify: `Maccy/Settings/GeneralSettingsPane.swift` (Update-Toggle/„Check for updates“ ausblenden)
- Create: `scripts/install-local.sh` (ausführbar)
- Modify: `README.md` (kurzer Fork-Abschnitt: Feature, Installation, Bedienungshilfen neu erteilen)

- [ ] **Step 1:** Sparkle-Feed entfernen und Update-UI ausblenden; `SoftwareUpdater` bleibt im Code, wird aber nicht mehr angeboten.
- [ ] **Step 2:** `scripts/install-local.sh`: `DEVELOPER_DIR` setzen, Release-Build mit `CODE_SIGN_IDENTITY=-` nach `build/`, laufendes Maccy beenden (`osascript -e 'quit app "Maccy"'`), `/Applications/Maccy.app` durch Build ersetzen (vorher Backup nach `~/Applications/Maccy-2.7.1-backup.app`, nur beim ersten Mal), starten, Hinweis ausgeben: Bedienungshilfen-Eintrag für Maccy entfernen und neu hinzufügen.
- [ ] **Step 3:** Alle `MaccyTests` laufen lassen. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 4:** Manuelle Prüfung (mit dem Nutzer, nach Installation):
  - Markdown aus Claude kopieren → in Teams `⌘⇧V` → formatiert; danach `⌘V` in TextEdit (Plain) zeigt wieder Markdown; Maccy-Historie hat keinen neuen Eintrag.
  - `⌘⇧V` in Chrome → Chromes eigenes Verhalten.
  - Normaler Text in Teams mit `⌘⇧V` → unverändert eingefügt.
  - Footer-Eintrag bei Markdown aktiv, bei normalem Text ausgegraut; nach Klick formatiert in Outlook einfügbar.
  - Restore-Verzögerung: falls Teams manchmal das Original einfügt, `restoreDelay` erhöhen und notieren.
- [ ] **Step 5: Commit** — `chore: disable updates and add local install script`
