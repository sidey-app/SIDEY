import Foundation
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, frameCount, duration) in [("hamster-stun-orbit-v2.gif", 72, 2.4), ("hamster-stun-timeline-v2.gif", 216, 7.2)] {
    let source = CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL, nil)!
    precondition(CGImageSourceGetCount(source) == frameCount)
    var total = 0.0
    var stunned = 0.0
    for index in 0..<frameCount {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)! as NSDictionary
        let gif = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as! Double
        total += delay
        if name.contains("timeline") && (18..<198).contains(index) { stunned += delay }
        let image = CGImageSourceCreateImageAtIndex(source, index, nil)!
        precondition(image.width == 384 && image.height == 252)
    }
    precondition(abs(total - duration) < 0.001)
    if name.contains("timeline") { precondition(abs(stunned - 6) < 0.001) }
    print("PASS: \(name), \(frameCount) frames, \(String(format: "%.2f", total)) seconds")
}
for (name, width, height) in [("star-v1.png", 7, 7), ("ring-v2.png", 23, 11), ("hamster-stun-frame-8-v2.png", 64, 42), ("hamster-stun-frame-9-v2.png", 64, 42)] {
    let source = CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(image.width == width && image.height == height && image.bitsPerComponent == 8)
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let alphas = Set((0..<(width * height)).map { bytes[$0 * 4 + 3] })
    precondition(alphas == Set([UInt8(0), UInt8(255)]))
    print("PASS: \(name), \(width)×\(height), hard alpha")
}
