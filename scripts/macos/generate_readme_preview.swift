#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO

private enum PreviewError: LocalizedError {
    case invalidArguments
    case missingAsset(URL)
    case invalidAsset(URL)
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: generate_readme_preview.swift /path/to/repository /path/to/preview.png"
        case let .missingAsset(url):
            return "Missing preview asset: \(url.path)"
        case let .invalidAsset(url):
            return "Expected a 240×24, ten-frame character sheet: \(url.path)"
        case .bitmapCreationFailed:
            return "Could not create the README preview bitmap"
        case .pngEncodingFailed:
            return "Could not encode the README preview as PNG"
        }
    }
}

private struct CharacterSpec {
    let sheetPath: String
    let nickname: String
    let frameIndex: Int
    let centerX: CGFloat
    let scale: CGFloat
    let statusColor: NSColor
    let opacity: CGFloat
    let darken: Bool
    let message: String?
    let typing: Bool
    let showsZzz: Bool
}

private let canvas = NSSize(width: 1_672, height: 941)
private let logicalFrame = NSSize(width: 24, height: 24)
private let footBaselinePixel: CGFloat = 3
private let characterPointSize: CGFloat = 48
private let presentationOriginY = characterPointSize / 2 - footBaselinePixel * 2

private let specs = [
    CharacterSpec(
        sheetPath: "macos/SIDEY/Resources/Characters/PixelHamster/pixel_hamster.png",
        nickname: "민지",
        frameIndex: 8,
        centerX: 210,
        scale: 2,
        statusColor: NSColor(srgbRed: 0.95, green: 0.23, blue: 0.28, alpha: 1),
        opacity: 0.75,
        darken: true,
        message: nil,
        typing: false,
        showsZzz: false
    ),
    CharacterSpec(
        sheetPath: "macos/SIDEY/Resources/Characters/PixelCat/pixel_cat.png",
        nickname: "도윤",
        frameIndex: 0,
        centerX: 505,
        scale: 2,
        statusColor: NSColor(srgbRed: 0.20, green: 0.82, blue: 0.43, alpha: 1),
        opacity: 1,
        darken: false,
        message: "저녁 7시에 볼까?",
        typing: false,
        showsZzz: false
    ),
    CharacterSpec(
        sheetPath: "macos/SIDEY/Resources/Characters/PixelPuppy/pixel_puppy.png",
        nickname: "하린",
        frameIndex: 6,
        centerX: 810,
        scale: 2,
        statusColor: NSColor(srgbRed: 1, green: 0.58, blue: 0.10, alpha: 1),
        opacity: 1,
        darken: false,
        message: nil,
        typing: false,
        showsZzz: true
    ),
    CharacterSpec(
        sheetPath: "macos/SIDEY/Resources/Characters/PixelRabbit/pixel_rabbit.png",
        nickname: "수아 · 나",
        frameIndex: 0,
        centerX: 1_160,
        scale: 14,
        statusColor: NSColor(srgbRed: 0.20, green: 0.82, blue: 0.43, alpha: 1),
        opacity: 1,
        darken: false,
        message: nil,
        typing: false,
        showsZzz: false
    ),
    CharacterSpec(
        sheetPath: "macos/SIDEY/Resources/Characters/PixelPenguin/pixel_penguin.png",
        nickname: "지우",
        frameIndex: 0,
        centerX: 1_485,
        scale: 2,
        statusColor: NSColor(srgbRed: 0.20, green: 0.82, blue: 0.43, alpha: 1),
        opacity: 1,
        darken: false,
        message: nil,
        typing: true,
        showsZzz: false
    ),
]

private func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func fill(_ rect: NSRect, color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    if radius > 0 {
        roundedPath(rect, radius: radius).fill()
    } else {
        rect.fill()
    }
}

private func stroke(_ rect: NSRect, color: NSColor, width: CGFloat, radius: CGFloat) {
    color.setStroke()
    let path = roundedPath(rect.insetBy(dx: width / 2, dy: width / 2), radius: radius)
    path.lineWidth = width
    path.stroke()
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    ).draw(in: rect)
}

private func textSize(_ text: String, font: NSFont) -> NSSize {
    NSAttributedString(string: text, attributes: [.font: font]).size()
}

private func wallpaperURL() -> URL? {
    let fileManager = FileManager.default
    let highResolution = URL(
        fileURLWithPath: "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.heic"
    )
    let thumbnail = URL(
        fileURLWithPath: "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon Thumbnail@2x.png"
    )
    let magickCandidates = ["/opt/homebrew/bin/magick", "/usr/local/bin/magick"]

    if fileManager.fileExists(atPath: highResolution.path),
       let magick = magickCandidates.first(where: fileManager.fileExists(atPath:))
    {
        let rendered = URL(fileURLWithPath: "/private/tmp/sidey-readme-sonoma-horizon.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: magick)
        process.arguments = [
            "\(highResolution.path)[0]",
            "-resize", "\(Int(canvas.width))x\(Int(canvas.height))^",
            "-gravity", "center",
            "-crop", "\(Int(canvas.width))x\(Int(canvas.height))+0+0",
            "+repage",
            rendered.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               fileManager.fileExists(atPath: rendered.path)
            {
                return rendered
            }
        } catch {
            // The checked-in preview remains reproducible enough with the static thumbnail fallback.
        }
    }

    return fileManager.fileExists(atPath: thumbnail.path) ? thumbnail : nil
}

private func drawWallpaper() {
    if let wallpaperURL = wallpaperURL(),
       let source = CGImageSourceCreateWithURL(wallpaperURL as CFURL, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let sourceAspect = imageWidth / imageHeight
        let targetAspect = canvas.width / canvas.height
        let crop: CGRect
        if sourceAspect > targetAspect {
            let width = imageHeight * targetAspect
            crop = CGRect(
                x: (imageWidth - width) / 2,
                y: 0,
                width: width,
                height: imageHeight
            )
        } else {
            let height = imageWidth / targetAspect
            crop = CGRect(
                x: 0,
                y: (imageHeight - height) / 2,
                width: imageWidth,
                height: height
            )
        }
        let context = NSGraphicsContext.current!.cgContext
        context.interpolationQuality = .high
        if let cropped = image.cropping(to: crop.integral) {
            context.draw(cropped, in: CGRect(origin: .zero, size: canvas))
        } else {
            context.draw(image, in: CGRect(origin: .zero, size: canvas))
        }
    } else {
        NSGradient(
            starting: NSColor(srgbRed: 0.70, green: 0.82, blue: 0.96, alpha: 1),
            ending: NSColor(srgbRed: 0.84, green: 0.47, blue: 0.72, alpha: 1)
        )?.draw(in: NSRect(origin: .zero, size: canvas), angle: -18)
    }
}

private func drawMenuBar() {
    fill(
        NSRect(x: 0, y: canvas.height - 32, width: canvas.width, height: 32),
        color: NSColor.white.withAlphaComponent(0.78)
    )
    drawText(
        "●",
        in: NSRect(x: 22, y: canvas.height - 25, width: 18, height: 20),
        font: .systemFont(ofSize: 12, weight: .semibold),
        color: NSColor.black.withAlphaComponent(0.88)
    )
    drawText(
        "SIDEY   파일   편집   보기   윈도우   도움말",
        in: NSRect(x: 52, y: canvas.height - 25, width: 520, height: 20),
        font: .systemFont(ofSize: 13, weight: .semibold),
        color: NSColor.black.withAlphaComponent(0.86)
    )
    drawText(
        "배터리  100%     Wi‑Fi     9월 1일  오전 11:20",
        in: NSRect(x: canvas.width - 440, y: canvas.height - 25, width: 415, height: 20),
        font: .systemFont(ofSize: 12, weight: .medium),
        color: NSColor.black.withAlphaComponent(0.78),
        alignment: .right
    )
}

private func drawNativeWindow() {
    let window = NSRect(x: 330, y: 330, width: 1_012, height: 500)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill(window, color: NSColor.white.withAlphaComponent(0.97), radius: 24)
    NSGraphicsContext.restoreGraphicsState()
    stroke(window, color: NSColor.black.withAlphaComponent(0.10), width: 1, radius: 24)

    let titlebarHeight: CGFloat = 52
    fill(
        NSRect(x: window.minX, y: window.maxY - titlebarHeight, width: window.width, height: titlebarHeight),
        color: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.975, alpha: 0.98),
        radius: 24
    )
    fill(
        NSRect(x: window.minX, y: window.maxY - titlebarHeight, width: window.width, height: 26),
        color: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.975, alpha: 0.98)
    )
    fill(
        NSRect(x: window.minX, y: window.maxY - titlebarHeight - 1, width: window.width, height: 1),
        color: NSColor.black.withAlphaComponent(0.07)
    )

    let traffic = [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen]
    for (index, color) in traffic.enumerated() {
        fill(
            NSRect(
                x: window.minX + 22 + CGFloat(index * 23),
                y: window.maxY - 32,
                width: 12,
                height: 12
            ),
            color: color,
            radius: 6
        )
    }

    let sidebar = NSRect(x: window.minX, y: window.minY, width: 220, height: window.height - titlebarHeight)
    fill(sidebar, color: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 0.96))
    fill(NSRect(x: sidebar.maxX, y: sidebar.minY, width: 1, height: sidebar.height), color: NSColor.black.withAlphaComponent(0.07))

    drawText(
        "iCloud",
        in: NSRect(x: sidebar.minX + 24, y: sidebar.maxY - 48, width: 150, height: 20),
        font: .systemFont(ofSize: 13, weight: .medium),
        color: NSColor.secondaryLabelColor
    )
    let sidebarRows = ["모든 iCloud", "메모", "아이디어", "최근 삭제된 항목"]
    for (index, row) in sidebarRows.enumerated() {
        let y = sidebar.maxY - 82 - CGFloat(index * 38)
        if index == 1 {
            fill(NSRect(x: sidebar.minX + 12, y: y - 5, width: sidebar.width - 24, height: 30), color: NSColor.black.withAlphaComponent(0.075), radius: 8)
        }
        drawText(
            row,
            in: NSRect(x: sidebar.minX + 28, y: y, width: 160, height: 20),
            font: .systemFont(ofSize: 14, weight: index == 1 ? .semibold : .regular),
            color: NSColor.labelColor.withAlphaComponent(0.78)
        )
    }

    drawText(
        "프로젝트 회의 메모",
        in: NSRect(x: sidebar.maxX + 42, y: window.maxY - 108, width: 470, height: 40),
        font: .systemFont(ofSize: 27, weight: .bold),
        color: NSColor.labelColor
    )
    let content = [
        "• 일정",
        "   – 9월 3일 오전 10시 킥오프",
        "   – 9월 10일 중간 리뷰",
        "",
        "• 안건",
        "   □ 요구사항 정리",
        "   □ 기술 스택 확정",
        "   □ 역할 분담",
        "",
        "• 다음 단계",
        "   – 와이어프레임 초안 작성",
        "   – 샘플 데이터 준비",
    ]
    var y = window.maxY - 156
    for line in content {
        drawText(
            line,
            in: NSRect(x: sidebar.maxX + 44, y: y, width: 520, height: 22),
            font: .systemFont(ofSize: 16, weight: line.hasPrefix("•") ? .semibold : .regular),
            color: NSColor.labelColor.withAlphaComponent(0.88)
        )
        y -= line.isEmpty ? 11 : 25
    }
}

private func characterFrame(
    sheetURL: URL,
    frameIndex: Int,
    darken: Bool
) throws -> NSImage {
    guard FileManager.default.fileExists(atPath: sheetURL.path) else {
        throw PreviewError.missingAsset(sheetURL)
    }
    guard let sheet = NSImage(contentsOf: sheetURL),
          sheet.size.width >= 240,
          sheet.size.height >= 24,
          (0..<10).contains(frameIndex)
    else {
        throw PreviewError.invalidAsset(sheetURL)
    }

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 24,
        pixelsHigh: 24,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw PreviewError.bitmapCreationFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 24, height: 24).fill()
    sheet.draw(
        in: NSRect(x: 0, y: 0, width: 24, height: 24),
        from: NSRect(x: CGFloat(frameIndex) * 24, y: 0, width: 24, height: 24),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.none]
    )
    if darken {
        NSColor.systemGray.withAlphaComponent(0.58).setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill(using: .sourceAtop)
    }
    NSGraphicsContext.restoreGraphicsState()

    let frame = NSImage(size: logicalFrame)
    frame.addRepresentation(rep)
    return frame
}

private func drawCharacter(_ spec: CharacterSpec, repositoryRoot: URL) throws {
    let frame = try characterFrame(
        sheetURL: repositoryRoot.appendingPathComponent(spec.sheetPath),
        frameIndex: spec.frameIndex,
        darken: spec.darken
    )
    let side = logicalFrame.width * spec.scale
    let transparentFootInset = footBaselinePixel * spec.scale
    frame.draw(
        in: NSRect(
            x: spec.centerX - side / 2,
            y: -transparentFootInset,
            width: side,
            height: side
        ),
        from: NSRect(origin: .zero, size: logicalFrame),
        operation: .sourceOver,
        fraction: spec.opacity,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.none]
    )
}

private func drawNameplate(_ spec: CharacterSpec) {
    let font = NSFont(name: "AppleSDGothicNeo-SemiBold", size: 11)
        ?? NSFont.systemFont(ofSize: 11, weight: .semibold)
    let measured = textSize(spec.nickname, font: font)
    let labelFrame = NSRect(
        x: spec.centerX - measured.width / 2,
        y: presentationOriginY + 32 - measured.height / 2,
        width: measured.width,
        height: measured.height
    )
    let rect = NSRect(
        x: labelFrame.minX - 4,
        y: labelFrame.minY - 2,
        width: labelFrame.width + 8,
        height: labelFrame.height + 4
    )
    fill(rect, color: NSColor(srgbRed: 0.02, green: 0.025, blue: 0.035, alpha: 0.62), radius: 6)
    fill(
        NSRect(
            x: labelFrame.minX - 5 - 6,
            y: presentationOriginY + 32 - 3,
            width: 6,
            height: 6
        ),
        color: spec.statusColor,
        radius: 3
    )
    drawText(
        spec.nickname,
        in: labelFrame,
        font: font,
        color: .white,
        alignment: .center
    )
}

private func drawBubble(text: String, centerX: CGFloat, typing: Bool) {
    let font = typing
        ? (NSFont(name: "AppleSDGothicNeo-Medium", size: 16) ?? NSFont.systemFont(ofSize: 16, weight: .medium))
        : (NSFont(name: "AppleSDGothicNeo-Medium", size: 10.5) ?? NSFont.systemFont(ofSize: 10.5, weight: .medium))
    let measured = textSize(text, font: font)
    let width = typing ? 42 : min(220, max(28, ceil(measured.width) + 16))
    let height: CGFloat = typing ? 30 : max(28, ceil(measured.height) + 14)
    let body = NSRect(
        x: centerX - width / 2,
        y: presentationOriginY + 52,
        width: width,
        height: height
    )

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: centerX - 6, y: body.minY + 1))
    tail.line(to: NSPoint(x: centerX, y: presentationOriginY + 44))
    tail.line(to: NSPoint(x: centerX + 6, y: body.minY + 1))
    tail.close()
    NSColor.white.withAlphaComponent(0.97).setFill()
    tail.fill()

    fill(body, color: NSColor.white.withAlphaComponent(0.96), radius: 9)
    stroke(body, color: NSColor.black.withAlphaComponent(0.16), width: 1, radius: 9)
    drawText(
        text,
        in: NSRect(
            x: body.minX + 8,
            y: body.minY + (body.height - measured.height) / 2,
            width: body.width - 16,
            height: measured.height
        ),
        font: font,
        color: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1),
        alignment: .center
    )
}

private func drawZzz(centerX: CGFloat) {
    let font = NSFont(name: "AppleSDGothicNeo-Bold", size: 14)
        ?? NSFont.systemFont(ofSize: 14, weight: .bold)
    let measured = textSize("Zzz", font: font)
    let rect = NSRect(
        x: centerX + 26 - measured.width / 2,
        y: presentationOriginY + 14,
        width: measured.width,
        height: measured.height
    )
    let outline = NSColor(srgbRed: 0.10, green: 0.08, blue: 0.04, alpha: 0.82)
    for x in stride(from: -2, through: 2, by: 2) {
        for y in stride(from: -2, through: 2, by: 2) where x != 0 || y != 0 {
            drawText("Zzz", in: rect.offsetBy(dx: CGFloat(x), dy: CGFloat(y)), font: font, color: outline)
        }
    }
    drawText(
        "Zzz",
        in: rect,
        font: font,
        color: NSColor(srgbRed: 1, green: 0.55, blue: 0.08, alpha: 1)
    )
}

private func generate(repositoryRoot: URL, outputURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw PreviewError.bitmapCreationFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    drawWallpaper()
    drawMenuBar()
    drawNativeWindow()
    for spec in specs {
        try drawCharacter(spec, repositoryRoot: repositoryRoot)
    }
    for spec in specs {
        drawNameplate(spec)
        if let message = spec.message {
            drawBubble(text: message, centerX: spec.centerX, typing: false)
        } else if spec.typing {
            drawBubble(text: "...", centerX: spec.centerX, typing: true)
        }
        if spec.showsZzz {
            drawZzz(centerX: spec.centerX)
        }
    }

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw PreviewError.pngEncodingFailed
    }
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw PreviewError.invalidArguments
    }
    try generate(
        repositoryRoot: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2])
    )
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
