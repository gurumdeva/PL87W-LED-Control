import AppKit

/// 상단 상태 바: ●  PL87W HID 연결됨  …  ⟳
///
/// `AppViewModel.connection` 을 옵저빙해 dot/text 를 갈아 끼우고, 새로고침
/// 버튼 클릭은 `onRefresh` 콜백으로 발행.
final class StatusBarView: NSStackView {

    var onRefresh: (() -> Void)?

    private let dot = NSView()
    private let label = NSTextField(labelWithString: "검색 중…")
    private var subscriptions = Set<Subscription>()

    init(viewModel: AppViewModel) {
        super.init(frame: .zero)
        setupLayout()
        bind(viewModel: viewModel)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        orientation = .horizontal
        alignment = .centerY
        spacing = 7

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refresh = NSButton(title: "", target: self, action: #selector(refreshTapped))
        refresh.isBordered = false
        refresh.bezelStyle = .smallSquare
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "새로고침")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        refresh.contentTintColor = .secondaryLabelColor
        refresh.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            refresh.widthAnchor.constraint(equalToConstant: 22),
            refresh.heightAnchor.constraint(equalToConstant: 22)
        ])

        addArrangedSubview(dot)
        addArrangedSubview(label)
        addArrangedSubview(spacer)
        addArrangedSubview(refresh)
    }

    private func bind(viewModel: AppViewModel) {
        viewModel.connection.observe { [weak self] state in
            self?.applyConnectionState(state)
        }.store(in: &subscriptions)
    }

    private func applyConnectionState(_ state: ConnectionState) {
        let (dotColor, text, textColor): (NSColor, String, NSColor) = {
            switch state {
            case .unknown:      return (.systemGray,  "검색 중…",        .secondaryLabelColor)
            case .connected:    return (.systemGreen, "PL87W HID 연결됨", .systemGreen)
            case .disconnected: return (.systemRed,   "연결 안됨",        .secondaryLabelColor)
            }
        }()
        dot.layer?.backgroundColor = dotColor.cgColor
        label.stringValue = text
        label.textColor = textColor
    }

    @objc private func refreshTapped() {
        onRefresh?()
    }
}
