import AppKit
import ApplicationServices

/// 시스템 키보드 단축키(Mission Control)를 흉내 내어 Space를 전환한다
enum SpaceSwitcher {
    //#region 시스템 단축키 설정 조회 (com.apple.symbolichotkeys)
    struct Hotkey {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    // 심볼릭 핫키 ID: 79 = 왼쪽 Space, 81 = 오른쪽 Space, 118~133 = 데스크탑 1~16으로 전환
    private static let leftID = 79
    private static let rightID = 81
    private static let desktopBaseID = 117

    // 단축키가 plist에 없을 때 쓰는 macOS 기본값
    private static let defaultLeft = Hotkey(keyCode: 123, flags: CGEventFlags(rawValue: 0x840000))
    private static let defaultRight = Hotkey(keyCode: 124, flags: CGEventFlags(rawValue: 0x840000))

    private static func symbolicHotkeys() -> [String: Any] {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    }

    /// 설정에 등록되어 있고 켜져 있는 단축키만 돌려준다. 항목이 없으면 defaultValue 사용
    private static func hotkey(id: Int, in table: [String: Any], defaultValue: Hotkey?) -> Hotkey? {
        guard let entry = table[String(id)] as? [String: Any] else { return defaultValue }
        guard (entry["enabled"] as? NSNumber)?.boolValue == true else { return nil }
        // 켜져 있지만 키 조합이 기록되지 않은 경우(기본 조합 그대로)가 흔하다
        guard let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber],
              params.count >= 3 else { return defaultValue }
        return Hotkey(keyCode: CGKeyCode(params[1].intValue), flags: CGEventFlags(rawValue: params[2].uint64Value))
    }

    /// "데스크탑 N(으)로 전환" 단축키 (기본값은 꺼져 있음)
    static func desktopHotkey(number: Int) -> Hotkey? {
        guard (1...16).contains(number) else { return nil }
        return hotkey(id: desktopBaseID + number, in: symbolicHotkeys(), defaultValue: nil)
    }

    static var hasDirectHotkeys: Bool { desktopHotkey(number: 1) != nil }
    //#endregion

    //#region "데스크탑 N(으)로 전환" 단축키 켜기 (⌃⌥⇧1 ~ ⌃⌥⇧0)
    // Ctrl+숫자는 화면 캡처 앱 등과 겹치기 쉬워, 사람이 잘 쓰지 않는 ⌃⌥⇧ 조합을 쓴다.
    // DeskJump 는 설정에 저장된 조합을 그대로 읽어 보내므로 사용자가 직접 누를 일은 없다.
    private static let directHotkeyModifiers = 0x40000 | 0x80000 | 0x20000
    // 숫자 1~9, 0 의 (ASCII, 가상 키코드)
    private static let digitKeys: [(ascii: Int, keyCode: Int)] = [
        (49, 18), (50, 19), (51, 20), (52, 21), (53, 23), (54, 22), (55, 26), (56, 28), (57, 25), (48, 29),
    ]

    /// 처음 실행할 때 한 번만, 직접 전환 단축키가 하나도 없으면 켠다. 이후 사용자가 끄면 그대로 둔다
    static func enableDirectHotkeysOnFirstLaunch() {
        let key = "didSetupDirectHotkeys"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !hasDirectHotkeys { enableDirectHotkeys() }
    }

    /// 시스템 설정의 Mission Control 단축키 "Switch to Desktop 1~10" 을 ⌃⌥⇧+숫자로 켠다
    static func enableDirectHotkeys() {
        let domain = "com.apple.symbolichotkeys" as CFString
        var table = symbolicHotkeys()
        for (i, key) in digitKeys.enumerated() {
            table[String(desktopBaseID + i + 1)] = [
                "enabled": true,
                "value": ["type": "standard", "parameters": [key.ascii, key.keyCode, directHotkeyModifiers]],
            ] as [String: Any]
        }
        CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, table as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)

        // 로그아웃 없이 바로 적용
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        task.arguments = ["-u"]
        try? task.run()
        task.waitUntilExit()
    }
    //#endregion

    //#region 디버그 로그 (~/Library/Logs/DeskJump.log)
    /// `defaults write com.kaifacun.deskjump DebugLogging -bool true` 로 켰을 때만 기록한다
    static func debugLog(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "DebugLogging") else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DeskJump.log")
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    //#endregion

    //#region 키 입력 전송
    // 수정키(⌃⌥⇧⌘)는 실제 키보드처럼 눌렀다가 떼는 이벤트까지 보내야 한다.
    // 플래그만 실어 보내면 시스템의 수정키 상태가 눌린 채로 남아, 다음 클릭이 ⌃클릭이 되는 등 다른 입력이 오염된다.
    private static let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55),
    ]

    private static func post(_ key: Hotkey) {
        debugLog("post keyCode=\(key.keyCode) flags=0x\(String(key.flags.rawValue, radix: 16))")
        // 사용자가 실제로 누르고 있는 키 상태와 섞이지 않도록 독립된 이벤트 소스 사용
        let source = CGEventSource(stateID: .privateState)
        func send(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            // 연속으로 몰아 보내면 전환 처리 중에 일부 이벤트가 유실될 수 있어 간격을 둔다
            usleep(8_000)
        }

        let modifiers = modifierKeys.filter { key.flags.contains($0.flag) }
        var held: CGEventFlags = []
        for modifier in modifiers {
            held.insert(modifier.flag)
            send(modifier.keyCode, down: true, flags: held)
        }
        send(key.keyCode, down: true, flags: key.flags)
        send(key.keyCode, down: false, flags: key.flags)
        for modifier in modifiers.reversed() {
            held.remove(modifier.flag)
            send(modifier.keyCode, down: false, flags: held)
        }

        // 데스크탑 전환 애니메이션 중 떼기 이벤트가 유실되는 경우가 있어, 잠시 뒤 한 번 더 뗀다
        guard !modifiers.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            for modifier in modifiers {
                send(modifier.keyCode, down: false, flags: [])
            }
        }
    }
    //#endregion

    //#region Space 전환
    /// target 인덱스(전체화면 포함 순서)로 이동한다. 직접 단축키가 있으면 한 번에, 없으면 좌/우 이동을 반복
    static func switchTo(index target: Int, in display: DisplaySpaces) {
        debugLog("switch display=\(display.displayIdentifier) current=\(String(describing: display.currentIndex)) target=\(target)")
        guard display.spaces.indices.contains(target), let current = display.currentIndex, current != target else { return }

        let targetID = display.spaces[target].id
        if let number = display.spaces[target].desktopNumber, let key = desktopHotkey(number: number) {
            post(key)
            // 다중 모니터에서는 번호 체계가 다를 수 있으므로 실제로 도착했는지 확인 후 보정
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
                guard let latest = SpaceReader.readAll().first(where: { $0.displayIdentifier == display.displayIdentifier }),
                      latest.currentID != targetID,
                      let index = latest.spaces.firstIndex(where: { $0.id == targetID }) else { return }
                debugLog("direct hotkey missed, stepping instead")
                step(to: index, in: latest)
            }
            return
        }
        step(to: target, in: display)
    }

    /// Ctrl+←/→ 를 반복해 한 칸씩 이동
    private static func step(to target: Int, in display: DisplaySpaces) {
        guard let current = display.currentIndex, current != target else { return }
        let table = symbolicHotkeys()
        let goRight = target > current
        guard let key = goRight
            ? hotkey(id: rightID, in: table, defaultValue: defaultRight)
            : hotkey(id: leftID, in: table, defaultValue: defaultLeft) else {
            NSSound.beep()
            return
        }
        // 전환 애니메이션 중에도 입력이 누락되지 않도록 간격을 두고 보낸다
        for i in 0..<abs(target - current) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 90)) { post(key) }
        }
    }
    //#endregion

    //#region 손쉬운 사용 권한
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    //#endregion
}
