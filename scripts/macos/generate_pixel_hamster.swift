#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let frameSize = 24
private let frameCount = 8
private let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "macos/SIDEY/Resources/Characters/PixelHamster/pixel_hamster.png")

private struct Palette {
    static let gold = CGColor(red: 0.91, green: 0.58, blue: 0.20, alpha: 1)
    static let goldLight = CGColor(red: 0.98, green: 0.72, blue: 0.31, alpha: 1)
    static let goldShadow = CGColor(red: 0.67, green: 0.36, blue: 0.14, alpha: 1)
    static let cream = CGColor(red: 1.00, green: 0.91, blue: 0.72, alpha: 1)
    static let creamShadow = CGColor(red: 0.93, green: 0.77, blue: 0.56, alpha: 1)
    static let cocoa = CGColor(red: 0.24, green: 0.12, blue: 0.10, alpha: 1)
    static let pink = CGColor(red: 0.94, green: 0.48, blue: 0.48, alpha: 1)
    static let periwinkle = CGColor(red: 0.45, green: 0.49, blue: 0.85, alpha: 1)
    static let periwinkleShadow = CGColor(red: 0.31, green: 0.34, blue: 0.68, alpha: 1)
}

private enum Pose {
    case idle(bob: Int)
    case walk(step: Int)
    case sleep(breath: Int)
}

guard let context = CGContext(
    data: nil,
    width: frameSize * frameCount,
    height: frameSize,
    bitsPerComponent: 8,
    bytesPerRow: frameSize * frameCount * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create pixel-hamster bitmap context")
}
context.setShouldAntialias(false)
context.interpolationQuality = .none
context.clear(CGRect(x: 0, y: 0, width: frameSize * frameCount, height: frameSize))

private let poses: [Pose] = [
    .idle(bob: 0), .idle(bob: 1),
    .walk(step: 0), .walk(step: 1), .walk(step: 2), .walk(step: 3),
    .sleep(breath: 0), .sleep(breath: 1)
]

for (frame, pose) in poses.enumerated() {
    drawHamster(in: context, frame: frame, pose: pose)
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      )
else {
    fatalError("Could not create pixel-hamster PNG destination")
}
CGImageDestinationAddImage(destination, image, [
    kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: 0]
] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not finalize pixel-hamster PNG")
}

private func drawHamster(in context: CGContext, frame: Int, pose: Pose) {
    let originX = frame * frameSize
    let bob: Int
    let step: Int?
    let sleeping: Bool
    switch pose {
    case .idle(let value):
        bob = value
        step = nil
        sleeping = false
    case .walk(let value):
        bob = value.isMultiple(of: 2) ? 0 : 1
        step = value
        sleeping = false
    case .sleep(let breath):
        bob = -breath
        step = nil
        sleeping = true
    }

    func pixel(_ x: Int, _ y: Int, _ color: CGColor, width: Int = 1, height: Int = 1) {
        context.setFillColor(color)
        context.fill(CGRect(x: originX + x, y: y + bob, width: width, height: height))
    }

    func rows(_ ranges: [(Int, Int, Int)], _ color: CGColor) {
        for (y, start, end) in ranges {
            pixel(start, y, color, width: end - start + 1)
        }
    }

    // One-pixel cocoa silhouette keeps the 48pt render legible without a
    // heavy cartoon outline.
    rows([
        (5, 6, 17), (6, 4, 19), (7, 3, 20), (8, 3, 20),
        (9, 2, 21), (10, 2, 21), (11, 2, 21), (12, 2, 21),
        (13, 3, 20), (14, 3, 20), (15, 4, 19), (16, 4, 19),
        (17, 5, 18), (18, 5, 8), (18, 15, 18),
        (19, 5, 8), (19, 15, 18), (20, 6, 7), (20, 16, 17)
    ], Palette.cocoa)

    rows([
        (6, 6, 17), (7, 5, 18), (8, 4, 19), (9, 3, 20),
        (10, 3, 20), (11, 3, 20), (12, 3, 20), (13, 4, 19),
        (14, 4, 19), (15, 5, 18), (16, 5, 18), (17, 6, 17),
        (18, 6, 7), (18, 16, 17), (19, 6, 7), (19, 16, 17)
    ], Palette.gold)
    rows([(14, 6, 17), (15, 7, 16), (16, 8, 15), (17, 9, 14)], Palette.goldLight)
    rows([(7, 5, 18), (8, 4, 5), (8, 18, 19), (9, 3, 4), (9, 19, 20)], Palette.goldShadow)

    // Cream muzzle and belly.
    rows([
        (10, 6, 17), (11, 5, 18), (12, 5, 18), (13, 6, 17),
        (7, 8, 15), (8, 7, 16), (9, 7, 16)
    ], Palette.cream)
    rows([(7, 8, 9), (7, 14, 15), (8, 7, 7), (8, 16, 16)], Palette.creamShadow)

    // Inner ears and tiny cheek pixels.
    pixel(6, 18, Palette.pink)
    pixel(17, 18, Palette.pink)
    pixel(5, 11, Palette.pink)
    pixel(18, 11, Palette.pink)

    if sleeping {
        pixel(7, 13, Palette.cocoa, width: 3)
        pixel(14, 13, Palette.cocoa, width: 3)
    } else {
        pixel(8, 13, Palette.cocoa, width: 2, height: 2)
        pixel(14, 13, Palette.cocoa, width: 2, height: 2)
        pixel(8, 14, Palette.cream)
        pixel(14, 14, Palette.cream)
    }
    pixel(11, 11, Palette.pink, width: 2)
    pixel(10, 10, Palette.cocoa)
    pixel(13, 10, Palette.cocoa)
    pixel(11, 9, Palette.cocoa, width: 2)

    // Small periwinkle accent, deliberately subordinate to the face.
    pixel(4, 9, Palette.periwinkle, width: 16)
    pixel(5, 8, Palette.periwinkle, width: 14)
    pixel(17, 7, Palette.periwinkleShadow, width: 2)

    let leftFootX: Int
    let rightFootX: Int
    if let step {
        leftFootX = step == 0 || step == 3 ? 5 : 7
        rightFootX = step == 1 || step == 2 ? 16 : 14
    } else {
        leftFootX = 6
        rightFootX = 15
    }
    pixel(leftFootX, 4, Palette.pink, width: 3)
    pixel(rightFootX, 4, Palette.pink, width: 3)
}
