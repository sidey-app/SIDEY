// Review renderer only. Draws the approved, unmodified body frames and a code-native pixel star.
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: swift render_preview.swift REPOSITORY OUTPUT") }
let repository = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let source = repository.appendingPathComponent("assets/v1/characters/pixel_hamster/base.png")
let sheet = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(source as CFURL, nil)!, 0, nil)!
let poses = [0, 8, 9].map { sheet.cropping(to: CGRect(x: $0 * 24, y: 0, width: 24, height: 24))! }
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas(_ width: Int, _ height: Int) -> CGContext {
    let result = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    result.setShouldAntialias(false)
    result.interpolationQuality = .none
    return result
}

func rgb(_ value: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((value >> 16) & 255) / 255,
        CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, 1])!
}

// Seven-pixel star icon; independent of all approved character sheets.
let starRows = ["...O...", "..OYO..", "OOYHYOO", "OYYYYYO", ".OYYYO.", ".OYOYO.", ".OO.OO."]
let starContext = canvas(7, 7)
for (row, line) in starRows.enumerated() {
    for (column, pixel) in line.enumerated() where pixel != "." {
        starContext.setFillColor(rgb(pixel == "O" ? 0x8B5C19 : pixel == "H" ? 0xFFF6AE : 0xFFD34D))
        starContext.fill(CGRect(x: column, y: 6 - row, width: 1, height: 1))
    }
}
let star = starContext.makeImage()!

func png(_ image: CGImage, _ name: String) {
    let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}

func scaled(_ image: CGImage, by scale: Int) -> CGImage {
    let c = canvas(image.width * scale, image.height * scale)
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale))
    return c.makeImage()!
}

func scene(time: Double, phase: Double? = nil, poseOverride: Int? = nil, background: UInt32? = nil) -> CGImage {
    let c = canvas(64, 42)
    if let background {
        c.setFillColor(rgb(background))
        c.fill(CGRect(x: 0, y: 0, width: 64, height: 42))
    }
    let isStunned = phase != nil || (time >= 0.6 && time < 6.6)
    let elapsed = phase ?? max(0, time - 0.6)
    let pose = poseOverride ?? (isStunned ? 1 + Int(elapsed / 1.2) % 2 : 0)
    let stars = (0..<3).map { index -> (Double, CGRect) in
        let angle = elapsed / 1.2 * 2 * Double.pi + Double(index) * 2 * Double.pi / 3
        let depth = sin(angle)
        let rect = CGRect(x: round(32 + 11 * cos(angle) - 3.5),
            y: round(19 + 5 * depth - 3.5), width: 7, height: 7)
        return (depth, rect)
    }.sorted { $0.0 < $1.0 }
    if isStunned {
        for (_, rect) in stars where rect.midY >= 19 { c.draw(star, in: rect) }
    }
    c.draw(poses[pose], in: CGRect(x: 20, y: 0, width: 24, height: 24))
    if isStunned {
        for (_, rect) in stars where rect.midY < 19 { c.draw(star, in: rect) }
    }
    return c.makeImage()!
}

png(star, "star-v1.png")
png(scaled(star, by: 16), "star-v1-16x.png")
png(scene(time: 0, phase: 0, poseOverride: 1), "hamster-stun-frame-8-v1.png")
png(scene(time: 0, phase: 0.6, poseOverride: 2), "hamster-stun-frame-9-v1.png")

let board = canvas(128, 84)
for (row, color) in [UInt32(0xFAF7F1), UInt32(0x202532)].enumerated() {
    for column in 0..<2 {
        let image = scene(time: 0, phase: Double(column) * 0.6, poseOverride: column + 1, background: color)
        board.draw(image, in: CGRect(x: column * 64, y: (1 - row) * 42, width: 64, height: 42))
    }
}
png(scaled(board.makeImage()!, by: 6), "hamster-stun-review-v1.png")

func gif(_ name: String, duration: Double, fixedPhase: Bool, bg: UInt32) {
    let count = Int(duration * 30)
    let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, UTType.gif.identifier as CFString, count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for index in 0..<count {
        let elapsed = Double(index) / 30
        let frame = scene(time: elapsed, phase: fixedPhase ? elapsed : nil, background: bg)
        // GIF stores centiseconds: 30 + 30 + 40 ms repeats, preserving 1.2/6.0 s timing.
        let delay = index % 3 == 2 ? 0.04 : 0.03
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
            kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        CGImageDestinationAddImage(dest, scaled(frame, by: 6), properties)
    }
    precondition(CGImageDestinationFinalize(dest))
}
gif("hamster-stun-orbit-v1.gif", duration: 2.4, fixedPhase: true, bg: 0x202532)
gif("hamster-stun-timeline-v1.gif", duration: 7.2, fixedPhase: false, bg: 0xFAF7F1)

let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
let assets = try files.filter { ["png", "gif"].contains($0.pathExtension) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
    ["file": "visual/" + $0.lastPathComponent, "sha256": SHA256.hash(data: try Data(contentsOf: $0)).map { String(format: "%02x", $0) }.joined(), "approval": "pending"]
}
let manifest: [String: Any] = ["review_round": 1, "approval": "pending", "assets": assets,
    "source_character_sha256": SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined(),
    "source_frames": [8, 9], "body_frame_seconds": 1.2, "orbit_seconds": 1.2,
    "star_count": 3, "star_size_logical_pixels": 7, "orbit_radius_logical_pixels": [11, 5],
    "orbit_center_logical_pixels": [32, 19], "fps": 30, "stun_seconds": 6,
    "recovery_protection_seconds": 0,
    "provenance": "Native code rendering of unchanged approved character frames plus a pixel-grid star icon."]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.deletingLastPathComponent().appendingPathComponent("visual-manifest.json"))
print("Rendered pixel PNGs, orbit GIF and six-second stun timeline; approval pending.")
