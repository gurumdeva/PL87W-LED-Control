import Foundation
import IOKit.hid

private final class Probe {
    private var manager: IOHIDManager!
    private var response: [UInt8]?
    private var device: IOHIDDevice?

    func run() -> Int32 {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x36B0,
            kIOHIDProductIDKey: 0x3031,
            kIOHIDPrimaryUsagePageKey: 0xFF60,
            kIOHIDPrimaryUsageKey: 0x61
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            print("open failed: 0x\(String(openStatus, radix: 16))")
            return 1
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
            print("raw HID device not found")
            return 1
        }
        self.device = device

        let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        inputBuffer.initialize(repeating: 0, count: 32)
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 32, { context, _, _, _, reportID, report, reportLength in
            guard let context else { return }
            let probe = Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue()
            probe.response = Array(UnsafeBufferPointer(start: report, count: reportLength))
            print("input report id=\(reportID) len=\(reportLength) \(probe.hex(probe.response ?? []))")
            CFRunLoopStop(CFRunLoopGetCurrent())
        }, Unmanaged.passUnretained(self).toOpaque())

        let tests: [(String, [UInt8])] = [
            ("protocol", [0x01]),
            ("backlight brightness", [0x08, 0x01, 0x01]),
            ("backlight effect", [0x08, 0x01, 0x02]),
            ("rgblight brightness", [0x08, 0x02, 0x01]),
            ("rgblight effect", [0x08, 0x02, 0x02]),
            ("rgblight speed", [0x08, 0x02, 0x03]),
            ("rgblight color", [0x08, 0x02, 0x04]),
            ("rgb matrix brightness", [0x08, 0x03, 0x01]),
            ("rgb matrix effect", [0x08, 0x03, 0x02]),
            ("rgb matrix speed", [0x08, 0x03, 0x03]),
            ("rgb matrix color", [0x08, 0x03, 0x04]),
            ("led matrix brightness", [0x08, 0x05, 0x01]),
            ("led matrix effect", [0x08, 0x05, 0x02]),
            ("led matrix speed", [0x08, 0x05, 0x03])
        ]

        for (label, payload) in tests {
            response = nil
            print("request \(label)")
            send(payload, to: device)
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.5, false)
            if response == nil {
                print("  no response")
            }
            usleep(50_000)
        }
        return 0
    }

    private func send(_ payload: [UInt8], to device: IOHIDDevice) {
        var request = [UInt8](repeating: 0, count: 32)
        for (index, byte) in payload.enumerated() where index < request.count {
            request[index] = byte
        }
        let status = request.withUnsafeBytes {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0), $0.bindMemory(to: UInt8.self).baseAddress!, request.count)
        }
        print("  send status: 0x\(String(status, radix: 16))")
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

exit(Probe().run())
