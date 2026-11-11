import AppKit

@MainActor
enum SelfTests {
    static func fixture(_ text: String, size: CGFloat, dark: Bool = false) -> CGImage {
        let font = NSFont(name: "HiraginoSans-W3", size: size) ?? .systemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dark ? NSColor.white : NSColor.black]
        let measured = (text as NSString).size(withAttributes: attributes)
        let width = Int(ceil(measured.width)) + 8, height = Int(ceil(measured.height)) + 8
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        (dark ? NSColor(white: 0.08, alpha: 1) : NSColor.white).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        (text as NSString).draw(at: NSPoint(x: 4, y: 4), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
    static func run() -> Bool {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        let rect = CaptureGeometry.pixelRect(CGRect(x: 40, y: 30, width: 80, height: 50), viewSize: CGSize(width: 500, height: 300), imageSize: CGSize(width: 1000, height: 600))
        check(rect == CGRect(x: 80, y: 60, width: 160, height: 100), "Retina crop coordinates")
        let reverse = CaptureGeometry.pixelRect(CGRect(x: 120, y: 80, width: -80, height: -50), viewSize: CGSize(width: 500, height: 300), imageSize: CGSize(width: 1000, height: 600))
        check(reverse == rect, "Reverse-direction selection")
        let clipped = CaptureGeometry.pixelRect(CGRect(x: -10, y: -10, width: 30, height: 30), viewSize: CGSize(width: 500, height: 300), imageSize: CGSize(width: 1000, height: 600))
        check(clipped == CGRect(x: 0, y: 0, width: 40, height: 40), "Selection clips to screen")
        let cases: [(String, CGFloat, Bool)] = [("猫", 40, false), ("霧", 40, false), ("許", 32, false), ("寝", 32, false), ("朝", 24, false), ("き", 24, false), ("鬱", 40, false), ("食べる", 28, false), ("日本語", 16, false), ("勉強", 18, true), ("今日はいい天気です。", 24, false)]
        for (expected, size, dark) in cases {
            do {
                let image = fixture(expected, size: size, dark: dark)
                let output = try OCR.recognize(image)
                check(output.text == expected, "Japanese \(expected) at \(Int(size))px \(dark ? "dark" : "light") → \(output.text)")
            } catch { check(false, "OCR: \(error.localizedDescription)") }
        }
        do {
            let blank = fixture("", size: 40)
            let result = try OCR.recognize(blank)
            check(result.text.isEmpty, "Blank image produces no text")
        } catch { check(false, "Blank OCR: \(error)") }
        print("\(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECKS FAILED")")
        return failures == 0
    }
}
