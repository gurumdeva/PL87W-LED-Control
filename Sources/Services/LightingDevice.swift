import AppKit

/// 조명 제어 디바이스 추상화 — 새 기기를 추가할 때 이 protocol 만 구현하면
/// ViewModel/View 는 그대로 재사용된다.
///
/// async 인터페이스 의도:
/// - HID 응답 시간(현재 PL87W ≤ 250ms)부터 BLE/네트워크(수백 ms~) 까지 같은 모양으로 다룸
/// - 메인 스레드 차단 없이 cooperative scheduling 으로 양보
///
/// 모든 구현체는 `@MainActor` 격리를 권장 (UI 와 자연스럽게 통합).
@MainActor
protocol LightingDevice: AnyObject {
    /// 디바이스가 매칭/제거될 때 발사되는 이벤트 스트림. 자동 reconnect UX 의 기반.
    var connectionEvents: AsyncStream<ConnectionEvent> { get }

    /// 디바이스 연결. 이미 연결되어 있으면 즉시 true.
    func connect() async -> Bool

    /// 연결을 끊고 모든 리소스 정리.
    func reset() async

    /// 펌웨어가 알려주는 채널의 동적 capability. 미지원이면 nil — ViewModel 이
    /// LightingSection 의 fallback 값으로 fall back.
    func capabilities(of channel: ViaLightingChannel) async -> ChannelCapabilities?

    /// 한 채널의 전체 상태를 읽어 온다. 응답이 없거나 timeout 이면 fallback 값.
    func read(channel: ViaLightingChannel) async -> ViaLightingState

    /// 여러 채널의 상태를 한 번에. 연결이 안 되면 nil.
    func loadStates(for sections: [LightingSection]) async -> [ViaLightingChannel: ViaLightingState]?

    /// 채널의 한 항목을 갱신 (fire-and-forget). 성공 여부만 반환.
    func write(channel: ViaLightingChannel, value: ViaLightingValue, bytes: [UInt8]) async -> Bool

    /// 현재 설정을 펌웨어 비휘발성 영역에 저장.
    func save(channel: ViaLightingChannel) async -> Bool
}

/// 디바이스 in/out 이벤트. AsyncStream 으로 발사된다.
enum ConnectionEvent {
    case matched           // 디바이스가 매칭되어 사용 가능
    case removed           // 디바이스가 사라짐 (USB 분리 등)
}
