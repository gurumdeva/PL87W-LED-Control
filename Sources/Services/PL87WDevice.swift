import AppKit
import IOKit.hid

/// PL87W 키보드의 `LightingDevice` 구현.
///
/// `@MainActor` 격리: IOKit callback 이 메인 runloop 로 schedule 되어 모든 호출이
/// 메인에서 일어난다. actor 와 IOKit context 가 자연스럽게 맞물려 별도 동기화 없음.
///
/// ## 자동 연결 감지
/// 별도의 IOHIDManager (`monitor`) 를 두고 매칭/제거 callback 을 등록한다.
/// USB plug/unplug 가 발생하면 `connectionEvents` AsyncStream 으로 알림이 흘러
/// AppViewModel 이 자동으로 reload 또는 disconnect 상태로 전환한다.
@MainActor
final class PL87WDevice: LightingDevice {

    private let hid: ViaHIDController

    let connectionEvents: AsyncStream<ConnectionEvent>
    private let connectionEventContinuation: AsyncStream<ConnectionEvent>.Continuation

    /// 디바이스 in/out 만 감지하는 전용 IOHIDManager. 통신용 manager (`hid`) 와는 별개.
    private var monitor: IOHIDManager?

    // PL87W VIA Raw HID descriptor — ViaHIDController 와 동일.
    private static let vendorID: Int = 0x36B0
    private static let productID: Int = 0x3031
    private static let usagePage: Int = 0xFF60
    private static let usage: Int = 0x61

    init(hid: ViaHIDController? = nil) {
        self.hid = hid ?? ViaHIDController()
        var cont: AsyncStream<ConnectionEvent>.Continuation!
        self.connectionEvents = AsyncStream { cont = $0 }
        self.connectionEventContinuation = cont

        setupMonitor()
    }

    deinit {
        // 메인 격리된 cleanup 을 nonisolated deinit 에서 안전하게 호출하기 위해 assumeIsolated.
        // 앱 종료 시점은 메인 thread.
        MainActor.assumeIsolated {
            teardownMonitor()
            connectionEventContinuation.finish()
        }
    }

    // MARK: - LightingDevice

    func connect() async -> Bool {
        hid.connect()
    }

    func reset() async {
        hid.reset()
    }

    func capabilities(of channel: ViaLightingChannel) async -> ChannelCapabilities? {
        // PL87W 펌웨어는 capability 조회 명령을 노출하지 않는다. nil 을 반환해
        // ViewModel 이 카탈로그 정의 (LightingSection.brightnessMax/speedMax) 로 fallback.
        // 다른 키보드를 위한 LightingDevice 구현체는 실제 VIA 명령으로 조회해 채워 줄 수 있다.
        return nil
    }

    func read(channel: ViaLightingChannel) async -> ViaLightingState {
        await hid.state(channel: channel)
    }

    /// 채널 별 상태를 TaskGroup 으로 병렬 read. 채널 3 × 항목 4 = 최대 12 read 가 동시에 진행.
    func loadStates(for sections: [LightingSection]) async -> [ViaLightingChannel: ViaLightingState]? {
        guard hid.connect() else { return nil }

        return await withTaskGroup(of: (ViaLightingChannel, ViaLightingState).self) { group in
            for section in sections {
                group.addTask { [hid] in
                    let state = await hid.state(channel: section.channel)
                    return (section.channel, state)
                }
            }
            var result: [ViaLightingChannel: ViaLightingState] = [:]
            for await (channel, state) in group {
                result[channel] = state
            }
            return result
        }
    }

    func write(channel: ViaLightingChannel, value: ViaLightingValue, bytes: [UInt8]) async -> Bool {
        hid.set(channel: channel, value: value, bytes: bytes)
    }

    func save(channel: ViaLightingChannel) async -> Bool {
        hid.save(channel: channel)
    }

    // MARK: - IOKit monitoring

    /// PL87W 매칭/제거를 듣는 별도 IOHIDManager 를 셋업.
    /// 매칭 시 .matched, 제거 시 .removed 가 `connectionEvents` 에 yield 된다.
    private func setupMonitor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: Self.usage
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            let device = Unmanaged<PL87WDevice>.fromOpaque(ctx).takeUnretainedValue()
            // callback 은 IOHIDManager 가 메인 runloop 로 schedule 했으므로 메인 thread.
            MainActor.assumeIsolated {
                device.connectionEventContinuation.yield(.matched)
            }
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            let device = Unmanaged<PL87WDevice>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                // 통신용 hid 핸들도 정리 — 이후 호출이 nil status 로 fail 처리되도록.
                device.hid.reset()
                device.connectionEventContinuation.yield(.removed)
            }
        }, context)

        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        self.monitor = manager
    }

    private func teardownMonitor() {
        if let monitor {
            IOHIDManagerUnscheduleFromRunLoop(
                monitor, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(monitor, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        monitor = nil
    }
}
