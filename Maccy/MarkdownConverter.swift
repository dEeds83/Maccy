import AppKit
import Markdown

nonisolated struct RichTextContents {
  let html: Data
  let rtf: Data
  let markdown: String
}

nonisolated enum MarkdownConverter {
  static func looksLikeMarkdown(_ text: String) -> Bool {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }

    return containsFormatting(parse(text))
  }

  static func html(from markdown: String) -> String {
    var converter = HTMLConverter()
    return "<meta charset=\"utf-8\">" + converter.visit(parse(markdown))
  }

  // Smart punctuation would turn `--`, `...` and straight quotes into typographic
  // characters, altering what the user copied.
  private static func parse(_ text: String) -> Document {
    return Document(parsing: text, options: .disableSmartOpts)
  }

  // NSAttributedString's HTML importer requires the main thread.
  @MainActor
  static func richText(from markdown: String) -> RichTextContents? {
    guard looksLikeMarkdown(markdown) else {
      return nil
    }

    guard let html = html(from: markdown).data(using: .utf8),
          let attributed = NSAttributedString(html: html, documentAttributes: nil),
          let rtf = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
          ) else {
      return nil
    }

    return RichTextContents(html: html, rtf: rtf, markdown: markdown)
  }

  private static func containsFormatting(_ markup: Markup) -> Bool {
    for child in markup.children {
      switch child {
      case is Paragraph, is Text, is SoftBreak, is LineBreak:
        break
      // Raw HTML/XML on its own is not Markdown and must not be converted.
      case is HTMLBlock, is InlineHTML:
        continue
      case is Strong, is Emphasis, is InlineCode, is Link, is Strikethrough:
        return true
      case is BlockMarkup:
        return true
      default:
        break
      }
      if containsFormatting(child) {
        return true
      }
    }
    return false
  }
}

private nonisolated struct HTMLConverter: MarkupVisitor {
  typealias Result = String

  private static let codeFont = "font-family: Menlo, monospace;"
  private static let cellStyle = "border: 1px solid #ccc; padding: 4px 8px; border-collapse: collapse;"

  mutating func defaultVisit(_ markup: Markup) -> String {
    return children(of: markup)
  }

  mutating func visitDocument(_ document: Document) -> String {
    return children(of: document)
  }

  mutating func visitHeading(_ heading: Heading) -> String {
    let level = min(max(heading.level, 1), 6)
    return "<h\(level)>\(children(of: heading))</h\(level)>"
  }

  mutating func visitParagraph(_ paragraph: Paragraph) -> String {
    return "<p>\(children(of: paragraph))</p>"
  }

  mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
    let style = "border-left: 3px solid #ccc; margin: 0; padding-left: 12px; color: #555;"
    return "<blockquote style=\"\(style)\">\(children(of: blockQuote))</blockquote>"
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
    return preformatted(codeBlock.code)
  }

  mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
    return "<hr>"
  }

  mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
    return preformatted(html.rawHTML)
  }

  mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
    return "<ul>\(children(of: unorderedList))</ul>"
  }

  mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
    let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
    return "<ol\(start)>\(children(of: orderedList))</ol>"
  }

  mutating func visitListItem(_ listItem: ListItem) -> String {
    var prefix = ""
    if let checkbox = listItem.checkbox {
      prefix = checkbox == .checked ? "☑ " : "☐ "
    }

    // Tight items (a single paragraph, optionally followed by a nested list) are
    // unwrapped so they render compactly; loose items keep their <p> wrappers.
    let paragraphCount = listItem.children.filter { $0 is Paragraph }.count
    var content = ""
    for child in listItem.children {
      if paragraphCount == 1, let paragraph = child as? Paragraph {
        content += children(of: paragraph)
      } else {
        content += visit(child)
      }
    }
    return "<li>\(prefix)\(content)</li>"
  }

  mutating func visitTable(_ table: Table) -> String {
    let style = "border: 1px solid #ccc; border-collapse: collapse;"
    var rows = "<thead>\(visit(table.head))</thead>"
    if !table.body.isEmpty {
      rows += "<tbody>\(visit(table.body))</tbody>"
    }
    return "<table style=\"\(style)\">\(rows)</table>"
  }

  mutating func visitTableHead(_ tableHead: Table.Head) -> String {
    return "<tr>\(cells(of: tableHead, tag: "th"))</tr>"
  }

  mutating func visitTableBody(_ tableBody: Table.Body) -> String {
    return children(of: tableBody)
  }

  mutating func visitTableRow(_ tableRow: Table.Row) -> String {
    return "<tr>\(cells(of: tableRow, tag: "td"))</tr>"
  }

  mutating func visitText(_ text: Text) -> String {
    return escape(text.string)
  }

  mutating func visitStrong(_ strong: Strong) -> String {
    return "<strong>\(children(of: strong))</strong>"
  }

  mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
    return "<em>\(children(of: emphasis))</em>"
  }

  mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
    return "<s>\(children(of: strikethrough))</s>"
  }

  mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
    let style = "\(Self.codeFont) background-color: #f6f8fa;"
    return "<code style=\"\(style)\">\(escape(inlineCode.code))</code>"
  }

  mutating func visitLink(_ link: Link) -> String {
    guard let destination = link.destination, Self.isSafeURL(destination) else {
      return children(of: link)
    }
    return "<a href=\"\(escape(destination))\">\(children(of: link))</a>"
  }

  // Rendered as a link: an <img> would make NSAttributedString's HTML importer
  // fetch the resource synchronously on the main thread.
  mutating func visitImage(_ image: Image) -> String {
    let alt = escape(image.plainText)
    guard let source = image.source, Self.isSafeURL(source) else {
      return alt
    }
    return "<a href=\"\(escape(source))\">\(alt.isEmpty ? escape(source) : alt)</a>"
  }

  mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
    return escape(inlineHTML.rawHTML)
  }

  // Chat-style line breaks (like GitHub comments and Teams): a single newline
  // stays a newline instead of being collapsed into a space.
  mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
    return "<br>"
  }

  mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
    return "<br>"
  }

  private static let safeSchemes: Set<String> = ["http", "https", "mailto"]

  private static func isSafeURL(_ destination: String) -> Bool {
    guard let colon = destination.firstIndex(of: ":") else {
      return false
    }
    return safeSchemes.contains(destination[..<colon].lowercased())
  }

  private func preformatted(_ text: String) -> String {
    var code = text
    if code.hasSuffix("\n") {
      code.removeLast()
    }
    let preStyle = "\(Self.codeFont) background-color: #f6f8fa; padding: 8px; white-space: pre-wrap;"
    return "<pre style=\"\(preStyle)\"><code style=\"\(Self.codeFont)\">\(escape(code))</code></pre>"
  }

  private mutating func children(of markup: Markup) -> String {
    return markup.children.map { visit($0) }.joined()
  }

  private mutating func cells(of markup: Markup, tag: String) -> String {
    return markup.children.compactMap { $0 as? Table.Cell }.map { cell in
      "<\(tag) style=\"\(Self.cellStyle)\">\(children(of: cell))</\(tag)>"
    }.joined()
  }

  private func escape(_ text: String) -> String {
    return text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
