import AppKit

/// 윈도우 라이프사이클을 관리하고 AppViewModel 의 상태를 화면에 연결한다.
///
/// MVVM 의 "binder" 역할 — 직접 비즈니스 로직을 들지 않고, ViewModel 의
/// 옵저버블을 옵저빙해 View 의 isHidden/setSelected 같은 구조적 변경만
/// 트리거한다. 각 View(StatusBarView, ToastView, ChannelPanel)는 자기에게
/// 필요한 ViewModel 만 직접 옵저빙한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 상위 모델
    private let viewModel = AppViewModel()

    // MARK: - 자식 뷰
    private var window: NSWindow!
    private var backgroundView: AmbientBackgroundView!
    private var rootStack: NSStackView!
    private var statusBar: StatusBarView!
    private var tabsRow: NSStackView!
    private var contentArea: NSView!
    private var disconnectedView: DisconnectedView!
    private var toastView: ToastView!
    private var tabs: [ChannelTabView] = []
    private var panels: [ChannelPanel] = []

    /// 색상 피커가 열려 있는 채널. NSColorPanel 콜백이 어떤 채널에 적용할지 알기 위해 보관.
    private weak var pickerTarget: ChannelViewModel?

    /// ViewModel 옵저버블 구독. self 가 사라지면 함께 해제되어 listener leak 없음.
    private var subscriptions = Set<Subscription>()

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        bindViewModel()
        // 윈도우 먼저 표시. 첫 HID read 는 async — 메인 차단 없이 background 로 진행되어
        // 결과가 도착하면 connection 옵저버블이 .connected/.disconnected 로 전환됨.
        // 그 사이엔 statusBar 가 "검색 중…" 표시.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await viewModel.loadFromDevice() }
    }

    // MARK: - Window construction

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PL87W LED Control"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 320, height: 440)
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)

        backgroundView = AmbientBackgroundView(frame: .zero)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = backgroundView

        // 패딩 일관성: top 은 traffic light 와 충돌 회피용으로 28, 좌/우/하단은 모두 16.
        rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 12
        rootStack.edgeInsets = NSEdgeInsets(top: 28, left: 16, bottom: 16, right: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: backgroundView.bottomAnchor)
        ])

        statusBar = StatusBarView(viewModel: viewModel)
        statusBar.onRefresh = { [weak self] in
            Task { [weak self] in await self?.viewModel.refresh() }
        }
        rootStack.addArrangedSubview(statusBar)
        rootStack.setCustomSpacing(16, after: statusBar)

        tabsRow = makeTabsRow()
        rootStack.addArrangedSubview(tabsRow)
        rootStack.setCustomSpacing(18, after: tabsRow)

        // contentArea: 세 패널을 같은 자리에 겹쳐 두고 isHidden 으로 한 개만 보임.
        // .alignment = .width 만으로 폭이 안정적으로 안 맞아 backgroundView 폭에
        // 직접 묶는다.
        contentArea = NSView()
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(contentArea)
        let hInsets = rootStack.edgeInsets.left + rootStack.edgeInsets.right
        contentArea.widthAnchor
            .constraint(equalTo: backgroundView.widthAnchor, constant: -hInsets)
            .isActive = true

        for channelVM in viewModel.channels {
            let panel = ChannelPanel(viewModel: channelVM)
            panel.onRequestColorPicker = { [weak self] in self?.openColorPicker(for: channelVM) }
            panel.isHidden = true
            panels.append(panel)
            contentArea.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
                panel.topAnchor.constraint(equalTo: contentArea.topAnchor),
                panel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor)
            ])
        }

        disconnectedView = DisconnectedView()
        disconnectedView.onRetry = { [weak self] in
            Task { [weak self] in await self?.viewModel.refresh() }
        }
        disconnectedView.isHidden = true
        rootStack.addArrangedSubview(disconnectedView)

        toastView = ToastView(viewModel: viewModel)
        rootStack.addArrangedSubview(toastView)
    }

    private func makeTabsRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .top
        row.distribution = .fillEqually
        for (index, channelVM) in viewModel.channels.enumerated() {
            let tab = ChannelTabView(section: channelVM.section)
            tab.onClick = { [weak self] in self?.viewModel.selectChannel(at: index) }
            tabs.append(tab)
            row.addArrangedSubview(tab)
        }
        return row
    }

    // MARK: - ViewModel binding

    private func bindViewModel() {
        viewModel.connection.observe { [weak self] state in
            self?.applyConnectionLayout(state)
        }.store(in: &subscriptions)
        // 현재 채널은 두 가지에 반영: 탭/패널 visibility 와 배경 글로우 활성 인덱스.
        viewModel.currentChannelIndex.observe { [weak self] index in
            self?.applyChannelSelection(index)
            self?.backgroundView.activeIndex = index
        }.store(in: &subscriptions)
        // 배경 색상은 채널 색이 실제로 바뀔 때만 push 된다.
        viewModel.ambientColors.observe { [weak self] colors in
            self?.backgroundView.glowColors = colors
        }.store(in: &subscriptions)
    }

    private func applyConnectionLayout(_ state: ConnectionState) {
        switch state {
        case .unknown:
            tabsRow.isHidden = true
            for p in panels { p.isHidden = true }
            disconnectedView.isHidden = true
        case .connected:
            tabsRow.isHidden = false
            disconnectedView.isHidden = true
            applyChannelSelection(viewModel.currentChannelIndex.value)
        case .disconnected:
            tabsRow.isHidden = true
            for p in panels { p.isHidden = true }
            disconnectedView.isHidden = false
        }
    }

    private func applyChannelSelection(_ index: Int) {
        guard viewModel.connection.value == .connected else { return }
        for (i, tab) in tabs.enumerated() {
            tab.setSelected(i == index)
        }
        for (i, panel) in panels.enumerated() {
            panel.isHidden = (i != index)
        }
    }

    // MARK: - NSColorPanel 브릿지
    //
    // NSColorPanel 은 target/action 만 받는 Cocoa API 라서 ViewModel 에 직접
    // 연결할 수 없다. AppDelegate 가 얇은 어댑터 역할만 한다.

    private func openColorPicker(for channel: ChannelViewModel) {
        pickerTarget = channel
        let picker = NSColorPanel.shared
        picker.color = channel.color.value.nsColor
        picker.setTarget(self)
        picker.setAction(#selector(colorPickerChanged(_:)))
        picker.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPickerChanged(_ picker: NSColorPanel) {
        guard let target = pickerTarget else { return }
        let converted = picker.color.usingColorSpace(.deviceRGB) ?? picker.color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let hueByte = UInt8(max(0, min(255, Int(round(hue * 255)))))
        let satByte = UInt8(max(0, min(255, Int(round(saturation * 255)))))
        Task { await target.setCustomColor(hue: hueByte, saturation: satByte) }
    }
}
