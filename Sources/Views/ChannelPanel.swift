import AppKit

/// 한 채널의 컨트롤 묶음 (효과 / 밝기 / 속도 / 색상 / 저장).
///
/// MVVM 의 View — 자체 상태를 들지 않는다.
/// - 사용자 액션이 발생하면 `ChannelViewModel` 의 인텐트 메서드를 호출한다.
/// - ViewModel 의 옵저버블을 `bind...` 메서드로 옵저빙해 자동으로 자기 모양을 맞춘다.
///
/// 채널 간 차이(프리셋 목록, 최대값, 강조 색상)는 `viewModel.section` 에 다 들어있어
/// 패널 코드 자체에는 채널별 분기가 없다.
final class ChannelPanel: NSView {

    let viewModel: ChannelViewModel

    // MARK: - 자식 컨트롤
    private let effectPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let brightnessSlider = GradientSlider()
    private let speedSlider = GradientSlider()
    private let brightnessValueLabel = NSTextField(labelWithString: "0")
    private let speedValueLabel = NSTextField(labelWithString: "0")
    private var presetSwatches: [(preset: ColorPreset, view: ColorSwatch)] = []
    private let pickerSwatch = ColorSwatch()
    private let saveButton: AccentButton

    /// 사용자가 + 스와치를 눌렀을 때의 후크. AppDelegate 가 NSColorPanel 을 띄운다.
    var onRequestColorPicker: (() -> Void)?

    /// ViewModel 옵저버블 구독. self 가 dealloc 되면 함께 사라짐.
    private var subscriptions = Set<Subscription>()

    init(viewModel: ChannelViewModel) {
        self.viewModel = viewModel
        self.saveButton = AccentButton(title: "현재 설정 저장", symbolName: "tray.and.arrow.down")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
        bindViewModel()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View → ViewModel binding
    //
    // ViewModel 의 옵저버블이 바뀌면 컨트롤 모양을 맞춘다.
    // weak self 캡처로 라이프사이클이 view 와 같이 끝난다.

    private func bindViewModel() {
        viewModel.effect.observe { [weak self] value in
            self?.updateEffectSelection(value)
        }.store(in: &subscriptions)

        // brightness/speed 와 effectiveMax 가 함께 바뀔 수 있으므로 양쪽 옵저빙 모두에서
        // 같은 reapply 함수를 호출 — 슬라이더 range/value, 라벨 텍스트/색상 일관 유지.
        viewModel.brightness.observe { [weak self] _ in
            self?.applyBrightnessDisplay()
        }.store(in: &subscriptions)
        viewModel.effectiveBrightnessMax.observe { [weak self] _ in
            self?.applyBrightnessDisplay()
        }.store(in: &subscriptions)

        viewModel.speed.observe { [weak self] _ in
            self?.applySpeedDisplay()
        }.store(in: &subscriptions)
        viewModel.effectiveSpeedMax.observe { [weak self] _ in
            self?.applySpeedDisplay()
        }.store(in: &subscriptions)

        viewModel.color.observe { [weak self] _ in
            self?.refreshSwatchHighlights()
        }.store(in: &subscriptions)
    }

    /// 슬라이더 max 와 현재 값을 동시 반영 + 한도 초과 시 라벨에 시각 신호.
    private func applyBrightnessDisplay() {
        applySliderDisplay(
            value: viewModel.brightness.value,
            max: viewModel.effectiveBrightnessMax.value,
            slider: brightnessSlider,
            label: brightnessValueLabel
        )
    }

    private func applySpeedDisplay() {
        applySliderDisplay(
            value: viewModel.speed.value,
            max: viewModel.effectiveSpeedMax.value,
            slider: speedSlider,
            label: speedValueLabel
        )
    }

    /// 공통 표시 로직: 슬라이더 maxValue 동적 조정 + 핸들 위치 clamp + 라벨에 실제 값
    /// + over-range 면 라벨 색상으로 경고.
    private func applySliderDisplay(value: UInt8, max: UInt8, slider: GradientSlider, label: NSTextField) {
        slider.maxValue = Double(max)
        // 핸들은 max 까지만 — 라벨이 실제 값을 보여주므로 정보는 손실 없음.
        slider.value = Double(Swift.min(value, max))
        label.stringValue = "\(value)"
        let overRange = value > max
        label.textColor = overRange ? .systemOrange : .secondaryLabelColor
    }

    private func updateEffectSelection(_ value: UInt8) {
        // 카탈로그에 없는 값이 들어왔다 해도 (ViewModel 이 보정해 줘서 거의 발생 안 함)
        // 안전하게 0번 항목 fallback. popup 자체가 비어 있으면 noop.
        let presets = viewModel.section.presets
        guard !presets.isEmpty else { return }
        let index = presets.firstIndex(where: { $0.value == value }) ?? 0
        effectPopup.selectItem(at: index)
    }

    private func refreshSwatchHighlights() {
        var matched = false
        for entry in presetSwatches {
            let on = viewModel.isPresetSelected(entry.preset)
            entry.view.isHighlighted = on
            if on { matched = true }
        }
        pickerSwatch.isHighlighted = !matched
    }

    // MARK: - Layout

    private func setupLayout() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stack.addArrangedSubview(makeHeader("EFFECT"))
        configureEffectPopup()
        stack.addArrangedSubview(effectPopup)
        // NSPopUpButton 은 hugging priority 만으로는 stack 폭에 맞춰 늘어나지 않아
        // (cell 레벨에서 너비를 잡는다) widthAnchor 를 직접 묶는다.
        effectPopup.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: effectPopup)

        stack.addArrangedSubview(makeHeader("BRIGHTNESS", value: brightnessValueLabel))
        // maxValue 는 effectiveBrightnessMax 옵저버블이 동적으로 set. 여기선 색상/콜백만.
        configureSlider(brightnessSlider, valueLabel: brightnessValueLabel) {
            [weak self] v in
            Task { [weak self] in await self?.viewModel.setBrightness(UInt8(clamping: v)) }
        }
        stack.addArrangedSubview(brightnessSlider)
        stack.setCustomSpacing(18, after: brightnessSlider)

        stack.addArrangedSubview(makeHeader("SPEED", value: speedValueLabel))
        configureSlider(speedSlider, valueLabel: speedValueLabel) {
            [weak self] v in
            Task { [weak self] in await self?.viewModel.setSpeed(UInt8(clamping: v)) }
        }
        stack.addArrangedSubview(speedSlider)
        stack.setCustomSpacing(18, after: speedSlider)

        stack.addArrangedSubview(makeHeader("COLOR"))
        let colorRow = makeColorRow()
        stack.addArrangedSubview(colorRow)
        stack.setCustomSpacing(22, after: colorRow)

        stack.addArrangedSubview(makeSaveRow())
    }

    private func configureEffectPopup() {
        effectPopup.translatesAutoresizingMaskIntoConstraints = false
        effectPopup.bezelStyle = .rounded
        effectPopup.controlSize = .regular
        effectPopup.target = self
        effectPopup.action = #selector(effectChanged(_:))
        effectPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for preset in viewModel.section.presets {
            effectPopup.addItem(withTitle: preset.displayName)
            effectPopup.lastItem?.representedObject = Int(preset.value)
        }
    }

    /// brightness/speed 두 슬라이더가 공유하는 셋업. 색상과 드래그 콜백만 — maxValue 는
    /// effectiveBrightnessMax/effectiveSpeedMax 옵저버블이 동적으로 설정한다.
    /// 드래그 중에는 라벨만 갱신하고, 마우스를 떼는 순간에만 ViewModel 에 인텐트.
    private func configureSlider(
        _ slider: GradientSlider,
        valueLabel: NSTextField,
        onCommit: @escaping (Int) -> Void
    ) {
        slider.minValue = 0
        slider.trackColor = viewModel.section.accentColor
        slider.onValueChanged = { newValue, finished in
            let intValue = Int(newValue.rounded())
            valueLabel.stringValue = "\(intValue)"
            if finished { onCommit(intValue) }
        }
    }

    private func makeColorRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6
        row.alignment = .centerY

        for preset in ColorPreset.palette {
            let swatch = ColorSwatch()
            swatch.swatchColor = preset.color
            swatch.heightAnchor.constraint(equalToConstant: ColorSwatch.height).isActive = true
            swatch.onClick = { [weak self] in
                Task { [weak self] in await self?.viewModel.pickPreset(preset) }
            }
            row.addArrangedSubview(swatch)
            presetSwatches.append((preset, swatch))
        }

        pickerSwatch.isPickerStyle = true
        pickerSwatch.heightAnchor.constraint(equalToConstant: 32).isActive = true
        pickerSwatch.onClick = { [weak self] in
            self?.onRequestColorPicker?()
        }
        row.addArrangedSubview(pickerSwatch)
        return row
    }

    private func makeSaveRow() -> NSView {
        saveButton.accent = viewModel.section.accentColor
        saveButton.onClick = { [weak self] in
            Task { [weak self] in await self?.viewModel.save() }
        }
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        let lead = NSView()
        lead.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let trail = NSView()
        trail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(lead)
        row.addArrangedSubview(saveButton)
        row.addArrangedSubview(trail)
        return row
    }

    /// `EFFECT`/`BRIGHTNESS` 같은 작은 캡션 + 선택적 우측 값을 한 줄로.
    private func makeHeader(_ title: String, value: NSTextField? = nil) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.attributedStringValue = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .kern: 1.4
        ])
        label.alignment = .left
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(label)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        if let value {
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = .secondaryLabelColor
            value.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(value)
        }
        return row
    }

    @objc private func effectChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? Int else { return }
        Task { [weak self] in await self?.viewModel.selectEffect(UInt8(clamping: raw)) }
    }
}
