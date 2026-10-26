import AppKit
import Testing
@testable import Maccy

@Suite
struct MarkdownConverterTests {
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
  func detectsMarkdown(_ text: String) {
    #expect(MarkdownConverter.looksLikeMarkdown(text))
  }

  @Test(arguments: ["Hallo Welt", "Preis: 5 * 3 = 15", "Ticket #123 ist erledigt", "a_b_c", "", "   "])
  func rejectsPlainText(_ text: String) {
    #expect(!MarkdownConverter.looksLikeMarkdown(text))
  }

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
}
