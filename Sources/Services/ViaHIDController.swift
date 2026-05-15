import AppKit
import IOKit.hid

/// PL87W 의 VIA Raw HID 채널과 직접 통신하는 저수준 컨트롤러.
///
/// 두 가지 통신 모드:
/// - **fire-and-forget**: `set`, `save` — 응답을 기다리지 않는 출력.
/// - **request/response (async)**: `get` — 응답이 도착하면 그 보고서를 결과로 돌려준다.
///   메인 RunLoop spin 대신 `IOHIDReportCallback` 이 pendingRequests 큐를 풀어 주는
///   continuation 기반 구조라 메인 스레드를 차단하지 않는다.
///
/// 라이프사이클:
/// - `connect()` 가 manager/device/inputBuffer 를 잡고 runloop 에 스케줄.
/// - `reset()` 이 콜백 unregister → runloop unschedule → manager close → buffer 해제.
///   여기에 더해 `pendingRequests` 큐에 남아 있는 continuation 들을 `nil` 로 resume 해
///   호출 측이 영원히 기다리는 일이 없도록 한다.
/// - `deinit` 에서 `reset()` 호출.
///
/// `@MainActor` 격리: IOKit 콜백이 메인 runloop 에 schedule 되어 있어 callback 도
/// 메인에서 호출됨. actor isolation 을 메인으로 맞추면 별도 동기화 불필요.
@MainActor
final class ViaHIDController {

    // MARK: - Pending request 큐

    /// 응답을 기다리고 있는 요청. callback 이 들어오면 (channel, value) 로 매칭해 resume.
    private struct PendingRequest {
        let channel: UInt8
        let value: UInt8
        let continuation: CheckedContinuation<[UInt8]?, Never>
    }

    private var pendingRequests: [PendingRequest] = []

    // MARK: - IOKit handles

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?

    // MARK: - Constants

    private static let reportSize: CFIndex = 32
    private static let responseTimeout: TimeInterval = 0.25

    // PL87W VIA Raw HID descriptor (제조사 배포 JSON 확인값)
    private static let vendorID: Int = 0x36B0
    private static let productID: Int = 0x3031
    private static let usagePage: Int = 0xFF60
    private static let usage: Int = 0x61

    deinit {
        // deinit 은 nonisolated 라 @MainActor 메서드를 직접 못 부른다.
        // assumeIsolated 로 메인 thread 가정 (앱이 종료될 때 호출되며 그 시점은 메인).
        MainActor.assumeIsolated { reset() }
    }

    func reset() {
        // 1) 입력 콜백 unregister — 이후 호출 가능성을 끊는다.
        if let device, let inputBuffer {
            let noCallback: IOHIDReportCallback? = nil
            IOHIDDeviceRegisterInputReportCallback(
                device, inputBuffer, Self.reportSize, noCallback, nil
            )
        }
        // 2) manager 를 runloop 에서 떼고 close.
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        device = nil
        // 3) 대기 중이던 요청을 모두 nil 로 resume — caller 가 무한 대기하지 않게.
        let dropped = pendingRequests
        pendingRequests.removeAll()
        for req in dropped { req.continuation.resume(returning: nil) }
        // 4) 마지막으로 버퍼 해제.
        if let inputBuffer {
            inputBuffer.deallocate()
            self.inputBuffer = nil
        }
    }

    func connect() -> Bool {
        if device != nil { return true }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: Self.usage
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else { return false }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }

        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(Self.reportSize))
        buffer.initialize(repeating: 0, count: Int(Self.reportSize))

        // callback context = self (unretained). self 는 LightingDevice → AppViewModel
        // 체인이 strong 으로 들고 있어 살아 있다. deinit 시 reset 으로 unregister.
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, Self.reportSize,
            { context, _, _, _, _, report, reportLength in
                guard let context else { return }
                let controller = Unmanaged<ViaHIDController>
                    .fromOpaque(context).takeUnretainedValue()
                let buf = Array(UnsafeBufferPointer(start: report, count: reportLength))
                controller.handleResponse(buf)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        self.manager = manager
        self.device = device
        self.inputBuffer = buffer
        return true
    }

    // MARK: - Public commands

    /// Fire-and-forget. 응답을 기다리지 않는다.
    @discardableResult
    func set(channel: ViaLightingChannel, value: ViaLightingValue, bytes: [UInt8]) -> Bool {
        send([0x07, channel.rawValue, value.rawValue] + bytes)
    }

    @discardableResult
    func save(channel: ViaLightingChannel) -> Bool {
        send([0x09, channel.rawValue])
    }

    /// Request/response. callback 으로 응답이 들어올 때까지 await.
    /// 응답이 0.25s 안에 안 오면 timeout — nil 반환.
    func get(channel: ViaLightingChannel, value: ViaLightingValue) async -> [UInt8]? {
        guard connect() else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<[UInt8]?, Never>) in
            let request = PendingRequest(
                channel: channel.rawValue,
                value: value.rawValue,
                continuation: cont
            )
            pendingRequests.append(request)

            guard send([0x08, channel.rawValue, value.rawValue]) else {
                drainPending(channel: channel.rawValue, value: value.rawValue, result: nil)
                return
            }

            // Timeout — 메인 큐에 예약. 응답이 먼저 오면 큐에서 미리 빠져 있어 noop.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.responseTimeout) { [weak self] in
                self?.drainPending(channel: channel.rawValue, value: value.rawValue, result: nil)
            }
        }
    }

    /// 한 채널의 모든 항목을 병렬로 읽는다 (async let).
    /// 메인 스레드를 차단하지 않으면서 4 개 read 를 동시에 진행 → 응답 latency 가
    /// max 1×timeout 으로 압축된다 (기존 sync 버전은 4×timeout).
    func state(channel: ViaLightingChannel) async -> ViaLightingState {
        async let brightness = get(channel: channel, value: .brightness)
        async let effect = get(channel: channel, value: .effect)
        async let speed = get(channel: channel, value: .speed)
        async let color = get(channel: channel, value: .color)

        let (b, e, s, c) = await (brightness, effect, speed, color)
        let fb = ViaLightingState.fallback
        let colorPayload = c ?? [fb.hue, fb.saturation]
        return ViaLightingState(
            brightness: b?.first ?? fb.brightness,
            effect: e?.first ?? fb.effect,
            speed: s?.first ?? fb.speed,
            hue: colorPayload.first ?? fb.hue,
            saturation: colorPayload.count > 1 ? colorPayload[1] : fb.saturation
        )
    }

    // MARK: - Callback dispatch

    /// IOKit 콜백이 메인에서 호출된다. 응답 헤더로 매칭되는 pending request 를 풀어 준다.
    private func handleResponse(_ response: [UInt8]) {
        guard response.count >= 4, response[0] == 0x08 else { return }
        let channel = response[1]
        let value = response[2]
        let payload = Array(response.dropFirst(3))
        drainPending(channel: channel, value: value, result: payload)
    }

    /// (channel, value) 로 매칭되는 첫 pending 요청을 결과로 resume.
    /// 같은 키의 요청이 두 개 동시 진행 중이면 도착 순서대로 매칭한다.
    private func drainPending(channel: UInt8, value: UInt8, result: [UInt8]?) {
        guard let index = pendingRequests.firstIndex(where: { $0.channel == channel && $0.value == value }) else {
            return
        }
        let req = pendingRequests.remove(at: index)
        req.continuation.resume(returning: result)
    }

    // MARK: - private send

    private func send(_ payload: [UInt8]) -> Bool {
        guard connect(), let device else { return false }
        var report = [UInt8](repeating: 0, count: Int(Self.reportSize))
        for (index, byte) in payload.enumerated() where index < report.count {
            report[index] = byte
        }
        let status = report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnNoMemory
            }
            return IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(0), base, rawBuffer.count
            )
        }
        return status == kIOReturnSuccess
    }
}
