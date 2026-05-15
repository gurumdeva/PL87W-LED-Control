import AppKit

/// 색상 팔레트 한 칸. 일반 칸은 단색을 칠하고, picker 모드는 무지개 + ＋ 글리프로
/// "임의 색상 고르기" 의미를 준다.
///
/// `isHighlighted = true` 면 흰색 굵은 보더로 강조해 현재 적용된 색을 표시한다.
final class ColorSwatch: NSView {

    /// 모든 ColorSwatch 인스턴스가 같은 높이를 사용. 외부에서 heightAnchor 제약
    /// 줄 때도 이 상수를 참조해 일관성을 보장한다.
    static let height: CGFloat = 32

    var onClick: (() -> Void)?
    var isPickerStyle: Bool = false {
        didSet { needsDisplay = true }
    }
    var swatchColor: NSColor = .gray {
        didSet { needsDisplay = true }
    }
    var isHighlighted: Bool = false {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius: CGFloat = 8
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

        if isPickerStyle {
            drawRainbow(path: path)
            drawPlusGlyph()
        } else {
            swatchColor.setFill()
            path.fill()
        }

        drawBorder(radius: radius)
    }

    private func drawRainbow(path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let gradient = NSGradient(colors: stride(from: 0, through: 1.0, by: 1.0 / 6.0).map {
            NSColor(hue: CGFloat($0), saturation: 0.85, brightness: 1.0, alpha: 1.0)
        })
        gradient?.draw(in: bounds, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPlusGlyph() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 변경한 strokeColor/lineCap/shadow 가 이 함수 밖으로 새지 않도록 격리한다.
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let plusSize: CGFloat = 12
        let cx = bounds.midX
        let cy = bounds.midY
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 1.5,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.move(to: CGPoint(x: cx - plusSize / 2, y: cy))
        ctx.addLine(to: CGPoint(x: cx + plusSize / 2, y: cy))
        ctx.move(to: CGPoint(x: cx, y: cy - plusSize / 2))
        ctx.addLine(to: CGPoint(x: cx, y: cy + plusSize / 2))
        ctx.strokePath()
    }

    private func drawBorder(radius: CGFloat) {
        let inset: CGFloat = 0.75
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: radius - inset,
            yRadius: radius - inset
        )
        if isHighlighted {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 2
        } else {
            NSColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }
}
