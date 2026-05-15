import AppKit

// MARK: - VIA protocol

/// 펌웨어가 노출하는 조명 채널. raw value 는 VIA 명령에 그대로 실린다.
enum ViaLightingChannel: UInt8 {
    case rgbLight = 2
    case rgbMatrix = 3
    case sideLight = 4
}

/// 한 채널 안에서 조작 가능한 항목.
enum ViaLightingValue: UInt8 {
    case brightness = 1
    case effect = 2
    case speed = 3
    case color = 4

    var label: String {
        switch self {
        case .brightness: return "밝기"
        case .effect: return "효과"
        case .speed: return "속도"
        case .color: return "색상"
        }
    }
}

/// 한 채널의 전체 상태 스냅샷. HID 에서 한 번 읽어와 메모리에 캐시한다.
struct ViaLightingState {
    let brightness: UInt8
    let effect: UInt8
    let speed: UInt8
    let hue: UInt8
    let saturation: UInt8

    static let fallback = ViaLightingState(brightness: 180, effect: 1, speed: 128, hue: 0, saturation: 255)
}

// MARK: - UI 카탈로그

/// 효과 프리셋 한 개. UI 의 popup 항목과 HID payload 가 1:1 매핑된다.
///
/// `name` 은 펌웨어 식별자 (snake_case, VIA JSON 정의 그대로) — 디버깅/로그용.
/// 화면 표시는 `displayName` 을 통해 사람이 읽기 좋은 "Title Case" 로 자동 변환된다.
struct EffectPreset {
    let name: String
    let value: UInt8

    /// `solid_color` → `Solid Color`, `fixed wave` → `Fixed Wave` 처럼 변환.
    /// 단어 구분자(`_`, 공백)를 공백으로 통일하고 각 단어 첫 글자만 대문자로.
    var displayName: String {
        name
            .split(whereSeparator: { $0 == "_" || $0 == " " })
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

/// 화면 한 개(= 한 채널)를 그리는 데 필요한 모든 정보.
/// 채널마다 달라지는 부분(프리셋 목록, 최대값, 강조 색상)이 여기 다 모인다.
struct LightingSection {
    let title: String
    let shortTitle: String
    let iconSymbol: String
    let channel: ViaLightingChannel
    let presets: [EffectPreset]
    let brightnessMax: Double
    let speedMax: Double
    let accentColor: NSColor
}

/// 디바이스가 펌웨어 capability 조회로 알려주는 채널 범위 정보.
///
/// `LightingSection.brightnessMax/speedMax` 가 카탈로그 fallback 이라면,
/// `ChannelCapabilities` 는 펌웨어가 실제로 보고하는 동적 값이다. 두 값이 다르면
/// View 는 capability 를 우선 사용해 슬라이더 max 를 그려 준다.
struct ChannelCapabilities {
    let brightnessRange: ClosedRange<UInt8>
    let speedRange: ClosedRange<UInt8>
}

/// 색상 팔레트의 한 칸. hue/saturation 은 VIA payload 형식 그대로(0-255).
struct ColorPreset {
    let name: String
    let hue: UInt8
    let saturation: UInt8

    static let palette: [ColorPreset] = [
        ColorPreset(name: "Coral",    hue: 5,   saturation: 95),
        ColorPreset(name: "Peach",    hue: 22,  saturation: 90),
        ColorPreset(name: "Lemon",    hue: 42,  saturation: 95),
        ColorPreset(name: "Mint",     hue: 95,  saturation: 85),
        ColorPreset(name: "Sky",      hue: 138, saturation: 85),
        ColorPreset(name: "Lavender", hue: 188, saturation: 80),
        ColorPreset(name: "Rose",     hue: 232, saturation: 95)
    ]

    var color: NSColor {
        NSColor(
            hue: CGFloat(hue) / 255.0,
            saturation: CGFloat(saturation) / 255.0,
            brightness: 1.0,
            alpha: 1.0
        )
    }
}
