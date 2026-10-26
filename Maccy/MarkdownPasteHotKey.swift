import AppKit
import Defaults
import KeyboardShortcuts

// Global hotkey that pastes Markdown from the clipboard as rich text.
// The hotkey is only registered while one of the apps listed in
// `Defaults[.markdownApps]` is frontmost, so it doesn't shadow the
// same shortcut in other apps. The original clipboard contents are
// restored after the paste.
@MainActor
final class MarkdownPasteHotKey {
  static func isEnabled(for bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else {
      return false
    }

    return Defaults[.markdownApps].contains(bundleIdentifier)
  }

  private let restoreDelay: Duration
  private var isPasting = false
  private var activationObserver: NSObjectProtocol?
  private var markdownAppsObserver: Task<Void, Never>?

  init(restoreDelay: Duration = .milliseconds(500)) {
    self.restoreDelay = restoreDelay

    KeyboardShortcuts.onKeyDown(for: .pasteMarkdown) { [weak self] in
      Task { @MainActor in
        await self?.pasteMarkdown()
      }
    }

    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let bundleIdentifier = app?.bundleIdentifier
      MainActor.assumeIsolated {
        self?.updateRegistration(for: bundleIdentifier)
      }
    }

    markdownAppsObserver = Task { @MainActor [weak self] in
      for await _ in Defaults.updates(.markdownApps, initial: false) {
        self?.updateRegistration(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
      }
    }

    updateRegistration(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
  }

  func updateRegistration(for bundleIdentifier: String?) {
    if Self.isEnabled(for: bundleIdentifier) {
      KeyboardShortcuts.enable(.pasteMarkdown)
    } else {
      KeyboardShortcuts.disable(.pasteMarkdown)
    }
  }

  func pasteMarkdown() async {
    // Ignore repeated triggers while a paste/restore cycle is in flight
    // so snapshots don't stack up.
    guard !isPasting else {
      return
    }

    isPasting = true
    defer { isPasting = false }

    let clipboard = Clipboard.shared
    let snapshot = clipboard.snapshot()
    guard clipboard.convertMarkdownInPlace(recordInHistory: false) else {
      clipboard.paste()
      return
    }

    let changeCountAfterConversion = NSPasteboard.general.changeCount
    clipboard.paste()

    try? await Task.sleep(for: restoreDelay)

    // Don't clobber something the user copied during the delay.
    guard NSPasteboard.general.changeCount == changeCountAfterConversion else {
      return
    }

    clipboard.restore(snapshot)
  }
}
