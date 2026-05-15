import AppKit

/// 채널 강조 색상으로 채워지는 가로 슬라이더.
///
/// 드래그 도중에는 `finished == false` 콜백이 연속으로 발생하고, 마우스를 떼는
/// 시점에 단 한 번 `finished == true` 가 호출된다. 라벨은 매번, HID 전송은
/// 마지막에만 처리하는 패턴을 위해 두 단계로 노출한다.
final class GradientSlider: NSView {

    private enum Metrics {
        static let trackHeight: CGFloat = 5
        static let handleDiameter: CGFloat = 14
        static let viewHeight: CGFloat = 24
        static let shadowBlur: CGFloat = 3
        /// trackWidth 가 0 이 되는 디바이드 보호용 epsilon.
        static let minTrackWidth: CGFloat = 0.0001
    }

    var minValue: Double = 0
    var maxValue: Double = 100
    var value: Double = 0 {
        didSet { needsDisplay = true }
    }
    var trackColor: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }
    var onValueChanged: ((Double, Bool) -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.viewHeight)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset = Metrics.handleDiameter / 2
        let trackRect = NSRect(
            x: inset,
            y: (bounds.height - Metrics.trackHeight) / 2,
            width: max(0, bounds.width - inset * 2),
            height: Metrics.trackHeight
        )
        let radius = Metrics.trackHeight / 2

        // 비어 있는 트랙
        ctx.saveGState()
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.10).setFill()
        bgPath.fill()
        ctx.restoreGState()

        // 채워진 트랙
        let denom = max(Metrics.minTrackWidth, CGFloat(maxValue - minValue))
        let progress = max(0, min(1, CGFloat(value - minValue) / denom))
        let filledWidth = trackRect.width * progress
        if filledWidth > 0.5 {
            let filledRect = NSRect(
                x: trackRect.minX, y: trackRect.minY,
                width: filledWidth, height: Metrics.trackHeight
            )
            let filledPath = NSBezierPath(roundedRect: filledRect, xRadius: radius, yRadius: radius)
            let gradient = NSGradient(colors: [
                trackColor.withAlphaComponent(0.55),
                trackColor.withAlphaComponent(1.0)
            ])
            gradient?.draw(in: filledPath, angle: 0)
        }

        // 핸들
        let handleX = trackRect.minX + filledWidth - Metrics.handleDiameter / 2
        let handleRect = NSRect(
            x: handleX,
            y: (bounds.height - Metrics.handleDiameter) / 2,
            width: Metrics.handleDiameter,
            height: Metrics.handleDiameter
        )
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1),
            blur: Metrics.shadowBlur,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        ctx.restoreGState()
    }

    // MARK: - Drag handling

    override func mouseDown(with event: NSEvent) { updateValue(event: event, finished: false) }
    override func mouseDragged(with event: NSEvent) { updateValue(event: event, finished: false) }
    override func mouseUp(with event: NSEvent) { updateValue(event: event, finished: true) }

    private func updateValue(event: NSEvent, finished: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let inset = Metrics.handleDiameter / 2
        let trackWidth = max(Metrics.minTrackWidth, bounds.width - inset * 2)
        let progress = max(0, min(1, (point.x - inset) / trackWidth))
        let newValue = minValue + Double(progress) * (maxValue - minValue)
        if newValue != value || finished {
            value = newValue
            onValueChanged?(newValue, finished)
        }
    }
}
