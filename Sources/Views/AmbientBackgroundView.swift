import AppKit

/// 윈도우 배경을 부드럽게 채우는 글로우 레이어.
///
/// 현재 선택된 채널의 색상을 우상단에 진하게, 인접 채널 색상을 좌하단에 옅게 깐다.
/// 어피어런스(다크/라이트)에 따라 글로우 강도가 자동 조정된다.
final class AmbientBackgroundView: NSView {
    var glowColors: [NSColor] = [NSColor.systemBlue, NSColor.systemMint, NSColor.systemPurple] {
        didSet { needsDisplay = true }
    }
    var activeIndex: Int = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark
            ? NSColor(calibratedWhite: 0.08, alpha: 1.0)
            : NSColor(calibratedWhite: 0.97, alpha: 1.0)
        base.setFill()
        bounds.fill()

        guard !glowColors.isEmpty else { return }
        let activeIdx = min(max(activeIndex, 0), glowColors.count - 1)
        drawGlow(
            color: glowColors[activeIdx],
            xRatio: 1.05, yRatio: -0.10, scale: 1.5,
            alpha: dark ? 0.20 : 0.14
        )
        let accentIdx = (activeIdx + 1) % glowColors.count
        drawGlow(
            color: glowColors[accentIdx],
            xRatio: -0.05, yRatio: 1.05, scale: 1.2,
            alpha: dark ? 0.10 : 0.07
        )
    }

    private func drawGlow(color: NSColor, xRatio: CGFloat, yRatio: CGFloat, scale: CGFloat, alpha: CGFloat) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        let diameter = max(bounds.width, bounds.height) * scale
        let center = CGPoint(x: bounds.width * xRatio, y: bounds.height * yRatio)
        let rect = NSRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let gradient = NSGradient(colors: [
            converted.withAlphaComponent(alpha),
            converted.withAlphaComponent(alpha * 0.45),
            converted.withAlphaComponent(0)
        ])
        gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
    }
}
