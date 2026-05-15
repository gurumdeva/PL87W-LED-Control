import AppKit

/// PL87W 펌웨어가 지원하는 채널별 메뉴 정의.
///
/// 화면이 채널별로 거의 동일해 보이지만 사실상 달라지는 부분이 모두 이 카탈로그에 있다.
/// UI 쪽은 이 데이터를 받아 그대로 그리기만 한다. 다른 키보드 모델을 붙이려면
/// 이 파일만 새로 작성하면 된다.
enum LightingCatalog {

    // MARK: 전면 인디케이터 / 측면 라이트가 공유하는 7 종 효과
    private static let customLightPresets: [EffectPreset] = [
        EffectPreset(name: "none",       value: 0),
        EffectPreset(name: "wave",       value: 1),
        EffectPreset(name: "fixed wave", value: 2),
        EffectPreset(name: "spectrum",   value: 3),
        EffectPreset(name: "breathe",    value: 4),
        EffectPreset(name: "light",      value: 5),
        EffectPreset(name: "shutdown",   value: 6)
    ]

    // MARK: RGB 매트릭스(백라이트)의 46 종 효과
    private static let rgbMatrixPresets: [EffectPreset] = [
        EffectPreset(name: "none",                       value: 0),
        EffectPreset(name: "solid_color",                value: 1),
        EffectPreset(name: "alphas_mods",                value: 2),
        EffectPreset(name: "gradient_up_down",           value: 3),
        EffectPreset(name: "gradient_left_right",        value: 4),
        EffectPreset(name: "breathing",                  value: 5),
        EffectPreset(name: "band_sat",                   value: 6),
        EffectPreset(name: "band_val",                   value: 7),
        EffectPreset(name: "band_pinwheel_sat",          value: 8),
        EffectPreset(name: "band_pinwheel_val",          value: 9),
        EffectPreset(name: "band_spiral_sat",            value: 10),
        EffectPreset(name: "band_spiral_val",            value: 11),
        EffectPreset(name: "cycle_all",                  value: 12),
        EffectPreset(name: "cycle_left_right",           value: 13),
        EffectPreset(name: "cycle_up_down",              value: 14),
        EffectPreset(name: "cycle_out_in",               value: 15),
        EffectPreset(name: "cycle_out_in_dual",          value: 16),
        EffectPreset(name: "rainbow_moving_chevron",     value: 17),
        EffectPreset(name: "cycle_pinwheel",             value: 18),
        EffectPreset(name: "cycle_spiral",               value: 19),
        EffectPreset(name: "dual_beacon",                value: 20),
        EffectPreset(name: "rainbow_beacon",             value: 21),
        EffectPreset(name: "rainbow_pinwheels",          value: 22),
        EffectPreset(name: "flower_blooming",            value: 23),
        EffectPreset(name: "raindrops",                  value: 24),
        EffectPreset(name: "jellybean_raindrops",        value: 25),
        EffectPreset(name: "hue_breathing",              value: 26),
        EffectPreset(name: "hue_pendulum",               value: 27),
        EffectPreset(name: "hue_wave",                   value: 28),
        EffectPreset(name: "pixel_flow",                 value: 29),
        EffectPreset(name: "digital_rain",               value: 30),
        EffectPreset(name: "solid_reactive",             value: 31),
        EffectPreset(name: "solid_reactive_wide",        value: 32),
        EffectPreset(name: "solid_reactive_multiwide",   value: 33),
        EffectPreset(name: "solid_reactive_cross",       value: 34),
        EffectPreset(name: "solid_reactive_multicross",  value: 35),
        EffectPreset(name: "solid_reactive_nexus",       value: 36),
        EffectPreset(name: "solid_reactive_multinexus",  value: 37),
        EffectPreset(name: "splash",                     value: 38),
        EffectPreset(name: "multisplash",                value: 39),
        EffectPreset(name: "solid_splash",               value: 40),
        EffectPreset(name: "solid_multisplash",          value: 41),
        EffectPreset(name: "starlight",                  value: 42),
        EffectPreset(name: "starlight_dual_hue",         value: 43),
        EffectPreset(name: "starlight_dual_sat",         value: 44),
        EffectPreset(name: "riverflow",                  value: 45)
    ]

    /// 화면 순서대로 정렬된 PL87W 의 채널 정의.
    static let sections: [LightingSection] = [
        LightingSection(
            title: "백라이트",
            shortTitle: "백라이트",
            iconSymbol: "keyboard",
            channel: .rgbMatrix,
            presets: rgbMatrixPresets,
            brightnessMax: 200,
            speedMax: 255,
            accentColor: .systemBlue
        ),
        LightingSection(
            title: "전면 인디케이터",
            shortTitle: "전면",
            iconSymbol: "lightbulb",
            channel: .rgbLight,
            presets: customLightPresets,
            brightnessMax: 200,
            speedMax: 4,
            accentColor: .systemMint
        ),
        LightingSection(
            title: "측면 라이트",
            shortTitle: "측면",
            iconSymbol: "rectangle.split.3x1",
            channel: .sideLight,
            presets: customLightPresets,
            brightnessMax: 200,
            speedMax: 4,
            accentColor: .systemPurple
        )
    ]
}
