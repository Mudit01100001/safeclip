import CoreGraphics
import Vision

/// On-device text recognition for captured images using the Vision framework.
/// All processing is local — no data leaves the device.
enum OCRService {
    /// Recognizes text in PNG image data. Returns the joined lines, or nil when
    /// no text is found. Runs off the main thread; safe to await from @MainActor.
    static func recognizeText(in imageData: Data) async -> String? {
        await Task.detached(priority: .utility) {
            guard let cgImage = Self.cgImage(from: imageData) else { return nil }
            var recognized: String?
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let joined = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                recognized = joined.isEmpty ? nil : joined
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return recognized
        }.value
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
