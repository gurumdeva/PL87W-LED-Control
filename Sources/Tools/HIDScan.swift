import Foundation
import IOKit.hid

final class Scanner {
    private var manager: IOHIDManager!
    private var response: [UInt8]?

    func run() -> Int32 {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x36B0,
            kIOHIDProductIDKey: 0x3031,
            kIOHIDPrimaryUsagePageKey: 0xFF60,
            kIOHIDPrimaryUsageKey: 0x61
        ] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            print("raw HID device not found")
            return 1
        }

        let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        inputBuffer.initialize(repeating: 0, count: 32)
        defer { inputBuffer.deallocate() }

        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 32, { context, _, _, _, _, report, reportLength in
            guard let context else { return }
            let scanner = Unmanaged<Scanner>.fromOpaque(context).takeUnretainedValue()
            scanner.response = Array(UnsafeBufferPointer(start: report, count: reportLength))
        }, Unmanaged.passUnretained(self).toOpaque())

        for channel in UInt8(0)...UInt8(15) {
            var hits: [String] = []
            for value in UInt8(1)...UInt8(80) {
                response = nil
                send([0x08, channel, value], to: device)
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
                guard let response, response.count >= 4 else { continue }
                if response[0] != 0xFF {
                    let data = response.dropFirst(3).prefix(4).map { String(format: "%02x", $0) }.joined(separator: " ")
                    hits.append("\(value):\(data)")
                }
            }
            if !hits.isEmpty {
                print("channel \(channel): \(hits.joined(separator: ", "))")
            }
        }
        return 0
    }

    private func send(_ payload: [UInt8], to device: IOHIDDevice) {
        var report = [UInt8](repeating: 0, count: 32)
        for (index, byte) in payload.enumerated() {
            report[index] = byte
        }
        report.withUnsafeBytes {
            _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0), $0.bindMemory(to: UInt8.self).baseAddress!, report.count)
        }
    }
}

exit(Scanner().run())
