import AppKit
import ApplicationServices

/// Reads the on-screen location of the focused text caret so the floating panel
/// can anchor above it (owner request, 15 June 2026; ROADMAP §9 / R1).
///
/// This is the *only* place SafeClip touches the Accessibility API, and it is
/// strictly read-only: it reads `kAXFocusedUIElement` → `kAXSelectedTextRange`
/// → `kAXBoundsForRange` and nothing else. It never reads element values or the
/// text in a field, never observes keystrokes, and never synthesizes input —
/// the user always presses ⌘V themselves (PRD §8.1). Caret anchoring is opt-in
/// and the permission is requested only after an in-app explanation sheet
/// (GeneralSettingsView), keeping the "zero permissions at launch" pillar.
@MainActor
enum CaretLocator {
    /// Accessibility control of other apps is blocked inside the App Sandbox, so
    /// caret anchoring is a non-sandboxed-build feature (mirrors
    /// `ScreenOCRService.isAvailable`). The MAS build disables the toggle.
    static var isSupported: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    /// True once the user has granted SafeClip Accessibility access. Read-only —
    /// does not show the system prompt.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the one-time macOS Accessibility prompt (and deep-links System
    /// Settings). Call only *after* the in-app explanation sheet — never cold.
    @discardableResult
    static func requestTrust() -> Bool {
        // Literal key value avoids the `Unmanaged<CFString>` import that varies
        // across SDKs (see the Sendable-portability note in CLAUDE.md).
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The insertion-point rectangle of the focused text element, in AppKit
    /// screen coordinates (bottom-left origin). nil when there is no text focus,
    /// the app doesn't expose caret bounds, or access hasn't been granted — the
    /// caller then falls back to mouse anchoring. `assistChromium` lets the
    /// caller honour the "help Chromium/Electron apps" toggle.
    ///
    /// In Debug builds each step logs "SafeClip caret: …" (visible in the Xcode
    /// console), so a failing app reveals exactly where it drops out.
    static func caretRect(assistChromium: Bool = true) -> CGRect? {
        guard isSupported else { diag("unavailable in this build (sandbox)"); return nil }
        guard isTrusted else {
            diag("NOT trusted — grant Accessibility to THIS build in System Settings")
            return nil
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        if assistChromium { prewarmFrontmostApp() }

        let system = AXUIElementCreateSystemWide()
        guard
            let focused = copyValue(system, kAXFocusedUIElementAttribute),
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { diag("no focused UI element (frontmost=\(frontmost))"); return nil }
        let element = focused as! AXUIElement // checked by CFGetTypeID above
        let role = (copyValue(element, kAXRoleAttribute) as? String) ?? "?"

        guard
            let rangeValue = copyValue(element, kAXSelectedTextRangeAttribute),
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { diag("no selected-text-range (frontmost=\(frontmost) role=\(role))"); return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            diag("range decode failed (frontmost=\(frontmost) role=\(role))")
            return nil
        }

        // Ask, in order: the caret itself (zero-length), the character after it,
        // then the character before it. Native AppKit/WebKit fields answer the
        // zero-length query; some Chromium/Electron fields only answer a
        // non-empty range (and many answer none — then we fall back to mouse).
        let location = range.location
        let probes = [
            CFRange(location: location, length: 0),
            CFRange(location: location, length: 1),
            CFRange(location: max(0, location - 1), length: 1),
        ]
        for probe in probes {
            if let quartzRect = boundsForRange(element, probe), quartzRect.height > 0 {
                let appKit = convertFromQuartz(quartzRect)
                diag("OK frontmost=\(frontmost) role=\(role) quartz=\(quartzRect) appKit=\(appKit.map { "\($0)" } ?? "nil")")
                return appKit
            }
        }

        // Chromium/WebKit (Claude, Arc, …) report an AXTextArea + selected range
        // but don't answer kAXBoundsForRange; they expose caret geometry through
        // the text-marker API VoiceOver uses. Read-only, same as everything else.
        if let quartzRect = boundsViaSelectedTextMarker(element), quartzRect.height > 0 {
            let appKit = convertFromQuartz(quartzRect)
            diag("OK via text-marker frontmost=\(frontmost) role=\(role) appKit=\(appKit.map { "\($0)" } ?? "nil")")
            return appKit
        }

        diag("no caret bounds (frontmost=\(frontmost) role=\(role)) — mouse fallback")
        return nil
    }

    /// WebKit/Chromium caret bounds via the (undocumented but VoiceOver-stable)
    /// text-marker attributes: `AXSelectedTextMarkerRange` → `AXBoundsForTextMarkerRange`.
    /// The marker range is an opaque CFTypeRef we just hand straight back as the
    /// parameter. Walks a few ancestors because the markers may live on the
    /// AXWebArea rather than the focused text control.
    private static func boundsViaSelectedTextMarker(_ element: AXUIElement) -> CGRect? {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 6 {
            if let markerRange = copyValue(node, "AXSelectedTextMarkerRange") {
                var boundsRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    node, "AXBoundsForTextMarkerRange" as CFString, markerRange, &boundsRef
                ) == .success,
                    let boundsValue = boundsRef,
                    CFGetTypeID(boundsValue) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.height > 0 {
                        return rect
                    }
                }
            }
            if let parent = copyValue(node, kAXParentAttribute),
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                current = (parent as! AXUIElement)
            } else {
                current = nil
            }
            depth += 1
        }
        return nil
    }

    #if DEBUG
    private static func diag(_ message: @autoclosure () -> String) {
        NSLog("SafeClip caret: %@", message())
    }
    #else
    private static func diag(_ message: @autoclosure () -> String) {}
    #endif

    /// `kAXBoundsForRange` for one text range, as a Quartz rect (top-left origin).
    private static func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let rangeArg = AXValueCreate(.cfRange, &range) else { return nil }
        var boundsRef: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeArg,
                &boundsRef
            ) == .success,
            let boundsValue = boundsRef,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Chromium/Electron apps (Claude for Desktop, Arc, Wispr Flow, …) expose
    /// no accessibility tree — and therefore no caret bounds — until an
    /// assistive client asks them to. Setting `AXManualAccessibility` on the
    /// frontmost app turns that on; it's a no-op on native apps (which don't
    /// support the attribute). This is the one *write* SafeClip makes through
    /// Accessibility, and it only enables *reading*: it injects no input and
    /// reads no keystrokes or field text (R1).
    ///
    /// `AppDelegate` calls this on app-activation (when caret anchoring is on)
    /// so the tree is already built by the time the user opens the panel — the
    /// tree builds asynchronously, so enabling it only at panel-open time would
    /// miss the first ⌥V after switching apps.
    static func prewarmFrontmostApp() {
        guard isSupported, isTrusted,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    /// Quartz global coords (top-left origin, y grows down) → AppKit screen
    /// coords (bottom-left origin, y grows up), using the primary display height
    /// (the screen whose frame origin is the global origin).
    private static func convertFromQuartz(_ rect: CGRect) -> CGRect? {
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
        guard let primaryHeight else { return nil }
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
