import Defaults
import Testing
@testable import Maccy

@Suite(.serialized)
@MainActor
struct MarkdownPasteHotKeyTests {
  @Test
  func enabledOnlyForListedApps() {
    let saved = Defaults[.markdownApps]
    defer { Defaults[.markdownApps] = saved }

    Defaults[.markdownApps] = ["com.microsoft.teams2"]
    #expect(MarkdownPasteHotKey.isEnabled(for: "com.microsoft.teams2"))
    #expect(!MarkdownPasteHotKey.isEnabled(for: "com.google.Chrome"))
    #expect(!MarkdownPasteHotKey.isEnabled(for: nil))
  }
}
