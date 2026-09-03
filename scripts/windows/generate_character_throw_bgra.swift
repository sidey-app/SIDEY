#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceRoot = root.appendingPathComponent("assets/v1")
let outputRoot = root.appendingPathComponent("windows/src/Sidey.Overlay/Assets/CharacterThrow")

struct AssetManifest: Decodable {
    struct Source: Decodable { let path: String }
    struct Character: Decodable { let id: String; let throwHit: Source }
    struct Throwable: Decodable { let id: String; let sprite: Source }
    let characters: [Character]
    let throwables: [Throwable]

    enum CodingKeys: String, CodingKey {
        case characters, throwables
    }
}

let manifestData = try Data(contentsOf: sourceRoot.appendingPathComponent("manifest.json"))
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let manifest = try decoder.decode(AssetManifest.self, from: manifestData)
let assets = manifest.characters.map {
    (sourceRoot.appendingPathComponent($0.throwHit.path), "action-sheets", "\($0.id)_throw_hit")
} + manifest.throwables.map {
    (sourceRoot.appendingPathComponent($0.sprite.path), "object-sheets", $0.id)
}

try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

for (sourceURL, group, outputName) in assets {
    let outputDirectory = outputRoot.appendingPathComponent(group)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
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

    let pngOutput = outputDirectory.appendingPathComponent(outputName + ".png")
    let bgraOutput = outputDirectory.appendingPathComponent(outputName + ".bgra")
    try pngData.write(to: pngOutput, options: .atomic)
    try Data(bgra).write(to: bgraOutput, options: .atomic)
    print("Generated \(group)/\(bgraOutput.lastPathComponent)")
}
