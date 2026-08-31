#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let frameSize = 24
private let frameCount = 10
private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private struct Palette {
    let primary: CGColor
    let light: CGColor
    let shadow: CGColor
    let cream: CGColor
    let outline: CGColor
    let cheek: CGColor
    let accent: CGColor
    let accentShadow: CGColor
}

private enum Species: String, CaseIterable {
    case pixelHamster = "pixel_hamster"
    case pixelCat = "pixel_cat"
    case pixelPuppy = "pixel_puppy"
    case pixelRabbit = "pixel_rabbit"
    case pixelPenguin = "pixel_penguin"

    var directoryName: String {
        switch self {
        case .pixelHamster: "PixelHamster"
        case .pixelCat: "PixelCat"
        case .pixelPuppy: "PixelPuppy"
        case .pixelRabbit: "PixelRabbit"
        case .pixelPenguin: "PixelPenguin"
        }
    }

    var palette: Palette {
        switch self {
        case .pixelHamster:
            Palette(
                primary: rgb(0.91, 0.58, 0.20), light: rgb(0.98, 0.72, 0.31),
                shadow: rgb(0.67, 0.36, 0.14), cream: rgb(1.00, 0.91, 0.72),
                outline: rgb(0.24, 0.12, 0.10), cheek: rgb(0.94, 0.48, 0.48),
                accent: rgb(0.45, 0.49, 0.85), accentShadow: rgb(0.31, 0.34, 0.68)
            )
        case .pixelCat:
            Palette(
                primary: rgb(0.49, 0.47, 0.50), light: rgb(0.68, 0.65, 0.67),
                shadow: rgb(0.30, 0.28, 0.31), cream: rgb(0.98, 0.91, 0.80),
                outline: rgb(0.18, 0.15, 0.17), cheek: rgb(0.94, 0.57, 0.64),
                accent: rgb(0.64, 0.51, 0.78), accentShadow: rgb(0.45, 0.34, 0.62)
            )
        case .pixelPuppy:
            Palette(
                primary: rgb(0.76, 0.42, 0.17), light: rgb(0.93, 0.61, 0.27),
                shadow: rgb(0.48, 0.24, 0.10), cream: rgb(1.00, 0.91, 0.73),
                outline: rgb(0.25, 0.12, 0.08), cheek: rgb(0.95, 0.53, 0.53),
                accent: rgb(0.35, 0.66, 0.88), accentShadow: rgb(0.23, 0.48, 0.70)
            )
        case .pixelRabbit:
            Palette(
                primary: rgb(0.94, 0.90, 0.80), light: rgb(1.00, 0.97, 0.88),
                shadow: rgb(0.72, 0.64, 0.59), cream: rgb(1.00, 0.94, 0.84),
                outline: rgb(0.34, 0.25, 0.23), cheek: rgb(0.96, 0.62, 0.54),
                accent: rgb(0.63, 0.53, 0.82), accentShadow: rgb(0.46, 0.37, 0.65)
            )
        case .pixelPenguin:
            Palette(
                primary: rgb(0.11, 0.20, 0.38), light: rgb(0.20, 0.33, 0.56),
                shadow: rgb(0.06, 0.11, 0.24), cream: rgb(1.00, 0.94, 0.79),
                outline: rgb(0.04, 0.07, 0.15), cheek: rgb(0.95, 0.58, 0.55),
                accent: rgb(0.34, 0.75, 0.61), accentShadow: rgb(0.22, 0.55, 0.43)
            )
        }
    }

    var accentIsScarf: Bool { true }
}

private enum Pose {
    case idle(breath: Int)
    case walk(step: Int)
    case doze(nod: Int)
    case offline(breath: Int)
}

private let poses: [Pose] = [
    .idle(breath: 0), .idle(breath: 1),
    .walk(step: 0), .walk(step: 1), .walk(step: 2), .walk(step: 3),
    .doze(nod: 0), .doze(nod: 1),
    .offline(breath: 0), .offline(breath: 1)
]

for species in Species.allCases {
    let outputDirectory = repositoryRoot
        .appendingPathComponent("macos/SIDEY/Resources/Characters")
        .appendingPathComponent(species.directoryName)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try generate(species: species, outputURL: outputDirectory.appendingPathComponent("\(species.rawValue).png"))
}

private func generate(species: Species, outputURL: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: frameSize * frameCount,
        height: frameSize,
        bitsPerComponent: 8,
        bytesPerRow: frameSize * frameCount * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create \(species.rawValue) bitmap context") }
    context.setShouldAntialias(false)
    context.interpolationQuality = .none
    context.clear(CGRect(x: 0, y: 0, width: frameSize * frameCount, height: frameSize))

    for (frame, pose) in poses.enumerated() {
        draw(species: species, pose: pose, frame: frame, in: context)
    }

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              outputURL as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          )
    else { fatalError("Could not create \(species.rawValue) PNG destination") }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: 0]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not finalize \(species.rawValue) PNG")
    }
    print("Generated \(outputURL.path)")
}

private func draw(species: Species, pose: Pose, frame: Int, in context: CGContext) {
    let palette = species.palette
    let originX = frame * frameSize
    let headOffset: Int
    let footShift: Int
    let eyesClosed: Bool
    let curled: Bool
    switch pose {
    case .idle(let breath):
        headOffset = breath
        footShift = 0
        eyesClosed = false
        curled = false
    case .walk(let step):
        headOffset = step.isMultiple(of: 2) ? 0 : 1
        footShift = step
        eyesClosed = false
        curled = false
    case .doze(let nod):
        headOffset = -nod
        footShift = 0
        eyesClosed = true
        curled = false
    case .offline(let breath):
        headOffset = breath
        footShift = 0
        eyesClosed = true
        curled = true
    }

    func pixel(_ x: Int, _ y: Int, _ color: CGColor, width: Int = 1, height: Int = 1) {
        context.setFillColor(color)
        context.fill(CGRect(x: originX + x, y: y, width: width, height: height))
    }

    func rows(_ values: [(Int, Int, Int)], _ color: CGColor, yOffset: Int = 0) {
        for (y, start, end) in values {
            pixel(start, y + yOffset, color, width: end - start + 1)
        }
    }

    if curled {
        // Sideways curled sleep. Every offline frame still owns the exact y=3
        // alpha baseline used by every upright foot frame.
        rows([(3, 6, 17), (4, 4, 19), (5, 3, 20), (6, 2, 21), (7, 2, 21),
              (8, 2, 21), (9, 3, 20), (10, 4, 19), (11, 6, 17)], palette.outline)
        rows([(4, 6, 17), (5, 4, 19), (6, 3, 20), (7, 3, 20),
              (8, 4, 19), (9, 5, 18), (10, 7, 16)], palette.primary)
        rows([(5, 6, 16), (6, 5, 17), (7, 5, 17), (8, 7, 16)], palette.cream)
        pixel(5 + headOffset, 8, palette.outline, width: 3)
        pixel(12, 7, palette.shadow, width: 5)
        pixel(17, 5, palette.light, width: 2)
        if species == .pixelPenguin { pixel(7, 6, rgb(0.94, 0.49, 0.10), width: 2) }
        return
    }

    // Shared upright rounded body, always anchored by feet at y=3.
    rows([(3, 6, 8), (3, 15, 17)], palette.outline)
    rows([(4, 5, 18), (5, 4, 19), (6, 4, 19), (7, 3, 20), (8, 3, 20),
          (9, 3, 20), (10, 3, 20), (11, 4, 19), (12, 4, 19),
          (13, 5, 18), (14, 6, 17)], palette.outline, yOffset: headOffset)
    rows([(4, 7, 8), (4, 15, 16)], species == .pixelPenguin ? rgb(0.94, 0.49, 0.10) : palette.cheek)
    rows([(5, 6, 17), (6, 5, 18), (7, 4, 19), (8, 4, 19), (9, 4, 19),
          (10, 4, 19), (11, 5, 18), (12, 5, 18), (13, 7, 16)], palette.primary, yOffset: headOffset)
    rows([(5, 9, 14), (6, 8, 15), (7, 7, 16), (8, 7, 16),
          (9, 6, 17), (10, 6, 17), (11, 7, 16)], palette.cream, yOffset: headOffset)
    rows([(12, 8, 15), (13, 9, 14)], palette.light, yOffset: headOffset)

    drawSpeciesFeatures(
        species: species,
        palette: palette,
        headOffset: headOffset,
        eyesClosed: eyesClosed,
        pixel: pixel,
        rows: rows
    )

    // Scarf accent and feet remain compact enough to read at 2x nearest.
    pixel(4, 9 + headOffset, palette.accent, width: 16)
    pixel(5, 8 + headOffset, palette.accent, width: 14)
    pixel(17, 7 + headOffset, palette.accentShadow, width: 2)

    let leftX = footShift == 0 || footShift == 3 ? 5 : 7
    let rightX = footShift == 1 || footShift == 2 ? 16 : 14
    let footColor = species == .pixelPenguin ? rgb(0.94, 0.49, 0.10) : palette.cheek
    pixel(leftX, 3, footColor, width: 3)
    pixel(rightX, 3, footColor, width: 3)
}

private func drawSpeciesFeatures(
    species: Species,
    palette: Palette,
    headOffset: Int,
    eyesClosed: Bool,
    pixel: (Int, Int, CGColor, Int, Int) -> Void,
    rows: ([(Int, Int, Int)], CGColor, Int) -> Void
) {
    switch species {
    case .pixelHamster:
        rows([(14, 5, 8), (14, 15, 18), (15, 4, 8), (15, 15, 19),
              (16, 5, 7), (16, 16, 18)], palette.outline, headOffset)
        pixel(6, 15 + headOffset, palette.cheek, 2, 2)
        pixel(16, 15 + headOffset, palette.cheek, 2, 2)
    case .pixelCat:
        rows([(14, 4, 8), (14, 15, 19), (15, 3, 8), (15, 15, 20),
              (16, 3, 6), (16, 17, 20), (17, 3, 4), (17, 19, 20)], palette.outline, headOffset)
        rows([(15, 5, 7), (15, 16, 18), (16, 4, 5), (16, 18, 19)], palette.cheek, headOffset)
        pixel(19, 6 + headOffset, palette.shadow, 3, 1)
    case .pixelPuppy:
        rows([(13, 2, 6), (13, 17, 21), (14, 1, 6), (14, 17, 22),
              (15, 1, 5), (15, 18, 22), (16, 2, 4), (16, 19, 21)], palette.shadow, headOffset)
        pixel(2, 13 + headOffset, palette.primary, 4, 2)
        pixel(18, 13 + headOffset, palette.primary, 4, 2)
    case .pixelRabbit:
        rows([(14, 5, 8), (14, 15, 18), (15, 4, 8), (15, 15, 19),
              (16, 4, 7), (16, 16, 19), (17, 4, 7), (17, 16, 19),
              (18, 4, 7), (18, 16, 19), (19, 4, 7), (19, 16, 19),
              (20, 5, 7), (20, 16, 18), (21, 5, 6), (21, 17, 18)], palette.outline, headOffset)
        rows([(16, 5, 6), (16, 17, 18), (17, 5, 6), (17, 17, 18),
              (18, 5, 6), (18, 17, 18), (19, 5, 6), (19, 17, 18)], palette.cheek, headOffset)
    case .pixelPenguin:
        pixel(10, 10 + headOffset, rgb(0.94, 0.49, 0.10), 4, 2)
        pixel(2, 7 + headOffset, palette.shadow, 3, 4)
        pixel(19, 7 + headOffset, palette.shadow, 3, 4)
    }

    if eyesClosed {
        pixel(7, 12 + headOffset, palette.outline, 3, 1)
        pixel(14, 12 + headOffset, palette.outline, 3, 1)
    } else {
        pixel(8, 12 + headOffset, palette.outline, 2, 2)
        pixel(14, 12 + headOffset, palette.outline, 2, 2)
        pixel(8, 13 + headOffset, palette.cream, 1, 1)
        pixel(14, 13 + headOffset, palette.cream, 1, 1)
    }
    if species != .pixelPenguin {
        pixel(11, 10 + headOffset, palette.cheek, 2, 1)
    }
    pixel(10, 9 + headOffset, palette.outline, 1, 1)
    pixel(13, 9 + headOffset, palette.outline, 1, 1)
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: 1)
}
