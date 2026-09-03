#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceRoot = root.appendingPathComponent("shared/character-throw/v1")
let outputRoot = root.appendingPathComponent("windows/src/Sidey.Overlay/Assets/CharacterThrow")
let groups = ["action-sheets", "object-sheets"]

try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

for group in groups {
    let sourceDirectory = sourceRoot.appendingPathComponent(group)
    let outputDirectory = outputRoot.appendingPathComponent(group)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let files = try FileManager.default.contentsOfDirectory(
        at: sourceDirectory,
        includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    for sourceURL in files {
        let pngData = try Data(contentsOf: sourceURL)
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { fatalError("Could not decode \(sourceURL.path)") }

        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue)
            else { fatalError("Could not create conversion context") }
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

        let pngOutput = outputDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        let bgraOutput = outputDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".bgra")
        try pngData.write(to: pngOutput, options: .atomic)
        try Data(bgra).write(to: bgraOutput, options: .atomic)
        print("Generated \(group)/\(bgraOutput.lastPathComponent)")
    }
}
