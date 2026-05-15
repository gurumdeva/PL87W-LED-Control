import Foundation

/// 단방향 바인딩을 위한 미니 옵저버블.
///
/// Combine 의 `@Published` 와 유사하지만 의존성 없이 한 파일로 끝낸다.
/// AppKit 의 메인 스레드 전용으로 가정한다 — 멀티스레드 동기화는 하지 않는다.
///
/// ## 라이프사이클 (RAII)
/// `observe` 가 반환하는 `Subscription` 은 호출자가 보관해야 listener 가 살아 있다.
/// `Subscription` 이 dealloc 되면 자동으로 `cancel()` 이 호출되어 listener 는
/// 즉시 entries 에서 제거된다. 일반적 패턴:
///
/// ```swift
/// private var subscriptions = Set<Subscription>()
/// viewModel.effect.observe { ... }.store(in: &subscriptions)
/// ```
///
/// View 가 dealloc 되면 `subscriptions` 도 함께 사라져 listener leak 이 없다.
///
/// ## 재진입 안전성
/// listener 호출 도중에 다른 listener 가 추가/제거되어도 안전 (snapshot 순회).
final class Observable<T> {
    typealias Listener = (T) -> Void

    private struct Entry {
        let token: UUID
        let listener: Listener
    }

    private var entries: [Entry] = []

    var value: T {
        didSet { notify() }
    }

    init(_ value: T) {
        self.value = value
    }

    /// 리스너를 등록하고 현재 값을 즉시 한 번 흘려보낸다.
    func observe(_ listener: @escaping Listener) -> Subscription {
        let token = appendEntry(listener)
        listener(value)
        return makeSubscription(token: token)
    }

    /// 초기 발사를 건너뛴다. 일회성 이벤트(토스트 등)에 유용.
    func observeChanges(_ listener: @escaping Listener) -> Subscription {
        let token = appendEntry(listener)
        return makeSubscription(token: token)
    }

    private func appendEntry(_ listener: @escaping Listener) -> UUID {
        let token = UUID()
        entries.append(Entry(token: token, listener: listener))
        return token
    }

    private func makeSubscription(token: UUID) -> Subscription {
        Subscription { [weak self] in
            self?.entries.removeAll { $0.token == token }
        }
    }

    private func notify() {
        // 리스너가 새 리스너를 등록/취소하거나 value 를 다시 set 해도 안전하도록,
        // 현재 순간의 스냅샷을 만들어 두고 그 위에서 호출한다.
        let snapshot = entries
        for entry in snapshot {
            entry.listener(value)
        }
    }
}

/// `Observable.observe` 의 결과 핸들.
///
/// - **RAII**: 호출자가 보관하지 않아 dealloc 되면 자동으로 cancel — listener 도 함께 해제됨.
///   호출자 (보통 View) 가 dealloc 되면 listener 가 entries 에 leak 되는 일이 없다.
/// - **명시적 cancel**: 라이프사이클이 끝나기 전에 미리 끊고 싶으면 `cancel()`.
/// - **`store(in:)`**: View 가 `Set<Subscription>` 한 곳에 모아 두는 표준 패턴.
final class Subscription: Hashable {
    private let onCancel: () -> Void
    private var cancelled = false

    init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        cancel()
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }

    /// Combine 의 `store(in:)` 과 동일한 호출 패턴. View 가 한 곳에 모아 두면
    /// View dealloc 시 set 전체가 사라지며 모든 listener 가 한꺼번에 해제된다.
    func store(in set: inout Set<Subscription>) {
        set.insert(self)
    }

    static func == (lhs: Subscription, rhs: Subscription) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
