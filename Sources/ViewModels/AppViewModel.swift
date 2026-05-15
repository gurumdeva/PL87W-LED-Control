import AppKit

/// 앱 전체 상태를 들고 있는 최상위 ViewModel.
///
/// `@MainActor` 격리. 자식 ChannelViewModel 세 개를 관리하고, 전역 UI 상태
/// (연결 여부 / 현재 탭 / 토스트 / ambient glow 색상)를 옵저버블로 노출한다.
/// 디바이스 호출은 `LightingDevice` protocol 을 통해 추상화 — 다른 기기 추가 시
/// 이 클래스 수정 없음.
///
/// ## 자동 reconnect
/// 디바이스가 발사하는 `connectionEvents` AsyncStream 을 구독해 USB plug/unplug
/// 에 자동으로 반응한다. 사용자가 새로고침을 누를 필요가 없다.
///
/// ## dirty-flag 충돌 방지
/// 사용자가 방금 변경한 상태가 자동 reload 로 덮어쓰이지 않도록 `lastUserIntentAt`
/// 을 추적. 일정 시간 (`reloadGuardWindow`) 안의 reconnect 는 reload 를 건너뛴다.
@MainActor
final class AppViewModel {

    // MARK: - 자식 ViewModel
    let sections: [LightingSection]
    let channels: [ChannelViewModel]

    // MARK: - 전역 상태 (View 가 옵저빙)
    let connection = Observable<ConnectionState>(.unknown)
    let currentChannelIndex = Observable<Int>(0)
    let ambientColors = Observable<[NSColor]>([])
    /// 일회성 이벤트. observeChanges 로 받는다.
    let toast = Observable<ToastMessage?>(nil)

    private let device: any LightingDevice
    private var subscriptions = Set<Subscription>()

    /// 마지막 성공한 사용자 인텐트 시각. 자동 reload 가 덮어쓰지 않도록 dirty flag.
    private var lastUserIntentAt: Date?
    /// 사용자 변경 후 자동 reload 를 보류할 시간.
    private let reloadGuardWindow: TimeInterval = 5.0

    init(
        sections: [LightingSection] = LightingCatalog.sections,
        device: (any LightingDevice)? = nil
    ) {
        let resolvedDevice = device ?? PL87WDevice()
        self.sections = sections
        self.device = resolvedDevice
        self.channels = sections.map { ChannelViewModel(section: $0, device: resolvedDevice) }

        wireChildren()
        recomputeAmbient()
        startMonitoringConnection()
    }

    private func wireChildren() {
        for ch in channels {
            ch.onToast = { [weak self] msg in
                guard let self else { return }
                self.toast.value = msg
                // 성공한 인텐트만 dirty 로 마킹 — 실패는 디바이스 상태를 안 바꿨으니 reload 가 안전.
                if !msg.isError { self.lastUserIntentAt = Date() }
            }
            ch.color.observeChanges { [weak self] _ in
                self?.recomputeAmbient()
            }.store(in: &subscriptions)
        }
    }

    /// 디바이스의 connection event stream 을 구독한다. USB 분리/재연결을 자동 추적.
    private func startMonitoringConnection() {
        Task { [weak self] in
            guard let self else { return }
            for await event in self.device.connectionEvents {
                switch event {
                case .matched:
                    // 매칭 직후엔 stale state 가 있을 수 있으므로 reload — 단 사용자가 막 변경한 게
                    // 있으면 덮어쓰지 않도록 dirty window 동안은 connection 만 갱신.
                    if self.shouldReloadFromDevice() {
                        await self.loadFromDevice()
                    } else {
                        self.connection.value = .connected
                    }
                case .removed:
                    self.connection.value = .disconnected
                }
            }
        }
    }

    private func shouldReloadFromDevice() -> Bool {
        guard let last = lastUserIntentAt else { return true }
        return Date().timeIntervalSince(last) > reloadGuardWindow
    }

    // MARK: - Intents

    /// 디바이스에서 모든 채널 상태를 병렬로 읽어 옵저버블에 반영.
    func loadFromDevice() async {
        if let states = await device.loadStates(for: sections) {
            for ch in channels {
                if let state = states[ch.section.channel] { ch.applyState(state) }
            }
            connection.value = .connected
        } else {
            connection.value = .disconnected
        }
    }

    func selectChannel(at index: Int) {
        guard channels.indices.contains(index), index != currentChannelIndex.value else { return }
        currentChannelIndex.value = index
    }

    func refresh() async {
        // 명시적 새로고침은 dirty window 를 무시한다 — 사용자가 의도적으로 reload 요청.
        lastUserIntentAt = nil
        await device.reset()
        await loadFromDevice()
        toast.value = ToastMessage(text: "새로고침됨", isError: false)
    }

    // MARK: - private

    private func recomputeAmbient() {
        ambientColors.value = channels.map { $0.color.value.nsColor }
    }
}

/// 디바이스 연결 상태. View 는 이 값만 보고 UI 를 갈아낀다.
enum ConnectionState {
    case unknown
    case connected
    case disconnected
}
