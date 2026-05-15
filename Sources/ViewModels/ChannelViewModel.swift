import AppKit

/// 한 LED 채널(백라이트/전면/측면)의 상태와 인텐트.
///
/// 모든 인텐트는 `async`. 호출하는 View 는 Task 안에서 호출하면 된다 — 결과를
/// 기다리지 않는 fire-and-forget 패턴. 결과(success/failure 토스트)는 ViewModel
/// 이 옵저버블로 발행.
///
/// `@MainActor` 격리: UI 상태(옵저버블 갱신)와 device 호출(현재 PL87W 도 @MainActor)
/// 이 같은 actor 에 있어 자연스럽게 직렬화된다.
@MainActor
final class ChannelViewModel {

    // MARK: - View 가 옵저빙
    let section: LightingSection
    let effect = Observable<UInt8>(ViaLightingState.fallback.effect)
    let brightness = Observable<UInt8>(ViaLightingState.fallback.brightness)
    let speed = Observable<UInt8>(ViaLightingState.fallback.speed)
    let color = Observable<ChannelColor>(
        ChannelColor(hue: ViaLightingState.fallback.hue, saturation: ViaLightingState.fallback.saturation)
    )

    /// 동적 max — capability 조회 결과나 카탈로그 fallback. View 가 슬라이더 범위로 사용.
    let effectiveBrightnessMax: Observable<UInt8>
    let effectiveSpeedMax: Observable<UInt8>

    /// AppViewModel 에서 주입. 토스트 메시지를 전역으로 전달.
    var onToast: ((ToastMessage) -> Void)?

    // MARK: - 의존성
    private let device: any LightingDevice
    private var channel: ViaLightingChannel { section.channel }

    private enum ColorMatch {
        static let hueTolerance = 4
        static let saturationTolerance = 12
    }

    init(section: LightingSection, device: any LightingDevice) {
        self.section = section
        self.device = device
        // 초기값은 카탈로그 fallback. 디바이스가 capability 를 보고하면 loadCapabilities 에서 갱신.
        self.effectiveBrightnessMax = Observable<UInt8>(UInt8(clamping: Int(section.brightnessMax)))
        self.effectiveSpeedMax = Observable<UInt8>(UInt8(clamping: Int(section.speedMax)))

        // 백그라운드에서 capability 조회 — 결과가 도착하면 옵저버블이 갱신되어 View 자동 반영.
        Task { [weak self] in await self?.loadCapabilities() }
    }

    private func loadCapabilities() async {
        guard let caps = await device.capabilities(of: channel) else { return }
        effectiveBrightnessMax.value = caps.brightnessRange.upperBound
        effectiveSpeedMax.value = caps.speedRange.upperBound
    }

    // MARK: - 동기화 (옵저버블 갱신만 — 사이드 이펙트 없음)

    func applyState(_ state: ViaLightingState) {
        effect.value = sanitizedEffect(state.effect)
        // 펌웨어가 보고하는 값을 그대로 노출 — View 가 effectiveBrightnessMax/SpeedMax 와
        // 비교해 over-range 인지 시각적으로 표시한다 (다른 도구가 한도 초과 값을 설정했을 때 가시화).
        brightness.value = state.brightness
        speed.value = state.speed
        color.value = ChannelColor(hue: state.hue, saturation: state.saturation)
    }

    // MARK: - Intents (모두 async — caller 가 Task 로 호출)

    func selectEffect(_ value: UInt8) async {
        let label = section.presets.first { $0.value == value }?.displayName ?? "스타일"
        await perform(
            { await self.device.write(channel: self.channel, value: .effect, bytes: [value]) },
            onSuccess: { self.effect.value = value },
            successText: "\(label) 적용",
            failureText: "전송 실패: USB 유선 연결을 확인하세요"
        )
    }

    func setBrightness(_ value: UInt8) async {
        await perform(
            { await self.device.write(channel: self.channel, value: .brightness, bytes: [value]) },
            onSuccess: { self.brightness.value = value },
            successText: "밝기 \(value)"
        )
    }

    func setSpeed(_ value: UInt8) async {
        await perform(
            { await self.device.write(channel: self.channel, value: .speed, bytes: [value]) },
            onSuccess: { self.speed.value = value },
            successText: "속도 \(value)"
        )
    }

    func pickPreset(_ preset: ColorPreset) async {
        await perform(
            { await self.device.write(channel: self.channel, value: .color, bytes: [preset.hue, preset.saturation]) },
            onSuccess: { self.color.value = ChannelColor(hue: preset.hue, saturation: preset.saturation) },
            successText: "\(preset.name) 색상 적용"
        )
    }

    func setCustomColor(hue: UInt8, saturation: UInt8) async {
        await perform(
            { await self.device.write(channel: self.channel, value: .color, bytes: [hue, saturation]) },
            onSuccess: { self.color.value = ChannelColor(hue: hue, saturation: saturation) },
            successText: "색상 적용 H \(hue) S \(saturation)"
        )
    }

    func save() async {
        await perform(
            { await self.device.save(channel: self.channel) },
            successText: "현재 조명 설정 저장됨",
            failureText: "저장 실패"
        )
    }

    // MARK: - 파생 값

    func isPresetSelected(_ preset: ColorPreset) -> Bool {
        let current = color.value
        return abs(Int(preset.hue) - Int(current.hue)) < ColorMatch.hueTolerance
            && abs(Int(preset.saturation) - Int(current.saturation)) < ColorMatch.saturationTolerance
    }

    // MARK: - private helpers

    /// 모든 인텐트의 공통 패턴: async device 호출 → 결과로 분기 → 토스트.
    private func perform(
        _ action: () async -> Bool,
        onSuccess: () -> Void = {},
        successText: String,
        failureText: String = "전송 실패"
    ) async {
        let ok = await action()
        if ok { onSuccess() }
        let text = ok ? successText : failureText
        onToast?(ToastMessage(text: text, isError: !ok))
    }

    private func sanitizedEffect(_ raw: UInt8) -> UInt8 {
        if section.presets.contains(where: { $0.value == raw }) { return raw }
        return section.presets.first?.value ?? raw
    }
}

// MARK: - 부속 값 타입

struct ChannelColor: Equatable {
    let hue: UInt8
    let saturation: UInt8

    var nsColor: NSColor {
        NSColor(
            hue: CGFloat(hue) / 255.0,
            saturation: max(0.2, CGFloat(saturation) / 255.0),
            brightness: 1.0,
            alpha: 1.0
        )
    }
}

struct ToastMessage {
    let text: String
    let isError: Bool
}
