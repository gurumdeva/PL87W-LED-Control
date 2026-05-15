# PL87W LED Control

SPM PL87W 키보드를 USB 유선 연결에서 VIA Raw HID 로 직접 제어하는 macOS 앱.

세 가지 LED 채널(백라이트 / 전면 인디케이터 / 측면 라이트)의 효과, 밝기, 속도,
색상을 한 화면에서 조정하고 설정을 키보드 비휘발성 메모리에 저장한다.

## 설치 (배포본)

[Releases](../../releases) 페이지에서 `PL87W_LED_Control.dmg` 를 받아 마운트한 뒤,
`PL87W LED Control.app` 을 `Applications` 폴더로 드래그해 넣으면 끝.

처음 실행 시 macOS Gatekeeper 가 "확인되지 않은 개발자" 경고를 띄울 수 있다.
이 앱은 코드 서명이 없으므로 Finder 에서 앱을 우클릭 → "열기" 로 한 번 우회하면
이후엔 더블 클릭으로 실행 가능.

요구사항:
- macOS 13 (Ventura) 이상
- USB 유선 연결 (Bluetooth 모드에서는 LED 제어용 Raw HID 가 노출되지 않음)

## 빌드 (소스에서)

```bash
chmod +x build.sh
./build.sh
open "build/PL87W LED Control.app"
```

처음 빌드 시 `AppIcon.icns` 가 없으면 자동으로 `Sources/Tools/IconGenerator.swift`
를 컴파일·실행해 아이콘을 만든다.

배포용 DMG 가 필요하면:

```bash
chmod +x make_dmg.sh
./make_dmg.sh
# → build/PL87W_LED_Control.dmg
```

HID 진단용 보조 도구 (선택):

```bash
./probe.sh    # PL87W 의 VIA Raw HID 응답을 헥사덤프
./scan-hid.sh # 시스템의 모든 HID 디바이스 나열
```

## 아키텍처

MVVM + 단방향 데이터 흐름. AppKit 기반, 외부 의존성 0.

```
Sources/
├── AppLauncher.swift         # @main 진입점
├── AppDelegate.swift         # @MainActor binder — 윈도우 + ViewModel 옵저빙
├── Models/
│   ├── Models.swift          # Via 타입, EffectPreset, ColorPreset, ChannelCapabilities
│   └── LightingCatalog.swift # PL87W 채널 정의 (정적 데이터)
├── Services/
│   ├── LightingDevice.swift  # 디바이스 추상화 protocol  ← 새 기기 추가 진입점
│   ├── PL87WDevice.swift     # PL87W 구현 (@MainActor, async)
│   └── ViaHIDController.swift# IOKit Raw HID 래퍼 (callback → continuation)
├── ViewModels/
│   ├── Observable.swift      # Subscription RAII + `.store(in:)` 패턴
│   ├── AppViewModel.swift    # 전역 상태 + 자동 reconnect + dirty flag
│   └── ChannelViewModel.swift# 채널별 상태 + async intent
└── Views/                    # 모두 ViewModel 옵저빙으로 자동 업데이트
    ├── ChannelPanel.swift
    ├── ChannelTabView.swift
    ├── StatusBarView.swift
    ├── DisconnectedView.swift
    ├── ToastView.swift
    ├── AmbientBackgroundView.swift
    ├── GradientSlider.swift
    ├── ColorSwatch.swift
    └── AccentButton.swift
```

### 데이터 흐름

```
사용자가 슬라이더 드래그 (mouseUp)
   ↓ Intent
ChannelViewModel.setBrightness(value)  ── async ──┐
                                                  │
                                  await device.write(...)
                                                  │
                                  성공 시 Observable.value = value
                                                  ↓ didSet
                                  View 가 옵저빙 중인 listener 자동 호출
                                  → 슬라이더/라벨/배경 글로우 갱신
```

### 자동 연결 감지

`PL87WDevice` 가 별도 IOHIDManager 로 매칭/제거 callback 을 등록하고
`AsyncStream<ConnectionEvent>` 로 발사한다. USB 가 분리·재연결되면 화면이
자동으로 disconnected ↔ connected 로 전환된다. 사용자가 막 변경한 값을
자동 reload 가 덮어쓰지 않도록 5 초 dirty-window 가 보호한다.

## 다른 키보드 추가하기

`LightingDevice` protocol 만 구현하면 ViewModel/View 코드 수정 없이 새 기기를 붙일 수 있다.

```swift
@MainActor
final class MyKeyboardDevice: LightingDevice {
    let connectionEvents: AsyncStream<ConnectionEvent> = ...

    func connect() async -> Bool { ... }
    func reset() async { ... }
    func capabilities(of channel: ViaLightingChannel) async -> ChannelCapabilities? { ... }
    func read(channel: ViaLightingChannel) async -> ViaLightingState { ... }
    func loadStates(for sections: [LightingSection]) async -> [...]? { ... }
    func write(channel:value:bytes:) async -> Bool { ... }
    func save(channel:) async -> Bool { ... }
}
```

그리고 `Models/LightingCatalog.swift` 에 해당 기기의 채널·효과·강조 색을 정의해
`AppViewModel(sections: ..., device: MyKeyboardDevice())` 로 주입.

## PL87W Raw HID 참고

- Vendor ID: `0x36B0`
- Product ID: `0x3031`
- Usage Page: `0xFF60`
- Usage: `0x61`
- VIA Protocol: `0x000C`

채널 매핑 (제조사 배포 `PL87W.JSON` 의 VIA 메뉴 정의 기준):

| 채널 | raw value | 설명 |
|---|---|---|
| `rgbLight` | 2 | 전면 인디케이터 |
| `rgbMatrix` | 3 | 백라이트 |
| `sideLight` | 4 | 측면 라이트 |

전면/측면은 7 종 효과 (`none`, `wave`, `fixed wave`, `spectrum`, `breathe`, `light`,
`shutdown`), 백라이트는 46 종 QMK rgb_matrix 효과를 지원한다.

## 라이선스

MIT.
