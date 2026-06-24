import AppKit

/// "Capture text from screen": runs the native macOS region-screenshot UI, OCRs
/// the selected region, and places the recognized text on the clipboard. The
/// screenshot lives in a temp file only long enough to OCR, then is deleted —
/// it is never added to history.
///
/// Capture is delegated to `/usr/sbin/screencapture -i` (the same interactive
/// crosshair as ⌘⇧4). Because the system screenshot service performs the grab
/// on the user's behalf, SafeClip itself needs no Screen Recording permission —
/// preserving the zero-permission design pillar (PRD §8.1). Spawning a process
/// is forbidden under the App Sandbox, so this path is for the non-sandboxed
/// (website/Developer ID) build; in a sandboxed build it reports `.unavailable`.
@MainActor
enum ScreenOCRService {
    enum Outcome: Sendable {
        case copied(String)
        case noText
        case cancelled
        case unavailable
    }

    /// False inside an App Sandbox container, where `Process` is blocked.
    static var isAvailable: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    static func capture() async -> Outcome {
        guard isAvailable else { return .unavailable }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safeclip-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let selectionMade = await runScreencapture(to: tempURL)
        guard selectionMade,
              FileManager.default.fileExists(atPath: tempURL.path),
              let imageData = try? Data(contentsOf: tempURL)
        else {
            return .cancelled // user pressed Esc / made no selection
        }

        guard let text = await OCRService.recognizeText(in: imageData) else {
            return .noText
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // No self-write marker: the recognized text is a normal copy, so the
        // monitor captures it into history like anything else the user copies.
        return .copied(text)
    }

    /// Launches the interactive screenshot tool and resolves when it exits.
    /// Returns true on a clean exit (a region was captured to `url`); cancel or
    /// failure resolves false.
    private static func runScreencapture(to url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i interactive, -x silent (no shutter sound), -t png.
            process.arguments = ["-i", "-x", "-t", "png", url.path]
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
