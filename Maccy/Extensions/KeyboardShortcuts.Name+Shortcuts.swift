import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", initial: Shortcut(.c, modifiers: [.command, .shift]))
  static let pin = Self("pin", initial: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", initial: Shortcut(.delete, modifiers: [.option]))
  static let pasteMarkdown = Self("pasteMarkdown", initial: Shortcut(.v, modifiers: [.command, .shift]))
  static let togglePreview = Self("togglePreview", initial: Shortcut(.space, modifiers: [.control]))
}
