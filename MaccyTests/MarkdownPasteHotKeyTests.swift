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

  @Test
  func waitsUntilModifiersAreReleased() async {
    var polls = 0
    let released = await MarkdownPasteHotKey.waitForModifierRelease(
      timeout: .seconds(1),
      pollInterval: .milliseconds(1)
    ) {
      polls += 1
      return polls < 5
    }

    #expect(released)
    #expect(polls == 5)
  }

  @Test
  func givesUpWaitingAfterTimeout() async {
    let released = await MarkdownPasteHotKey.waitForModifierRelease(
      timeout: .milliseconds(30),
      pollInterval: .milliseconds(5)
    ) { true }

    #expect(!released)
  }
}
