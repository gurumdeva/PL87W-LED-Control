import AppKit

/// 앱 아이콘 생성기. 한 번 실행하면 `AppIcon.iconset/` 에 모든 해상도의 PNG 를 만들고,
/// 이어서 `iconutil` 로 `.icns` 로 변환할 수 있다.
///
/// 별도 도구로 빌드 — main 앱이랑 함께 컴파일되지 않도록 `Sources/Tools/` 에 둔다.
/// 실행:
///     swiftc Sources/Tools/IconGenerator.swift -o build/icon-gen \
///       -framework AppKit
///     ./build/icon-gen
///     iconutil -c icns AppIcon.iconset

private let projectRoot: String = {
    let scriptPath = CommandLine.arguments.first ?? ""
    // build/icon-gen 에서 두 단계 위가 프로젝트 루트
    let url = URL(fileURLWithPath: scriptPath).deletingLastPathComponent().deletingLastPathComponent()
    return url.path
}()

private let outputDir = "\(projectRoot)/AppIcon.iconset"

private let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func makeIcon(pixels: Int) -> NSImage {
    let dim = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: dim, height: dim))
    image.lockFocus()
    defer { image.unlockFocus() }

    // 1) 둥근 사각형 (macOS Big Sur 이후 squircle 스타일)
    let inset = dim * 0.08
    let cornerRadius = dim * 0.225
    let squirclePath = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2),
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    NSGraphicsContext.saveGraphicsState()
    squirclePath.addClip()

    // 2) 그라데이션 배경 — 채널 강조 색상의 영감을 받은 청-보라
    let backgroundGradient = NSGradient(colors: [
        NSColor(srgbRed: 0.05, green: 0.10, blue: 0.30, alpha: 1.0),
        NSColor(srgbRed: 0.20, green: 0.30, blue: 0.65, alpha: 1.0),
        NSColor(srgbRed: 0.45, green: 0.30, blue: 0.85, alpha: 1.0)
    ])!
    backgroundGradient.draw(in: squirclePath.bounds, angle: -45)

    // 3) LED 글로우 효과 — 두 색의 부드러운 원형 글로우
    drawGlow(
        center: CGPoint(x: dim * 0.78, y: dim * 0.20),
        radius: dim * 0.55,
        color: NSColor(srgbRed: 0.40, green: 0.85, blue: 1.0, alpha: 1.0)
    )
    drawGlow(
        center: CGPoint(x: dim * 0.18, y: dim * 0.80),
        radius: dim * 0.45,
        color: NSColor(srgbRed: 0.95, green: 0.40, blue: 0.85, alpha: 1.0)
    )

    // 4) 키보드 심볼 (가운데, 흰색)
    drawKeyboardSymbol(in: NSRect(origin: .zero, size: NSSize(width: dim, height: dim)))

    NSGraphicsContext.restoreGraphicsState()

    return image
}

func drawGlow(center: CGPoint, radius: CGFloat, color: NSColor) {
    let rect = NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    let gradient = NSGradient(colors: [
        color.withAlphaComponent(0.55),
        color.withAlphaComponent(0.25),
        color.withAlphaComponent(0.0)
    ])!
    gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
}

/// SF Symbol "keyboard.fill" 을 흰색으로 합성해 그리기.
func drawKeyboardSymbol(in rect: NSRect) {
    let pointSize = rect.width * 0.42
    var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    if #available(macOS 12.0, *) {
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
        config = config.applying(paletteConfig)
    }
    guard let symbol = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        return
    }
    let symbolSize = symbol.size
    let symbolRect = NSRect(
        x: rect.midX - symbolSize.width / 2,
        y: rect.midY - symbolSize.height / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    // macOS 12 미만 호환: 흰색 fill 로 마스킹
    if #unavailable(macOS 12.0) {
        NSGraphicsContext.saveGraphicsState()
        NSColor.white.set()
        symbolRect.fill()
        symbol.draw(in: symbolRect, from: .zero, operation: .destinationIn, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    } else {
        symbol.draw(in: symbolRect)
    }
}

func savePNG(_ image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to encode PNG for \(path)\n".data(using: .utf8)!)
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    } catch {
        FileHandle.standardError.write("Failed to write \(path): \(error)\n".data(using: .utf8)!)
    }
}

// MARK: - main

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (name, pixels) in iconSizes {
    let image = makeIcon(pixels: pixels)
    savePNG(image, path: "\(outputDir)/\(name)")
}

print("\nDone. Convert to .icns with:")
print("  iconutil -c icns \"\(outputDir)\"")
