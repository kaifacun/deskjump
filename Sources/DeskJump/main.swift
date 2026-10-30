import AppKit
import CGSPrivate
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var display: DisplaySpaces?
    private var refreshTimer: Timer?
    private let updater = Updater()

    //#region 레이아웃 상수
    private let cellWidth: CGFloat = 18
    private let cellHeight: CGFloat = 15
    private let cellGap: CGFloat = 3
    private let sidePadding: CGFloat = 2
    //#endregion

    //#region 앱 시작
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 첫 실행 설정: 권한 요청, 로그인 항목 등록, 직접 전환 단축키 켜기
        _ = SpaceSwitcher.isTrusted(prompt: true)
        registerLoginItemOnFirstLaunch()
        SpaceSwitcher.enableDirectHotkeysOnFirstLaunch()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        // Space 전환 시 즉시 갱신
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // 데스크탑 추가·삭제, 마우스의 모니터 이동은 알림이 없으므로 주기적으로 확인
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }

        refresh()
        runSwitchArgumentIfNeeded()

        // 새 버전이 확인되면 메뉴바에 점을 표시
        updater.onChange = { [weak self] in self?.redraw() }
        updater.startAutomaticChecks()
    }

    /// 명령줄 확인용: `open DeskJump.app --args --switch N` 으로 N번째 칸(1부터)으로 이동
    private func runSwitchArgumentIfNeeded() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--switch"), i + 1 < args.count,
              let n = Int(args[i + 1]), let display else { return }
        SpaceSwitcher.switchTo(index: n - 1, in: display)
    }
    //#endregion

    //#region 로그인 시 자동 실행
    /// 처음 실행할 때 한 번만 로그인 항목으로 등록한다. 이후 사용자가 메뉴에서 끄면 그대로 둔다
    private func registerLoginItemOnFirstLaunch() {
        let key = "didSetupLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            SpaceSwitcher.debugLog("login item register failed: \(error)")
        }
    }
    //#endregion

    //#region 상태 갱신 및 그리기
    @objc private func refresh() {
        let latest = SpaceReader.readForMouseDisplay()
        guard latest != display || statusItem.button?.image == nil else { return }
        display = latest
        redraw()
    }

    private func redraw() {
        statusItem.button?.image = renderImage(for: display)
    }

    private func renderImage(for display: DisplaySpaces?) -> NSImage {
        let spaces = display?.spaces ?? []
        let count = max(spaces.count, 1)
        let showsUpdateDot = updater.available != nil
        let cellsWidth = sidePadding * 2 + CGFloat(count) * cellWidth + CGFloat(count - 1) * cellGap
        // 업데이트 알림 점은 숫자 칸 오른쪽 위에 붙인다 (칸 위치는 그대로라 클릭 계산에 영향 없음)
        let width = cellsWidth + (showsUpdateDot ? 6 : 0)
        let height: CGFloat = 18

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { [self] _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let style = NSMutableParagraphStyle()
            style.alignment = .center

            for (i, space) in spaces.enumerated() {
                let x = sidePadding + CGFloat(i) * (cellWidth + cellGap)
                let rect = NSRect(x: x, y: (height - cellHeight) / 2, width: cellWidth, height: cellHeight)
                let isCurrent = space.id == display?.currentID
                let label = space.desktopNumber.map(String.init) ?? "F"

                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
                NSColor.black.set()
                if isCurrent {
                    path.fill()
                    // 현재 Space는 채운 상자에서 숫자를 투명하게 뚫어 표시
                    ctx.setBlendMode(.destinationOut)
                } else {
                    path.lineWidth = 1
                    path.stroke()
                }

                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style]
                let textHeight = (label as NSString).size(withAttributes: attrs).height
                let textRect = NSRect(x: rect.minX, y: rect.midY - textHeight / 2, width: rect.width, height: textHeight)
                (label as NSString).draw(in: textRect, withAttributes: attrs)
                ctx.setBlendMode(.normal)
            }

            if showsUpdateDot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: cellsWidth, y: height - 7, width: 5, height: 5)).fill()
            }
            return true
        }
        // 템플릿 이미지라 밝은/어두운 메뉴바에 자동으로 맞춰진다
        image.isTemplate = true
        return image
    }
    //#endregion

    //#region 클릭 처리
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }

        // 클릭 직전에 다른 모니터에서 넘어왔을 수 있으니 최신 상태로 다시 읽는다
        refresh()
        guard let display else { return }
        if !SpaceSwitcher.isTrusted(prompt: false) {
            showMenu()
            return
        }

        guard let localX = clickX(in: sender) else { return }
        let index = Int(floor((localX - sidePadding) / (cellWidth + cellGap)))
        SpaceSwitcher.debugLog("click localX=\(localX) index=\(index)")
        guard display.spaces.indices.contains(index) else { return }
        SpaceSwitcher.switchTo(index: index, in: display)
    }

    /// 클릭한 위치를 버튼 이미지 기준 x 좌표로 변환한다.
    /// 최신 macOS는 메뉴바 클릭을 버튼 중앙 좌표로 전달하므로 실제 마우스 위치(NSEvent.mouseLocation)를 쓴다.
    private func clickX(in button: NSStatusBarButton) -> CGFloat? {
        guard let window = button.window, let buttonScreen = window.screen else { return nil }
        let mouse = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? buttonScreen

        let xInWindow: CGFloat
        if mouseScreen == buttonScreen {
            xInWindow = mouse.x - window.frame.minX
        } else {
            // 다른 모니터의 메뉴바: 항목은 화면 오른쪽 끝 기준으로 같은 위치에 놓인다
            let windowRightGap = buttonScreen.frame.maxX - window.frame.maxX
            let mouseRightGap = mouseScreen.frame.maxX - mouse.x
            xInWindow = window.frame.width - (mouseRightGap - windowRightGap)
        }
        let buttonOriginX = button.convert(NSPoint.zero, to: nil).x
        let imageWidth = button.image?.size.width ?? 0
        // 이미지는 버튼 가운데 정렬. 업데이트 점은 이미지 오른쪽 끝에 붙으므로 칸의 x 위치는 바뀌지 않는다
        let imageOffset = (button.bounds.width - imageWidth) / 2
        return xInWindow - buttonOriginX - imageOffset
    }
    //#endregion

    //#region 우클릭 메뉴
    private func showMenu() {
        let menu = NSMenu()

        if SpaceSwitcher.isTrusted(prompt: false) {
            menu.addItem(disabledItem("✓ Accessibility access granted"))
        } else {
            menu.addItem(disabledItem("⚠︎ Accessibility access required"))
            menu.addItem(actionItem("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        }

        if SpaceSwitcher.hasDirectHotkeys {
            menu.addItem(disabledItem("✓ Instant switching enabled"))
        } else {
            menu.addItem(disabledItem("Switching one desktop at a time (slow)"))
            menu.addItem(actionItem("Enable Instant Switching", #selector(enableInstantSwitching)))
            menu.addItem(actionItem("Open Keyboard Shortcuts Settings…", #selector(openKeyboardSettings)))
        }

        menu.addItem(.separator())
        if let release = updater.available {
            menu.addItem(actionItem("Update to DeskJump \(release.version)…", #selector(installUpdate)))
        }
        menu.addItem(actionItem("Check for Updates…", #selector(checkForUpdates)))
        let loginItem = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(actionItem("Open Mission Control", #selector(openMissionControl)))
        menu.addItem(.separator())
        menu.addItem(disabledItem("DeskJump \(Updater.currentVersion)"))
        menu.addItem(actionItem("Quit DeskJump", #selector(quit)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // 다음 왼쪽 클릭이 다시 숫자 클릭으로 동작하도록 메뉴를 떼어 둔다
        statusItem.menu = nil
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!)
    }

    @objc private func enableInstantSwitching() {
        SpaceSwitcher.enableDirectHotkeys()
    }

    @objc private func openMissionControl() {
        CoreDockSendNotification("com.apple.expose.awake" as CFString, 0)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            SpaceSwitcher.debugLog("login item toggle failed: \(error)")
            NSSound.beep()
        }
    }

    //#region 업데이트
    @objc private func checkForUpdates() {
        updater.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release?):
                self.confirmInstall(release)
            case .success(nil):
                self.showAlert("DeskJump is up to date.", "You have the latest version (\(Updater.currentVersion)).")
            case .failure(let error):
                self.showAlert("Couldn't check for updates.", error.localizedDescription)
            }
        }
    }

    @objc private func installUpdate() {
        guard let release = updater.available else { return }
        confirmInstall(release)
    }

    private func confirmInstall(_ release: Updater.Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DeskJump \(release.version) is available."
        alert.informativeText = "You have \(Updater.currentVersion). DeskJump will download the update, verify it and restart."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            updater.install(release) { [weak self] error in
                guard let error else { return }
                self?.showAlert("Update failed.", error.localizedDescription, link: release.pageURL)
            }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private func showAlert(_ title: String, _ message: String, link: URL? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if link != nil { alert.addButton(withTitle: "Open Release Page") }
        if alert.runModal() == .alertSecondButtonReturn, let link {
            NSWorkspace.shared.open(link)
        }
    }
    //#endregion

    @objc private func quit() { NSApp.terminate(nil) }
    //#endregion
}

//#region 진입점 (Dock 아이콘 없는 메뉴바 전용 앱)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
//#endregion
