import AppKit

// AppKit lifecycle rather than a SwiftUI App scene: SafeClip is an
// LSUIElement agent whose three surfaces (status item, non-activating panel,
// settings window) are all managed imperatively — SwiftUI scene lifecycle
// fights that model (docs/DESIGN.md §2).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
