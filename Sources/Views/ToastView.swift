import AppKit

/// 윈도우 하단에 잠깐 떴다가 사라지는 상태 메시지.
///
/// `AppViewModel.toast` 옵저버블을 직접 구독해 새 메시지가 도착할 때마다
/// 페이드 인 → 유지 → 페이드 아웃을 자기가 알아서 처리한다.
final class ToastView: NSTextField {

    private enum Timing {
        static let fadeIn: TimeInterval = 0.15
        static let visible: TimeInterval = 2.4
        static let fadeOut: TimeInterval = 0.45
    }

    private var fadeOutWork: DispatchWorkItem?
    private var subscriptions = Set<Subscription>()

    init(viewModel: AppViewModel) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isEditable = false
        isBezeled = false
        drawsBackground = false
        isSelectable = false
        alignment = .center
        font = .systemFont(ofSize: 11)
        textColor = .tertiaryLabelColor
        alphaValue = 0

        // 토스트는 일회성 이벤트라서 초기 값(nil)으로 발사되면 안 된다.
        viewModel.toast.observeChanges { [weak self] message in
            guard let self, let message else { return }
            self.show(message)
        }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func show(_ message: ToastMessage) {
        // 이전 토스트가 페이드 아웃 대기 중이면 취소하고 새 토스트로 덮어쓴다.
        fadeOutWork?.cancel()

        stringValue = message.text
        textColor = message.isError ? .systemRed : .secondaryLabelColor
        alphaValue = 0
        animate(to: 1.0, duration: Timing.fadeIn)

        let work = DispatchWorkItem { [weak self] in
            self?.animate(to: 0, duration: Timing.fadeOut)
        }
        fadeOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.visible, execute: work)
    }

    private func animate(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = alpha
        }
    }
}
