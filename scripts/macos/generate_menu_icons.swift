#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("macos/SIDEY/Resources/Assets.xcassets")

for unread in [false, true] {
    let name = unread ? "SideyMenuIconUnread" : "SideyMenuIcon"
    let directory = root.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for scale in [1, 2] {
        try drawIcon(
            scale: scale,
            unread: unread,
            outputURL: directory.appendingPathComponent("sidey-menu-\(unread ? "unread-" : "")\(scale)x.png")
        )
    }
}

private func drawIcon(scale: Int, unread: Bool, outputURL: URL) throws {
    let logicalSize = 18
    let verticalOffset = -2
    let size = logicalSize * scale
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create menu icon context") }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(CGColor(gray: 0, alpha: 1))

    func pixel(_ x: Int, _ y: Int, width: Int = 1, height: Int = 1) {
        context.fill(CGRect(
            x: x * scale,
            y: (y + verticalOffset) * scale,
            width: width * scale,
            height: height * scale
        ))
    }

    func clearPixel(_ x: Int, _ y: Int, width: Int = 1, height: Int = 1) {
        context.setBlendMode(.clear)
        pixel(x, y, width: width, height: height)
        context.setBlendMode(.normal)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
    }

    // A soft filled silhouette survives macOS's 18pt template rendering much
    // better than a one-pixel outline. Opaque facial pixels stay legible in
    // both light and dark menu bars because the image remains a template.
    context.setFillColor(CGColor(gray: 0, alpha: 0.34))
    pixel(2, 13, width: 4, height: 3)
    pixel(12, 13, width: 4, height: 3)
    pixel(4, 11, width: 10, height: 3)
    pixel(3, 6, width: 12, height: 5)
    pixel(2, 7, width: 14, height: 3)
    pixel(3, 4, width: 12, height: 2)
    pixel(5, 3, width: 8)

    context.setFillColor(CGColor(gray: 0, alpha: 1))
    pixel(3, 14)
    pixel(14, 14)
    pixel(6, 9, height: 2)
    pixel(11, 9, height: 2)
    pixel(8, 7, width: 2)
    context.setFillColor(CGColor(gray: 0, alpha: 0.68))
    pixel(3, 7)
    pixel(14, 7)
    context.setFillColor(CGColor(gray: 0, alpha: 1))

    if unread {
        clearPixel(14, 14, width: 4, height: 4)
        pixel(15, 15, width: 3, height: 3)
    }

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              outputURL as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          )
    else { fatalError("Could not create menu icon PNG") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not finalize menu icon PNG") }
    print("Generated \(outputURL.path)")
}
