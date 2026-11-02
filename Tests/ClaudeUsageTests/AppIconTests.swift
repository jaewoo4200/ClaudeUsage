import AppKit
import ImageIO
import XCTest
@testable import ClaudeUsage

final class AppIconTests: XCTestCase {
    @MainActor
    func testSettingsLogoUsesBundledArtworkWithoutTemplateTinting() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        let expected = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertFalse(AppLogo.image.isTemplate)
        XCTAssertEqual(AppLogo.image.representations.count, 10)
        XCTAssertEqual(try XCTUnwrap(AppLogo.image.tiffRepresentation), try XCTUnwrap(expected.tiffRepresentation))
    }

    private func iconSource() throws -> CGImageSource {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        return try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    func testIconContainsEveryStandardAndRetinaRepresentation() throws {
        let source = try iconSource()
        var sizes: Set<String> = []
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                                            as? [CFString: Any])
            let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
            let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
            let dpi = try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double)
            XCTAssertEqual(width, height)
            sizes.insert("\(width)@\(Int(dpi))")
        }
        XCTAssertEqual(sizes, ["16@72", "32@144", "32@72", "64@144", "128@72",
                               "256@144", "256@72", "512@144", "512@72", "1024@144"])
    }

    func testSmallIconsRoundTripThroughSystemIconDecoder() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).iconset")
        defer { try? FileManager.default.removeItem(at: output) }
        // ImageIO accepts PNG-filled legacy slots that the Finder/iconutil decoder misinterprets.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "iconset", url.path, "-o", output.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        func decoded(_ name: String) throws -> CGImage {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(output.appendingPathComponent(name) as CFURL, nil))
            return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let master = try decoded("icon_512x512@2x.png")
        for name in ["icon_16x16.png", "icon_16x16@2x.png", "icon_32x32.png",
                     "icon_32x32@2x.png", "icon_128x128.png"] {
            let image = try decoded(name)
            let actual = try pixels(image, size: image.width)
            let expected = try pixels(master, size: image.width)
            let error = zip(actual, expected).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
                / Double(actual.count) / 255
            // Permit resizing/compression differences, but reject noise from incompatible ICNS slots.
            XCTAssertLessThan(error, 0.06, "\(name): decoded artwork differs")
        }
    }

    private func pixels(_ image: CGImage, size: Int) throws -> [UInt8] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: size * size * 4))
    }
}
