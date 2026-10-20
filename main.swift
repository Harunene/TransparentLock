// TransparentLock — 화면은 살짝 흐리고 어둡게 보이게 두고 입력만 막는 잠금.
// Touch ID(또는 로그인 암호)로 인증해야 해제된다.
//
// 사용: TransparentLock.app 실행 → 바로 잠금
//       ⌥(Option) 누른 채 실행, 또는 --settings → 설정 창
//       테스트용 자동 해제: TransparentLock.app/Contents/MacOS/TransparentLock --test 30
//       일회성 값 지정:     ... --blur 4 --dim 0.4   (설정보다 우선)

import Cocoa
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

func argValue(_ name: String) -> Double? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return Double(args[i + 1])
}

enum Settings {
    static let defaults: UserDefaults = {
        let d = UserDefaults.standard
        d.register(defaults: ["blur": 4.0, "dim": 0.4])
        return d
    }()
    static var blur: Double {
        get { defaults.double(forKey: "blur") }
        set { defaults.set(newValue, forKey: "blur") }
    }
    static var dim: Double {
        get { defaults.double(forKey: "dim") }
        set { defaults.set(newValue, forKey: "dim") }
    }
}

// 창 뒤 배경 흐림 반경을 직접 지정하는 비공개 API(iTerm2 등이 쓰는 것). 없으면 false.
private typealias SetBlurFn = @convention(c) (UInt32, UInt32, Int32) -> Int32
private typealias MainConnFn = @convention(c) () -> UInt32

func setBackgroundBlur(_ window: NSWindow, radius: Int) -> Bool {
    guard let setSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetWindowBackgroundBlurRadius"),
          let connSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSMainConnectionID")
    else { return false }
    let setBlur = unsafeBitCast(setSym, to: SetBlurFn.self)
    let mainConn = unsafeBitCast(connSym, to: MainConnFn.self)
    return setBlur(mainConn(), UInt32(window.windowNumber), Int32(radius)) == 0
}

final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 모든 마우스·키 입력을 삼키는 뷰. 클릭하면 Touch ID 인증을 다시 시작한다.
final class BlockingView: NSView {
    var onClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [LockWindow] = []
    private var authHost: NSView!
    private var authView: LAAuthenticationView?
    private var statusLabel: NSTextField!
    private var context: LAContext?
    private var authenticating = false
    private var usingPassword = false
    private var locked = false

    private var settingsWindow: NSWindow?
    private var blurValueLabel: NSTextField!
    private var dimValueLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSEvent.modifierFlags.contains(.option) || CommandLine.arguments.contains("--settings") {
            showSettings()
        } else {
            lock(blur: argValue("--blur") ?? Settings.blur,
                 dim: argValue("--dim") ?? Settings.dim,
                 autoUnlockAfter: argValue("--test"))
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        locked ? .terminateCancel : .terminateNow
    }

    // MARK: - 설정 창

    private func showSettings() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "TransparentLock 설정"
        w.delegate = self

        let blurSlider = NSSlider(value: Settings.blur, minValue: 0, maxValue: 20,
                                  target: self, action: #selector(blurChanged(_:)))
        let dimSlider = NSSlider(value: Settings.dim, minValue: 0, maxValue: 0.9,
                                 target: self, action: #selector(dimChanged(_:)))
        blurValueLabel = NSTextField(labelWithString: "")
        dimValueLabel = NSTextField(labelWithString: "")
        [blurValueLabel, dimValueLabel].forEach {
            $0?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            $0?.alignment = .right
        }
        updateValueLabels()

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "흐림"), blurSlider, blurValueLabel],
            [NSTextField(labelWithString: "어둡기"), dimSlider, dimValueLabel],
        ])
        grid.column(at: 1).width = 260
        grid.column(at: 2).width = 40
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline

        let testButton = NSButton(title: "5초 미리보기", target: self, action: #selector(previewLock))
        let lockButton = NSButton(title: "지금 잠그기", target: self, action: #selector(lockNow))
        lockButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [testButton, lockButton])
        buttons.spacing = 8

        let hint = NSTextField(labelWithString: "설정 창은 ⌥(Option)을 누른 채 앱을 실행하면 열립니다.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [grid, buttons, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        w.contentView = stack

        w.center()
        settingsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func updateValueLabels() {
        blurValueLabel.stringValue = String(format: "%.0f", Settings.blur)
        dimValueLabel.stringValue = String(format: "%.2f", Settings.dim)
    }

    @objc private func blurChanged(_ sender: NSSlider) {
        Settings.blur = sender.doubleValue.rounded()
        updateValueLabels()
    }

    @objc private func dimChanged(_ sender: NSSlider) {
        Settings.dim = (sender.doubleValue * 20).rounded() / 20
        updateValueLabels()
    }

    @objc private func previewLock() {
        settingsWindow?.orderOut(nil)
        lock(blur: Settings.blur, dim: Settings.dim, autoUnlockAfter: 5)
    }

    @objc private func lockNow() {
        settingsWindow?.orderOut(nil)
        lock(blur: Settings.blur, dim: Settings.dim, autoUnlockAfter: nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow { NSApp.terminate(nil) }
    }

    // MARK: - 잠금

    private func lock(blur: Double, dim: Double, autoUnlockAfter seconds: Double?) {
        locked = true
        NSApp.presentationOptions = [
            .autoHideDock, .disableProcessSwitching, .disableForceQuit,
            .disableSessionTermination, .disableHideApplication,
        ]

        let dimAlpha = min(max(dim, 0.01), 1)
        windows = NSScreen.screens.map {
            makeWindow(for: $0, dim: dimAlpha, withPanel: $0 == NSScreen.main)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()
        if blur > 0 {
            for w in windows where !setBackgroundBlur(w, radius: Int(blur)) {
                addFallbackBlur(to: w)
            }
        }

        // 다른 앱이나 Spotlight 등으로 포커스가 넘어가면 다시 가져온다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.locked, !self.usingPassword else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.windows.forEach { $0.orderFrontRegardless() }
        }

        if let seconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.unlock() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.startBiometric() }
    }

    private func makeWindow(for screen: NSScreen, dim: Double, withPanel: Bool) -> LockWindow {
        let w = LockWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.level = .screenSaver
        w.isOpaque = false
        // 어둡게 덮는 정도. 완전 투명(0)이면 클릭이 아래로 통과하므로 최소 0.01은 유지한다.
        w.backgroundColor = NSColor.black.withAlphaComponent(dim)
        w.ignoresMouseEvents = false
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let blocker = BlockingView(frame: NSRect(origin: .zero, size: screen.frame.size))
        blocker.autoresizingMask = [.width, .height]
        blocker.onClick = { [weak self] in self?.startBiometric() }
        w.contentView = blocker
        w.initialFirstResponder = blocker
        if withPanel { addPanel(to: blocker) }
        return w
    }

    /// 비공개 API를 못 쓸 때: 시스템 흐림 효과를 반투명하게 깔아 약한 흐림처럼 보이게 한다.
    private func addFallbackBlur(to window: NSWindow) {
        guard let content = window.contentView else { return }
        let fx = NSVisualEffectView(frame: content.bounds)
        fx.autoresizingMask = [.width, .height]
        fx.material = .fullScreenUI
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.alphaValue = 0.6
        content.addSubview(fx, positioned: .below, relativeTo: nil)
    }

    private func addPanel(to parent: NSView) {
        let panel = NSVisualEffectView()
        panel.material = .hudWindow
        panel.blendingMode = .behindWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(panel)

        authHost = NSView()
        authHost.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "🔒 Touch ID로 잠금 해제")
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .labelColor

        let pwButton = NSButton(title: "암호 사용", target: self, action: #selector(usePassword))
        pwButton.bezelStyle = .rounded
        pwButton.controlSize = .small

        let stack = NSStackView(views: [authHost, statusLabel, pwButton])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            authHost.widthAnchor.constraint(equalToConstant: 32),
            authHost.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
            panel.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            panel.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -60),
        ])
    }

    private func setStatus(_ text: String) { statusLabel?.stringValue = text }

    /// 창 안에 내장된 Touch ID 뷰로 인증한다(시스템 대화상자가 잠금 창 뒤에 가려지지 않도록).
    private func startBiometric() {
        guard !authenticating, !usingPassword, locked else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            setStatus("Touch ID 사용 불가 — 암호로 해제하세요")
            return
        }
        authView?.removeFromSuperview()
        let view = LAAuthenticationView(context: ctx, controlSize: .regular)
        view.frame = authHost.bounds
        view.autoresizingMask = [.width, .height]
        authHost.addSubview(view)
        authView = view
        context = ctx
        authenticating = true
        setStatus("🔒 Touch ID로 잠금 해제")

        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "화면 잠금 해제") { ok, error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.authenticating = false
                if ok { self.unlock(); return }
                switch (error as? LAError)?.code {
                case .biometryLockout:
                    self.setStatus("Touch ID 잠김 — 암호로 해제하세요")
                case .authenticationFailed:
                    self.setStatus("인식 실패 — 화면을 클릭해 다시 시도")
                default:
                    // 시간 초과·취소 등은 잠시 뒤 자동으로 다시 대기
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.startBiometric() }
                }
            }
        }
    }

    @objc private func usePassword() {
        guard !usingPassword, locked else { return }
        context?.invalidate()
        authenticating = false
        usingPassword = true
        // 시스템 암호 대화상자가 보이도록 잠깐 창 레벨을 내린다(우리 앱이 최전면이라 입력은 계속 막힘).
        windows.forEach { $0.level = .normal }

        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "화면 잠금을 해제합니다") { ok, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.usingPassword = false
                if ok { self.unlock(); return }
                self.windows.forEach { $0.level = .screenSaver; $0.orderFrontRegardless() }
                NSApp.activate(ignoringOtherApps: true)
                self.startBiometric()
            }
        }
    }

    private func unlock() {
        guard locked else { return }
        locked = false
        context?.invalidate()
        NSApp.presentationOptions = []
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
