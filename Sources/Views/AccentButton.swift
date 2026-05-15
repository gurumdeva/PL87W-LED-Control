import AppKit

/// 채널 강조 색상으로 채워지는 둥근 풀너비 버튼.
///
/// macOS 기본 `NSButton.bezelStyle = .rounded` 가 임의의 색을 받지 않아서
/// 직접 그리는 버튼으로 대체한다. 누르는 동안 살짝 어두워지는 피드백도 자체 처리.
final class AccentButton: NSView {

    var onClick: (() -> Void)?
    var accent: NSColor = .systemBlue {
        didSet { updateAppearance() }
    }

    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var isPressed = false

    private enum Style {
        static let cornerRadius: CGFloat = 8
        static let height: CGFloat = 32
        static let minWidth: CGFloat = 140
        static let pressedAlpha: CGFloat = 0.65
        static let restingAlpha: CGFloat = 0.92
    }

    init(title: String, symbolName: String?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Style.cornerRadius

        if let symbolName, let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            iconView.contentTintColor = .white
        }

        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        if iconView.image != nil { row.addArrangedSubview(iconView) }
        row.addArrangedSubview(label)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Style.height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Style.minWidth)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Mouse handling
    //
    // 사용자가 누른 채 view 밖으로 드래그했다가 다시 들어오는 동작을 모두 추적해
    // pressed 시각 상태를 정확히 맞춘다. 그리고 mouseUp 시점에 커서가 view 안에
    // 있을 때만 onClick 발사 (macOS 기본 버튼과 동일한 UX).

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed { setPressed(inside) }
    }

    override func mouseUp(with event: NSEvent) {
        let wasInside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if wasInside { onClick?() }
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let alpha: CGFloat = isPressed ? Style.pressedAlpha : Style.restingAlpha
        layer?.backgroundColor = accent.withAlphaComponent(alpha).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = accent.cgColor
    }
}
