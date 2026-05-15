import AppKit

/// 앱 진입점. `@main` 으로 표시되어 link 시 자동으로 entry point 가 된다.
///
/// `@MainActor` 격리 — AppDelegate / AppViewModel / View 가 모두 메인 actor 에
/// 들어 있어 액터 간 boundary 횡단 없이 연속 실행된다.
@main
@MainActor
enum AppLauncher {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
