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

private struct PixelCanvas {
    let context: CGContext
    let originX: Int

    func pixel(_ x: Int, _ y: Int, _ color: CGColor, width: Int = 1, height: Int = 1) {
        guard width > 0, height > 0 else { return }
        context.setFillColor(color)
        context.fill(CGRect(x: originX + x, y: y, width: width, height: height))
    }

    func rows(
        _ values: [(Int, Int, Int)],
        _ color: CGColor,
        xOffset: Int = 0,
        yOffset: Int = 0
    ) {
        for (y, start, end) in values {
            pixel(start + xOffset, y + yOffset, color, width: end - start + 1)
        }
    }
}

private enum Species: String, CaseIterable {
    case pixelHamster = "pixel_hamster"
    case pixelCat = "pixel_cat"
    case pixelPuppy = "pixel_puppy"
    case pixelRabbit = "pixel_rabbit"
    case pixelPenguin = "pixel_penguin"
    case pixelGuineaPig = "pixel_guinea_pig"
    case pixelMonkey = "pixel_monkey"
    case pixelChinchilla = "pixel_chinchilla"
    case pixelStarlightUpalupa = "pixel_starlight_upalupa"

    var directoryName: String {
        switch self {
        case .pixelHamster: "PixelHamster"
        case .pixelCat: "PixelCat"
        case .pixelPuppy: "PixelPuppy"
        case .pixelRabbit: "PixelRabbit"
        case .pixelPenguin: "PixelPenguin"
        case .pixelGuineaPig: "PixelGuineaPig"
        case .pixelMonkey: "PixelMonkey"
        case .pixelChinchilla: "PixelChinchilla"
        case .pixelStarlightUpalupa: "PixelStarlightUpalupa"
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
        case .pixelGuineaPig:
            Palette(
                primary: rgb(0.73, 0.43, 0.23), light: rgb(0.94, 0.61, 0.24),
                shadow: rgb(0.43, 0.24, 0.17), cream: rgb(1.00, 0.91, 0.72),
                outline: rgb(0.24, 0.11, 0.07), cheek: rgb(0.96, 0.53, 0.58),
                accent: rgb(0.79, 0.61, 0.12), accentShadow: rgb(0.58, 0.42, 0.08)
            )
        case .pixelMonkey:
            Palette(
                primary: rgb(0.57, 0.35, 0.25), light: rgb(0.78, 0.52, 0.33),
                shadow: rgb(0.37, 0.20, 0.16), cream: rgb(1.00, 0.91, 0.73),
                outline: rgb(0.22, 0.11, 0.08), cheek: rgb(0.95, 0.52, 0.57),
                accent: rgb(0.19, 0.68, 0.78), accentShadow: rgb(0.08, 0.48, 0.61)
            )
        case .pixelChinchilla:
            Palette(
                primary: rgb(0.56, 0.54, 0.57), light: rgb(0.73, 0.71, 0.73),
                shadow: rgb(0.37, 0.34, 0.37), cream: rgb(0.98, 0.91, 0.76),
                outline: rgb(0.19, 0.16, 0.17), cheek: rgb(0.95, 0.56, 0.62),
                accent: rgb(0.25, 0.65, 0.84), accentShadow: rgb(0.13, 0.46, 0.68)
            )
        case .pixelStarlightUpalupa:
            Palette(
                primary: rgb(0.95, 0.66, 0.74), light: rgb(1.00, 0.80, 0.84),
                shadow: rgb(0.72, 0.42, 0.59), cream: rgb(1.00, 0.91, 0.73),
                outline: rgb(0.24, 0.10, 0.25), cheek: rgb(0.96, 0.49, 0.60),
                accent: rgb(0.66, 0.53, 0.84), accentShadow: rgb(0.47, 0.76, 0.68)
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

private let generatorArguments = Array(CommandLine.arguments.dropFirst())
private let macOSOnly = generatorArguments.contains("--macos-only")
private let requestedSpecies = Set(generatorArguments.filter { $0 != "--macos-only" })
private let speciesToGenerate = requestedSpecies.isEmpty
    ? Species.allCases
    : try requestedSpecies.map { rawValue in
        guard let species = Species(rawValue: rawValue) else {
            throw GeneratorError.unknownSpecies(rawValue)
        }
        return species
    }

// The approved chinchilla is an exact user-approved 240x24 raster sheet. It is
// imported by import_pixel_chinchilla.sh so running the procedural generator
// cannot accidentally replace the approved ten poses.
if speciesToGenerate.contains(.pixelChinchilla) {
    print("Skipped pixel_chinchilla; run scripts/macos/import_pixel_chinchilla.sh to rebuild it from the approved master")
}

for species in speciesToGenerate where species != .pixelChinchilla {
    let outputDirectory = repositoryRoot
        .appendingPathComponent("macos/SIDEY/Resources/Characters")
        .appendingPathComponent(species.directoryName)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let outputURL = outputDirectory.appendingPathComponent("\(species.rawValue).png")
    try generate(species: species, outputURL: outputURL)
    if species == .pixelStarlightUpalupa && !macOSOnly {
        try exportWindowsRuntimeAsset(species: species, pngURL: outputURL)
    }
}

private enum GeneratorError: LocalizedError {
    case unknownSpecies(String)

    var errorDescription: String? {
        switch self {
        case .unknownSpecies(let value): "Unknown SIDEY character: \(value)"
        }
    }
}

private func generate(species: Species, outputURL: URL) throws {
    let colorSpace = species == .pixelGuineaPig
        ? CGColorSpace(name: CGColorSpace.sRGB)!
        : CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: frameSize * frameCount,
        height: frameSize,
        bitsPerComponent: 8,
        bytesPerRow: frameSize * frameCount * 4,
        space: colorSpace,
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

    let canvas = PixelCanvas(context: context, originX: originX)
    switch species {
    case .pixelGuineaPig:
        drawGuineaPig(pose: pose, palette: palette, canvas: canvas)
        return
    case .pixelMonkey:
        drawMonkey(pose: pose, palette: palette, canvas: canvas)
        return
    case .pixelChinchilla:
        drawChinchilla(pose: pose, palette: palette, canvas: canvas)
        return
    default:
        break
    }

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

    if species == .pixelStarlightUpalupa {
        drawStarlightUpalupa(
            pose: pose,
            palette: palette,
            headOffset: headOffset,
            footShift: footShift,
            eyesClosed: eyesClosed,
            curled: curled,
            pixel: pixel,
            rows: rows
        )
        return
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
    case .pixelStarlightUpalupa, .pixelGuineaPig, .pixelMonkey, .pixelChinchilla:
        preconditionFailure("This species uses its dedicated deterministic silhouette")
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

private func drawGuineaPig(pose: Pose, palette _: Palette, canvas c: PixelCanvas) {
    func hex(_ value: UInt32) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
            CGFloat((value >> 16) & 0xff) / 255,
            CGFloat((value >> 8) & 0xff) / 255,
            CGFloat(value & 0xff) / 255,
            1
        ])!
    }

    let outline = hex(0x4A403B)
    let brownDark = hex(0x6A4A3C)
    let brown = hex(0x8B6550)
    let orange = hex(0xD98B54)
    let orangeDark = hex(0xB86D3F)
    let cream = hex(0xF5E7D1)
    let creamShade = hex(0xE4D1B6)
    let eye = hex(0x171312)
    let eyeHighlight = hex(0xFFF5DB)
    let pink = hex(0xEE8A92)
    let pinkDark = hex(0xC56A77)

    // This character was approved in top-left-origin pixel coordinates. Convert
    // at this boundary so the source specification stays directly editable in
    // Aseprite/Piskel terms while PixelCanvas keeps Core Graphics coordinates.
    func pixel(_ x: Int, _ y: Int, _ color: CGColor, width: Int = 1, height: Int = 1) {
        c.pixel(x, frameSize - y - height, color, width: width, height: height)
    }

    func rows(_ spans: [(Int, Int, Int)], _ color: CGColor, dy: Int = 0) {
        for (y, start, end) in spans {
            pixel(start, y + dy, color, width: end - start + 1)
        }
    }

    func body(dy: Int) {
        rows([
            (7, 5, 18), (8, 3, 20), (9, 2, 21), (10, 2, 21),
            (11, 2, 21), (12, 2, 21), (13, 2, 21), (14, 2, 21),
            (15, 2, 21), (16, 3, 20), (17, 3, 20), (18, 4, 19),
            (19, 5, 18)
        ], outline, dy: dy)
        rows([
            (8, 6, 17), (9, 4, 19), (10, 3, 20), (11, 3, 20),
            (12, 3, 20), (13, 3, 20), (14, 3, 20), (15, 3, 20),
            (16, 4, 19), (17, 4, 19), (18, 5, 18), (19, 6, 17)
        ], cream, dy: dy)
        rows([(18, 7, 16), (19, 7, 16)], creamShade, dy: dy)
    }

    func ears(dy: Int) {
        rows([(5, 5, 7), (6, 4, 8), (7, 4, 8)], outline, dy: dy)
        rows([(5, 16, 18), (6, 15, 19), (7, 15, 19)], outline, dy: dy)
        pixel(6, 6 + dy, pinkDark, width: 2)
        pixel(16, 6 + dy, pinkDark, width: 2)
    }

    func calico(dy: Int) {
        rows([
            (8, 4, 8), (9, 3, 9), (10, 3, 9), (11, 3, 8),
            (12, 3, 8), (13, 3, 7)
        ], brownDark, dy: dy)
        rows([(9, 5, 9), (10, 5, 9), (11, 4, 8), (12, 4, 7)], brown, dy: dy)
        rows([
            (7, 15, 18), (8, 14, 19), (9, 14, 20),
            (10, 15, 20), (11, 15, 19), (12, 16, 19)
        ], orangeDark, dy: dy)
        rows([(8, 15, 18), (9, 15, 19), (10, 16, 19), (11, 16, 18)], orange, dy: dy)
        rows([(14, 3, 8), (15, 3, 8), (16, 4, 8), (17, 4, 8)], brownDark, dy: dy)
        rows([(14, 5, 8), (15, 5, 8), (16, 6, 8)], brown, dy: dy)
        rows([(14, 15, 20), (15, 15, 20), (16, 15, 19), (17, 15, 19)], orangeDark, dy: dy)
        rows([(14, 15, 17), (15, 15, 17), (16, 15, 16)], orange, dy: dy)
    }

    func belly(dy: Int, expanded: Bool) {
        rows([
            (15, 8, 15), (16, 7, 16),
            (17, expanded ? 7 : 8, expanded ? 16 : 15)
        ], cream, dy: dy)
        rows([(18, 9, 14)], creamShade, dy: dy)
    }

    func face(dy: Int, eyesClosed: Bool) {
        if eyesClosed {
            pixel(7, 10 + dy, eye, width: 2)
            pixel(15, 10 + dy, eye, width: 2)
        } else {
            pixel(7, 9 + dy, eye, width: 2, height: 2)
            pixel(15, 9 + dy, eye, width: 2, height: 2)
            pixel(7, 9 + dy, eyeHighlight)
            pixel(15, 9 + dy, eyeHighlight)
        }
        pixel(11, 12 + dy, pink, width: 2)
        pixel(11, 13 + dy, pinkDark)
    }

    func feet(
        left: ClosedRange<Int>?,
        right: ClosedRange<Int>?,
        raisedLeft: Bool = false,
        raisedRight: Bool = false
    ) {
        if let left {
            pixel(left.lowerBound, raisedLeft ? 19 : 20, pink, width: left.upperBound - left.lowerBound + 1)
        }
        if let right {
            pixel(right.lowerBound, raisedRight ? 19 : 20, pink, width: right.upperBound - right.lowerBound + 1)
        }
    }

    func upright(
        lift: Int = 0,
        expandedBelly: Bool = false,
        eyesClosed: Bool = false,
        faceDrop: Int = 0,
        leftFoot: ClosedRange<Int>? = 7...8,
        rightFoot: ClosedRange<Int>? = 15...16,
        raisedLeft: Bool = false,
        raisedRight: Bool = false
    ) {
        let dy = -lift
        body(dy: dy)
        ears(dy: dy)
        calico(dy: dy)
        belly(dy: dy, expanded: expandedBelly)
        face(dy: dy + faceDrop, eyesClosed: eyesClosed)
        feet(left: leftFoot, right: rightFoot, raisedLeft: raisedLeft, raisedRight: raisedRight)
    }

    func offline(expandedBelly: Bool) {
        rows([
            (9, 6, 17), (10, 4, 19), (11, 3, 20), (12, 3, 20),
            (13, 3, 20), (14, 4, 19), (15, 5, 18), (16, 5, 18),
            (17, 6, 17), (18, 6, 17), (19, 7, 16), (20, 7, 16)
        ], outline)
        rows([
            (10, 7, 16), (11, 5, 18), (12, 4, 19), (13, 4, 19),
            (14, 5, 18), (15, 6, 17), (16, 6, 17), (17, 7, 16),
            (18, 7, 16), (19, 8, 15)
        ], cream)
        rows([(9, 5, 6), (10, 5, 6), (9, 17, 18), (10, 17, 18)], outline)
        pixel(5, 10, pinkDark)
        pixel(18, 10, pinkDark)
        rows([(11, 4, 9), (12, 4, 9), (13, 4, 8), (14, 5, 8), (15, 6, 8)], brownDark)
        rows([(12, 6, 9), (13, 6, 8), (14, 6, 8)], brown)
        rows([(10, 15, 18), (11, 14, 19), (12, 15, 19), (13, 16, 19), (14, 16, 18)], orangeDark)
        rows([(11, 15, 18), (12, 16, 18), (13, 17, 18)], orange)
        rows([(16, 5, 8), (17, 6, 8), (18, 6, 8)], brownDark)
        rows([(15, 15, 18), (16, 15, 18), (17, 15, 17), (18, 15, 17)], orangeDark)
        rows([(12, 8, 15), (13, 7, 16), (14, 8, 15), (15, 9, 14)], cream)
        pixel(7, 13, eye, width: 2)
        pixel(15, 13, eye, width: 2)
        pixel(11, 14, pink, width: 2)
        pixel(11, 15, pinkDark)
        pixel(expandedBelly ? 5 : 6, 17, cream, width: expandedBelly ? 14 : 12)
        pixel(7, 18, creamShade, width: 10)
        pixel(8, 20, pink)
        pixel(15, 20, pink)
    }

    switch pose {
    case .idle(let breath):
        upright(expandedBelly: breath == 1)
    case .walk(let step):
        switch step {
        case 0: upright(leftFoot: 6...7, rightFoot: 15...16)
        case 1: upright(lift: 1, leftFoot: 7...7, rightFoot: 15...16, raisedRight: true)
        case 2: upright(leftFoot: 7...8, rightFoot: 17...18)
        default: upright(lift: 1, leftFoot: 7...8, rightFoot: 17...17, raisedLeft: true)
        }
    case .doze(let nod):
        upright(eyesClosed: true, faceDrop: nod)
    case .offline(let breath):
        offline(expandedBelly: breath == 1)
    }
}

private func drawMonkey(pose: Pose, palette p: Palette, canvas c: PixelCanvas) {
    let eyesClosed: Bool
    let curled: Bool
    let lift: Int
    let step: Int
    switch pose {
    case .idle(let breath): eyesClosed = false; curled = false; lift = breath; step = 0
    case .walk(let phase): eyesClosed = false; curled = false; lift = phase.isMultiple(of: 2) ? 0 : 1; step = phase
    case .doze(let nod): eyesClosed = true; curled = false; lift = -nod; step = 0
    case .offline(let breath): eyesClosed = true; curled = true; lift = breath; step = 0
    }

    if curled {
        c.rows([(3, 6, 17), (4, 4, 19), (5, 3, 20), (6, 2, 21), (7, 2, 21),
                (8, 3, 20), (9, 4, 19), (10, 6, 17)], p.outline)
        c.pixel(1, 6, p.outline, width: 3, height: 3)
        c.pixel(20, 6, p.outline, width: 3, height: 3)
        c.rows([(4, 7, 16), (5, 5, 18), (6, 4, 19), (7, 4, 19),
                (8, 5, 18), (9, 7, 16)], p.primary, yOffset: lift)
        c.rows([(5, 7, 16), (6, 6, 17), (7, 7, 16), (8, 9, 14)], p.cream, yOffset: lift)
        c.pixel(6, 7 + lift, p.outline, width: 3)
        c.pixel(15, 7 + lift, p.outline, width: 3)
        c.pixel(11, 5 + lift, p.cheek, width: 2)
        c.pixel(17, 5, p.accentShadow, width: 3)
        return
    }

    // One near-circular silhouette keeps the oversized approved head/body ratio.
    c.rows([(3, 6, 9), (3, 15, 18)], p.outline)
    c.rows([(4, 3, 20), (5, 2, 21), (6, 2, 21),
            (7, 1, 22), (8, 1, 22), (9, 2, 21), (10, 2, 21),
            (11, 0, 23), (12, 0, 23), (13, 0, 23), (14, 2, 21),
            (15, 3, 20), (16, 3, 20), (17, 4, 19), (18, 4, 19),
            (19, 5, 18), (20, 6, 17)], p.outline, yOffset: lift)
    c.rows([(21, 7, 9), (21, 11, 12), (21, 14, 16)], p.outline, yOffset: lift)
    c.rows([(4, 5, 18), (5, 3, 20), (6, 3, 20), (7, 2, 21),
            (8, 2, 21), (9, 3, 20), (10, 3, 20), (11, 3, 20),
            (12, 3, 20), (13, 3, 20), (14, 3, 20), (15, 4, 19),
            (16, 4, 19), (17, 5, 18), (18, 5, 18), (19, 6, 17),
            (20, 7, 16), (21, 8, 9), (21, 11, 12), (21, 14, 15)], p.primary, yOffset: lift)

    // Wide peach ears and a large heart-shaped face mask match the concept.
    c.rows([(11, 1, 4), (12, 1, 4), (13, 1, 4), (14, 3, 5),
            (11, 19, 22), (12, 19, 22), (13, 19, 22), (14, 18, 20)], p.light, yOffset: lift)
    c.rows([(12, 2, 3), (13, 2, 3), (12, 20, 21), (13, 20, 21)], p.primary, yOffset: lift)
    c.rows([(8, 8, 15), (9, 6, 17), (10, 5, 18), (11, 5, 18),
            (12, 5, 18), (13, 5, 18), (14, 5, 18), (15, 6, 17),
            (16, 6, 10), (16, 13, 17), (17, 7, 9), (17, 14, 16)], p.cream, yOffset: lift)

    if eyesClosed {
        c.pixel(7, 13 + lift, p.outline, width: 3)
        c.pixel(14, 13 + lift, p.outline, width: 3)
    } else {
        c.pixel(7, 13 + lift, p.outline, width: 2, height: 2)
        c.pixel(15, 13 + lift, p.outline, width: 2, height: 2)
        c.pixel(7, 14 + lift, p.cream)
        c.pixel(15, 14 + lift, p.cream)
    }
    c.pixel(11, 11 + lift, p.cheek, width: 3)
    c.pixel(12, 10 + lift, p.cheek)

    c.pixel(3, 7 + lift, p.accent, width: 18, height: 2)
    c.pixel(4, 7 + lift, p.accentShadow, width: 16)
    c.rows([(7, 15, 19), (6, 15, 19), (5, 15, 18), (4, 15, 17)], p.accent, yOffset: lift)
    c.rows([(6, 18, 19), (5, 17, 18), (4, 17, 17)], p.accentShadow, yOffset: lift)

    let leftFoot = [6, 7, 8, 7][step]
    let rightFoot = [15, 15, 14, 14][step]
    c.pixel(leftFoot, 3, p.cream, width: 3)
    c.pixel(rightFoot, 3, p.cream, width: 3)
}

private func drawChinchilla(pose: Pose, palette p: Palette, canvas c: PixelCanvas) {
    let eyesClosed: Bool
    let curled: Bool
    let lift: Int
    let step: Int
    switch pose {
    case .idle(let breath): eyesClosed = false; curled = false; lift = breath; step = 0
    case .walk(let phase): eyesClosed = false; curled = false; lift = phase.isMultiple(of: 2) ? 0 : 1; step = phase
    case .doze(let nod): eyesClosed = true; curled = false; lift = -nod; step = 0
    case .offline(let breath): eyesClosed = true; curled = true; lift = breath; step = 0
    }

    if curled {
        c.rows([(3, 5, 18), (4, 3, 20), (5, 2, 21), (6, 1, 22), (7, 1, 22),
                (8, 2, 21), (9, 3, 20), (10, 5, 18)], p.outline)
        c.pixel(0, 6, p.outline, width: 4, height: 3)
        c.pixel(20, 6, p.outline, width: 4, height: 3)
        c.rows([(4, 6, 17), (5, 4, 19), (6, 3, 20), (7, 3, 20),
                (8, 4, 19), (9, 6, 17)], p.primary, yOffset: lift)
        c.rows([(5, 7, 16), (6, 6, 17), (7, 8, 15)], p.cream, yOffset: lift)
        c.pixel(6, 7 + lift, p.outline, width: 3)
        c.pixel(15, 7 + lift, p.outline, width: 3)
        c.pixel(11, 5 + lift, p.cheek, width: 2, height: 2)
        c.pixel(17, 5, p.accentShadow, width: 3)
        return
    }

    c.rows([(3, 6, 8), (3, 15, 17)], p.outline)
    c.rows([(4, 4, 19), (5, 3, 20), (6, 2, 21), (7, 2, 21), (8, 2, 21),
            (9, 2, 21), (10, 3, 20), (11, 3, 20), (12, 4, 19)], p.outline, yOffset: lift)
    c.rows([(5, 5, 18), (6, 4, 19), (7, 3, 20), (8, 3, 20), (9, 3, 20),
            (10, 4, 19), (11, 5, 18)], p.primary, yOffset: lift)
    c.rows([(4, 9, 14), (5, 8, 15), (6, 7, 16), (7, 7, 16), (8, 8, 15)], p.cream, yOffset: lift)
    // Chinchilla identity comes from the oversized round layered ears in the
    // reference, not a koala-style oval nose or compact bear ears.
    c.rows([(12, 1, 5), (13, 0, 7), (14, 0, 8), (15, 0, 8), (16, 1, 8),
            (17, 1, 8), (18, 2, 8), (19, 3, 7), (20, 4, 6),
            (12, 18, 22), (13, 16, 23), (14, 15, 23), (15, 15, 23),
            (16, 15, 22), (17, 15, 22), (18, 15, 21), (19, 16, 20),
            (20, 17, 19)], p.outline, yOffset: lift)
    c.rows([(13, 1, 6), (14, 1, 7), (15, 1, 7), (16, 2, 7),
            (17, 2, 7), (18, 3, 7), (19, 4, 6),
            (13, 17, 22), (14, 16, 22), (15, 16, 22), (16, 16, 21),
            (17, 16, 21), (18, 16, 20), (19, 17, 19)], p.light, yOffset: lift)
    c.rows([(14, 2, 5), (15, 2, 5), (16, 2, 5), (17, 3, 6), (18, 4, 6),
            (14, 19, 22), (15, 19, 22), (16, 19, 22), (17, 17, 20),
            (18, 17, 19)], p.shadow, yOffset: lift)
    c.rows([(11, 5, 18), (12, 4, 19), (13, 4, 19), (14, 5, 18),
            (15, 5, 18), (16, 6, 17), (17, 6, 17), (18, 7, 16),
            (19, 8, 15)], p.outline, yOffset: lift)
    c.rows([(12, 6, 17), (13, 5, 18), (14, 5, 18), (15, 6, 17),
            (16, 7, 16), (17, 8, 15), (18, 9, 14)], p.primary, yOffset: lift)
    c.pixel(8, 19 + lift, p.shadow, width: 8)

    if eyesClosed {
        c.pixel(7, 14 + lift, p.outline, width: 3)
        c.pixel(14, 14 + lift, p.outline, width: 3)
    } else {
        c.pixel(8, 14 + lift, p.outline, width: 2, height: 2)
        c.pixel(15, 14 + lift, p.outline, width: 2, height: 2)
        c.pixel(8, 15 + lift, p.cream)
        c.pixel(15, 15 + lift, p.cream)
    }
    c.rows([(11, 9, 14), (12, 8, 15), (13, 9, 14)], p.cream, yOffset: lift)
    c.pixel(11, 12 + lift, p.cheek, width: 2, height: 2)
    c.pixel(12, 11 + lift, p.shadow, width: 2)
    c.pixel(3, 8 + lift, p.accent, width: 18, height: 2)
    c.pixel(17, 6 + lift, p.accentShadow, width: 4, height: 3)
    c.pixel(2, 6 + lift, p.shadow, width: 3, height: 3)
    c.pixel(19, 6 + lift, p.shadow, width: 3, height: 3)
    let leftFoot = [5, 7, 7, 5][step]
    let rightFoot = [15, 15, 13, 13][step]
    c.pixel(leftFoot, 3, p.cheek, width: 3)
    c.pixel(rightFoot, 3, p.cheek, width: 3)
}

private func drawStarlightUpalupa(
    pose: Pose,
    palette: Palette,
    headOffset: Int,
    footShift: Int,
    eyesClosed: Bool,
    curled: Bool,
    pixel: (Int, Int, CGColor, Int, Int) -> Void,
    rows: ([(Int, Int, Int)], CGColor, Int) -> Void
) {
    let mint = palette.accentShadow
    let lavender = palette.accent
    let gold = rgb(0.96, 0.73, 0.22)
    let dimGold = rgb(0.57, 0.43, 0.25)

    if curled {
        // Offline sleep is still a front view: a low, soft puddle with closed
        // eyes, folded gills and the one directional tail behind the body.
        rows([(4, 0, 7), (5, 0, 9), (6, 1, 10), (7, 3, 10)], palette.outline, 0)
        rows([(5, 1, 8), (6, 2, 9)], palette.primary, 0)
        pixel(0, 5, mint, 1, 1)

        rows([(3, 7, 17), (4, 5, 19), (5, 4, 20), (6, 4, 20),
              (7, 5, 19), (8, 7, 17)], palette.outline, 0)
        rows([(4, 8, 16), (5, 6, 18), (6, 5, 19), (7, 7, 17)], palette.primary, 0)
        rows([(4, 10, 14), (5, 9, 15), (6, 10, 14)], palette.cream, 0)

        rows([(8, 0, 5), (10, 0, 5), (12, 1, 6),
              (8, 18, 23), (10, 18, 23), (12, 17, 22)], palette.outline, headOffset)
        rows([(8, 1, 5), (10, 1, 5), (12, 2, 6),
              (8, 18, 22), (10, 18, 22), (12, 17, 21)], lavender, headOffset)
        pixel(0, 8 + headOffset, mint, 1, 1)
        pixel(0, 10 + headOffset, mint, 1, 1)
        pixel(1, 12 + headOffset, mint, 1, 1)
        pixel(23, 8 + headOffset, mint, 1, 1)
        pixel(23, 10 + headOffset, mint, 1, 1)
        pixel(22, 12 + headOffset, mint, 1, 1)

        rows([(7, 5, 19), (8, 4, 20), (9, 3, 21), (10, 3, 21),
              (11, 3, 21), (12, 4, 20), (13, 5, 19), (14, 7, 17)], palette.outline, headOffset)
        rows([(8, 6, 18), (9, 5, 19), (10, 4, 20), (11, 4, 20),
              (12, 5, 19), (13, 7, 17)], palette.primary, headOffset)
        rows([(12, 7, 17), (13, 9, 15)], palette.light, headOffset)
        pixel(8, 7 + headOffset, palette.primary, 9, 1)
        pixel(7, 10 + headOffset, palette.outline, 3, 1)
        pixel(15, 10 + headOffset, palette.outline, 3, 1)
        pixel(12, 8 + headOffset, palette.outline, 1, 1)
        pixel(6, 9 + headOffset, palette.cheek, 2, 1)
        pixel(17, 9 + headOffset, palette.cheek, 2, 1)
        pixel(11, 5, dimGold, 3, 1)
        pixel(12, 4, dimGold, 1, 3)
        return
    }

    // The face stays front-facing. Only the asymmetric tail gives the sheet a
    // movement direction, so runtime mirroring reads as a tail-direction swap
    // instead of turning the character into a side profile.
    let tailWave: Int
    switch pose {
    case .idle(let breath): tailWave = breath
    case .walk(let step): tailWave = [0, 1, 0, -1][step]
    case .doze: tailWave = -1
    case .offline: tailWave = 0
    }
    rows([(4 + tailWave, 0, 6), (5 + tailWave, 0, 8),
          (6 + tailWave, 1, 9), (7 + tailWave, 2, 10),
          (8 + tailWave, 4, 11), (9 + tailWave, 6, 11)], palette.outline, 0)
    rows([(5 + tailWave, 1, 7), (6 + tailWave, 2, 8),
          (7 + tailWave, 3, 9), (8 + tailWave, 5, 10)], palette.primary, 0)
    pixel(0, 5 + tailWave, mint, 1, 1)

    // The compact pear body flows directly into the head. Removing the old
    // horizontal neck line makes this read as an axolotl instead of a doll.
    rows([(4, 7, 17), (5, 6, 18), (6, 5, 19), (7, 5, 19),
          (8, 6, 18), (9, 7, 17), (10, 8, 16)], palette.outline, headOffset)
    rows([(5, 8, 16), (6, 7, 17), (7, 6, 18), (8, 7, 17),
          (9, 8, 16), (10, 9, 15)], palette.primary, headOffset)
    rows([(5, 10, 14), (6, 9, 15), (7, 9, 15), (8, 10, 14)], palette.cream, headOffset)

    // Symmetric three-branch external gills frame the front-facing head.
    // Mint tips make them readable at the normal 2x nearest-neighbor scale.
    let gillDrop = eyesClosed ? -1 : 0
    let gillOffset = headOffset + gillDrop
    rows([(12, 0, 4), (13, 1, 5), (15, 0, 5), (16, 1, 5), (18, 1, 5), (19, 2, 6),
          (12, 19, 23), (13, 18, 22), (15, 18, 23), (16, 18, 22),
          (18, 18, 22), (19, 17, 21)], palette.outline, gillOffset)
    rows([(13, 1, 4), (16, 1, 4), (19, 2, 5),
          (13, 19, 22), (16, 19, 22), (19, 18, 21)], lavender, gillOffset)
    pixel(0, 12 + gillOffset, mint, 1, 1)
    pixel(0, 15 + gillOffset, mint, 1, 1)
    pixel(1, 18 + gillOffset, mint, 1, 1)
    pixel(23, 12 + gillOffset, mint, 1, 1)
    pixel(23, 15 + gillOffset, mint, 1, 1)
    pixel(22, 18 + gillOffset, mint, 1, 1)

    rows([(10, 6, 18), (11, 4, 20), (12, 3, 21), (13, 3, 21),
          (14, 3, 21), (15, 3, 21), (16, 3, 21), (17, 4, 20),
          (18, 5, 19), (19, 7, 17), (20, 9, 15)], palette.outline, headOffset)
    rows([(11, 6, 18), (12, 5, 19), (13, 4, 20), (14, 4, 20),
          (15, 4, 20), (16, 4, 20), (17, 5, 19), (18, 7, 17),
          (19, 9, 15)], palette.primary, headOffset)
    rows([(17, 7, 17), (18, 9, 15), (19, 10, 14)], palette.light, headOffset)

    // Bridge the head into the torso so the lower cheek outline curves inward
    // instead of cutting a straight neck across the character.
    pixel(9, 10 + headOffset, palette.primary, 7, 1)

    if eyesClosed {
        pixel(7, 14 + headOffset, palette.outline, 3, 1)
        pixel(15, 14 + headOffset, palette.outline, 3, 1)
    } else {
        pixel(7, 14 + headOffset, palette.outline, 2, 2)
        pixel(16, 14 + headOffset, palette.outline, 2, 2)
        pixel(7, 15 + headOffset, palette.cream, 1, 1)
        pixel(16, 15 + headOffset, palette.cream, 1, 1)
    }
    pixel(10, 12 + headOffset, palette.outline, 1, 1)
    pixel(14, 12 + headOffset, palette.outline, 1, 1)
    pixel(11, 11 + headOffset, palette.outline, 3, 1)
    pixel(6, 12 + headOffset, palette.cheek, 2, 1)
    pixel(17, 12 + headOffset, palette.cheek, 2, 1)

    // Centering the star keeps mirroring visually neutral; the tail is the
    // only obvious left/right feature.
    let ornament = eyesClosed ? dimGold : gold
    pixel(11, 7 + headOffset, ornament, 3, 1)
    pixel(12, 6 + headOffset, ornament, 1, 3)

    let leftFootX = footShift == 0 || footShift == 3 ? 6 : 8
    let rightFootX = footShift == 1 || footShift == 2 ? 16 : 14
    pixel(leftFootX, 3, palette.cheek, 3, 1)
    pixel(rightFootX, 3, palette.cheek, 3, 1)
}

private func exportWindowsRuntimeAsset(species: Species, pngURL: URL) throws {
    let windowsDirectory = repositoryRoot
        .appendingPathComponent("windows/src/Sidey.Overlay/Assets/Characters")
    try FileManager.default.createDirectory(at: windowsDirectory, withIntermediateDirectories: true)
    let pngData = try Data(contentsOf: pngURL)
    try pngData.write(
        to: windowsDirectory.appendingPathComponent("\(species.rawValue).png"),
        options: .atomic
    )

    guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("Could not decode \(species.rawValue) for Windows") }
    var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
    rgba.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { fatalError("Could not create Windows conversion context") }
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    var bgra = rgba
    for index in stride(from: 0, to: bgra.count, by: 4) {
        bgra[index] = rgba[index + 2]
        bgra[index + 1] = rgba[index + 1]
        bgra[index + 2] = rgba[index]
        bgra[index + 3] = rgba[index + 3]
    }
    try Data(bgra).write(
        to: windowsDirectory.appendingPathComponent("\(species.rawValue).bgra"),
        options: .atomic
    )
    print("Generated Windows PNG and BGRA for \(species.rawValue)")
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: 1)
}
