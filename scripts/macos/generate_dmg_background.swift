#!/usr/bin/env swift

import AppKit
import Foundation

private enum BackgroundError: LocalizedError {
    case invalidArguments
    case missingCharacter(URL)
    case invalidCharacterSheet(URL)
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: generate_dmg_background.swift /path/to/repository /path/to/background.png"
        case let .missingCharacter(url):
            return "Character sheet is missing: \(url.path)"
        case let .invalidCharacterSheet(url):
            return "Character sheet must be at least 24×24 pixels: \(url.path)"
        case .bitmapCreationFailed:
            return "Could not create the 660×420 DMG background bitmap"
        case .pngEncodingFailed:
            return "Could not encode the DMG background as PNG"
        }
    }
}

private let canvasSize = NSSize(width: 660, height: 420)
private let frameSize = NSSize(width: 24, height: 24)
private let characterScale: CGFloat = 3

private let characterPaths = [
    "macos/SIDEY/Resources/Characters/PixelHamster/pixel_hamster.png",
    "macos/SIDEY/Resources/Characters/PixelCat/pixel_cat.png",
    "macos/SIDEY/Resources/Characters/PixelPuppy/pixel_puppy.png",
    "macos/SIDEY/Resources/Characters/PixelRabbit/pixel_rabbit.png",
    "macos/SIDEY/Resources/Characters/PixelPenguin/pixel_penguin.png",
]

private func fill(_ rect: NSRect, color: NSColor) {
    color.setFill()
    rect.fill()
}

private func drawText(
    _ text: String,
    at point: NSPoint,
    font: NSFont,
    color: NSColor
) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    attributed.draw(
        in: NSRect(
            x: point.x,
            y: point.y,
            width: canvasSize.width - (point.x * 2),
            height: font.pointSize * 1.5
        )
    )
}

private func drawPixelArrow() {
    let accent = NSColor(calibratedRed: 0.98, green: 0.56, blue: 0.20, alpha: 1)
    fill(NSRect(x: 278, y: 207, width: 96, height: 8), color: accent)
    fill(NSRect(x: 358, y: 223, width: 8, height: 8), color: accent)
    fill(NSRect(x: 366, y: 215, width: 8, height: 8), color: accent)
    fill(NSRect(x: 374, y: 199, width: 8, height: 16), color: accent)
    fill(NSRect(x: 366, y: 191, width: 8, height: 8), color: accent)
    fill(NSRect(x: 358, y: 183, width: 8, height: 8), color: accent)
}

private func drawCharacter(from url: URL, at origin: NSPoint) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw BackgroundError.missingCharacter(url)
    }
    guard let image = NSImage(contentsOf: url),
          image.size.width >= frameSize.width,
          image.size.height >= frameSize.height else {
        throw BackgroundError.invalidCharacterSheet(url)
    }

    image.draw(
        in: NSRect(
            x: origin.x,
            y: origin.y,
            width: frameSize.width * characterScale,
            height: frameSize.height * characterScale
        ),
        from: NSRect(origin: .zero, size: frameSize),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.none]
    )
}

private func generate(repositoryRoot: URL, outputURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw BackgroundError.bitmapCreationFailed
    }

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw BackgroundError.bitmapCreationFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let background = NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.13, alpha: 1)
    let panel = NSColor(calibratedRed: 0.105, green: 0.125, blue: 0.175, alpha: 1)
    let border = NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.31, alpha: 1)
    let primaryText = NSColor(calibratedWhite: 0.96, alpha: 1)
    let secondaryText = NSColor(calibratedWhite: 0.72, alpha: 1)

    fill(NSRect(origin: .zero, size: canvasSize), color: background)
    fill(NSRect(x: 0, y: 0, width: canvasSize.width, height: 118), color: panel)
    fill(NSRect(x: 0, y: 116, width: canvasSize.width, height: 2), color: border)

    drawText(
        "SIDEY 설치",
        at: NSPoint(x: 48, y: 344),
        font: .monospacedSystemFont(ofSize: 32, weight: .bold),
        color: primaryText
    )
    drawText(
        "SIDEY를 Applications 폴더로 드래그해 설치하세요",
        at: NSPoint(x: 48, y: 304),
        font: .systemFont(ofSize: 16, weight: .medium),
        color: secondaryText
    )
    drawPixelArrow()

    let characterWidth = frameSize.width * characterScale
    let spacing: CGFloat = 22
    let totalWidth = (characterWidth * CGFloat(characterPaths.count))
        + (spacing * CGFloat(characterPaths.count - 1))
    let startX = (canvasSize.width - totalWidth) / 2
    for (index, relativePath) in characterPaths.enumerated() {
        try drawCharacter(
            from: repositoryRoot.appendingPathComponent(relativePath),
            at: NSPoint(
                x: startX + (CGFloat(index) * (characterWidth + spacing)),
                y: 24
            )
        )
    }

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw BackgroundError.pngEncodingFailed
    }
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw BackgroundError.invalidArguments
    }
    let repositoryRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    try generate(repositoryRoot: repositoryRoot, outputURL: outputURL)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
