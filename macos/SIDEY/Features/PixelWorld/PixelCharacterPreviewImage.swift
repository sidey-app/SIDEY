import AppKit

@MainActor
enum PixelCharacterPreviewImage {
    private static var cache: [String: NSImage] = [:]

    static func image(for definition: PixelCharacterDefinition) -> NSImage {
        if let cached = cache[definition.id] { return cached }
        guard let url = definition.assetURL(),
              let source = NSImage(contentsOf: url),
              let sheet = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let frame = sheet.cropping(to: CGRect(
                  x: definition.previewFrame * Int(PixelCharacterCatalog.framePixelSize.width),
                  y: 0,
                  width: Int(PixelCharacterCatalog.framePixelSize.width),
                  height: Int(PixelCharacterCatalog.framePixelSize.height)
              ))
        else {
            return NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: definition.displayName
            ) ?? NSImage(size: NSSize(width: 24, height: 24))
        }
        let image = NSImage(cgImage: frame, size: NSSize(width: 24, height: 24))
        image.isTemplate = false
        cache[definition.id] = image
        return image
    }
}
