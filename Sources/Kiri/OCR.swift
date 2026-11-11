import AppKit
import Vision

struct OCRResult {
    let text: String
    let confidence: Float
}

enum OCR {
    static func recognize(_ image: CGImage, correction: Bool = false) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = correction
        request.minimumTextHeight = 0
        guard try request.supportedRecognitionLanguages().contains("ja-JP") else {
            throw NSError(domain: "Kiri", code: 1, userInfo: [NSLocalizedDescriptionKey: "Japanese OCR is unavailable on this macOS version."])
        }
        let longestSide = max(image.width, image.height)
        let shortestSide = min(image.width, image.height)
        let primary = try read(prepare(image), with: request)
        guard primary.text.isEmpty, shortestSide >= 160, longestSide <= shortestSide * 2 else {
            return primary
        }

        // Vision can miss an isolated glyph when it fills a large crop. Retry at text size.
        let scale = 64 / CGFloat(longestSide)
        let reduced = prepare(image, scale: scale)
        if let neutral = mutingBrightColors(in: reduced) {
            let retry = try read(neutral, with: request)
            if !retry.text.isEmpty { return retry }
        }
        return try read(reduced, with: request)
    }

    private static func read(_ image: CGImage, with request: VNRecognizeTextRequest) throws -> OCRResult {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = (request.results ?? []).sorted {
            let a = $0.boundingBox, b = $1.boundingBox
            if abs(a.midY - b.midY) > min(a.height, b.height) * 0.5 { return a.midY > b.midY }
            return a.minX < b.minX
        }
        let candidates = observations.compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = candidates.isEmpty ? 0 : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)
        return OCRResult(text: text, confidence: confidence)
    }

    // Padding gives tightly selected glyphs room; enlargement is reserved for small crops.
    private static func prepare(_ image: CGImage, scale requestedScale: CGFloat? = nil) -> CGImage {
        let scale = requestedScale ?? (image.height < 100 && image.width < 1200 ? 3 : 1)
        let padding = 16
        let width = Int(CGFloat(image.width) * scale) + padding * 2
        let height = Int(CGFloat(image.height) * scale) + padding * 2
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        // Match padding to the crop's corner so dark-background text stays dark.
        var pixel = [UInt8](repeating: 0, count: 4)
        let sampleColor: NSColor = pixel.withUnsafeMutableBytes { bytes in
            guard let sample = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                         bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let corner = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) else { return .white }
            sample.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return NSColor(red: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255, blue: CGFloat(bytes[2]) / 255, alpha: 1)
        }
        context.setFillColor(sampleColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: padding, y: padding, width: width - padding * 2, height: height - padding * 2))
        return context.makeImage() ?? image
    }

    private static func mutingBrightColors(in image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // On light paper, bright markup becomes background while black strokes retain their shape.
        guard min(pixels[0], pixels[1], pixels[2]) >= 230 else { return nil }
        var changed = false
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * context.bytesPerRow + x * 4
                let brightest = max(pixels[offset], pixels[offset + 1], pixels[offset + 2])
                let darkest = min(pixels[offset], pixels[offset + 1], pixels[offset + 2])
                changed = changed || (brightest >= 230 && brightest - darkest >= 24)
                pixels[offset] = brightest
                pixels[offset + 1] = brightest
                pixels[offset + 2] = brightest
            }
        }
        return changed ? context.makeImage() : nil
    }
}

struct CaptureGeometry {
    static func pixelRect(_ rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let clipped = rect.standardized.intersection(CGRect(origin: .zero, size: viewSize))
        guard !clipped.isNull, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGRect(x: clipped.minX * imageSize.width / viewSize.width,
                      y: clipped.minY * imageSize.height / viewSize.height,
                      width: clipped.width * imageSize.width / viewSize.width,
                      height: clipped.height * imageSize.height / viewSize.height).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }
}
