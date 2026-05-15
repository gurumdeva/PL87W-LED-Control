import AppKit

/// 디바이스가 연결되지 않았을 때 빈 영역에 표시되는 빈 상태(empty state) 패널.
///
/// 상태 자체는 정적이라서 ViewModel 옵저빙은 하지 않고 visibility 만 외부가 결정.
/// "다시 검색" 버튼은 `onRetry` 콜백으로 발행.
final class DisconnectedView: NSStackView {

    var onRetry: (() -> Void)?

    init() {
        super.init(frame: .zero)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        // AppDelegate 가 backgroundView 의 정중앙에 absolute 배치하므로 자체 top
        // 패딩은 0. 자식들은 centerX 로 정렬해 가운데에 모은다.
        orientation = .vertical
        alignment = .centerX
        spacing = 10

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "cable.connector.slash", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 32, weight: .light))
        iconView.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: "연결된 장치가 없습니다")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let detail = NSTextField(labelWithString: "PL87W를 USB 케이블로 연결하고\n유선 모드로 전환하세요.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 0
        detail.lineBreakMode = .byWordWrapping

        let retry = NSButton(title: "다시 검색", target: self, action: #selector(retryTapped))
        retry.bezelStyle = .rounded
        retry.controlSize = .regular

        addArrangedSubview(iconView)
        addArrangedSubview(title)
        addArrangedSubview(detail)
        setCustomSpacing(14, after: detail)
        addArrangedSubview(retry)
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
