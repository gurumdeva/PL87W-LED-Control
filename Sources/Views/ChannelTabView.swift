import AppKit

/// 상단 채널 탭 한 개. 동그란 아이콘 + 채널 이름.
///
/// 선택 상태는 채널의 강조 색상(accent)을 옅게 깐 보더+배경으로 표시한다.
/// 부모는 `setSelected(_:)` 만 호출하면 되고, 내부 상태 변화는 알 필요 없다.
final class ChannelTabView: NSView {

    private enum Metrics {
        static let circleSize: CGFloat = 44
        static let iconPointSize: CGFloat = 18
        static let labelTopSpacing: CGFloat = 6
        static let labelFontSize: CGFloat = 11
    }

    let section: LightingSection
    var onClick: (() -> Void)?
    private(set) var isSelected: Bool = false

    private let circle = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(section: LightingSection) {
        self.section = section
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setup()
        setSelected(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func setup() {
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.wantsLayer = true
        circle.layer?.cornerRadius = Metrics.circleSize / 2
        circle.layer?.borderWidth = 1
        addSubview(circle)

        icon.translatesAutoresizingMaskIntoConstraints = false
        let cfg = NSImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .medium)
        icon.image = NSImage(systemSymbolName: section.iconSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        circle.addSubview(icon)

        label.stringValue = section.shortTitle
        label.font = .systemFont(ofSize: Metrics.labelFontSize, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        // 라벨이 자체 폭을 강하게 주장하면 부모 stack 의 .fillEqually 가 깨진다.
        // 라벨이 늘어나거나 줄어들 수 있도록 우선순위를 낮춰 둔다.
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: Metrics.circleSize),
            circle.heightAnchor.constraint(equalToConstant: Metrics.circleSize),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.topAnchor.constraint(equalTo: topAnchor),

            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),

            label.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: Metrics.labelTopSpacing),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func setSelected(_ selected: Bool, animated: Bool = true) {
        isSelected = selected
        let style = selected ? Style.selected(accent: section.accentColor) : Style.unselected

        let apply = {
            self.circle.layer?.backgroundColor = style.background
            self.circle.layer?.borderColor = style.border
            self.icon.contentTintColor = style.tint
            self.label.textColor = style.labelColor
            self.label.font = style.labelFont
        }

        if animated {
            // 암묵적 CALayer 애니메이션이 background/border 를 부드럽게 보간한다.
            apply()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        }
    }

    /// 선택/비선택 상태별 시각 정의. 분기를 한 곳에 모아 setSelected 를 단순하게 유지한다.
    private struct Style {
        let background: CGColor
        let border: CGColor
        let tint: NSColor
        let labelColor: NSColor
        let labelFont: NSFont

        static let unselected = Style(
            background: NSColor.white.withAlphaComponent(0.04).cgColor,
            border:     NSColor.white.withAlphaComponent(0.10).cgColor,
            tint:       .secondaryLabelColor,
            labelColor: .secondaryLabelColor,
            labelFont:  .systemFont(ofSize: Metrics.labelFontSize, weight: .medium)
        )

        static func selected(accent: NSColor) -> Style {
            Style(
                background: accent.withAlphaComponent(0.20).cgColor,
                border:     accent.withAlphaComponent(0.85).cgColor,
                tint:       accent,
                labelColor: .labelColor,
                labelFont:  .systemFont(ofSize: Metrics.labelFontSize, weight: .semibold)
            )
        }
    }
}
