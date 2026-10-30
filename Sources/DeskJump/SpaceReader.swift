import AppKit
import CGSPrivate

/// 한 디스플레이에 속한 Space 하나
struct SpaceInfo: Equatable {
    let id: UInt64
    let isFullscreen: Bool
    /// 일반 데스크탑일 때 1부터 시작하는 번호 (전체화면 앱은 nil)
    let desktopNumber: Int?
}

/// 한 디스플레이의 Space 목록과 현재 Space
struct DisplaySpaces: Equatable {
    let displayIdentifier: String
    let spaces: [SpaceInfo]
    let currentID: UInt64

    var currentIndex: Int? { spaces.firstIndex { $0.id == currentID } }
}

enum SpaceReader {
    //#region 전체 디스플레이의 Space 조회 (SkyLight 비공개 API)
    static func readAll() -> [DisplaySpaces] {
        let cid = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }

        return raw.compactMap { display in
            guard let identifier = display["Display Identifier"] as? String,
                  let spaceDicts = display["Spaces"] as? [[String: Any]] else { return nil }

            var desktopCount = 0
            let spaces: [SpaceInfo] = spaceDicts.compactMap { dict in
                guard let id = (dict["ManagedSpaceID"] as? NSNumber)?.uint64Value else { return nil }
                let type = (dict["type"] as? NSNumber)?.intValue ?? 0
                // type 0 = 일반 데스크탑, 4 = 전체화면 앱. 그 외(대시보드 등)는 제외
                if type == 0 {
                    desktopCount += 1
                    return SpaceInfo(id: id, isFullscreen: false, desktopNumber: desktopCount)
                } else if type == 4 {
                    return SpaceInfo(id: id, isFullscreen: true, desktopNumber: nil)
                }
                return nil
            }
            let current = ((display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0
            return DisplaySpaces(displayIdentifier: identifier, spaces: spaces, currentID: current)
        }
    }
    //#endregion

    //#region 마우스가 있는 디스플레이의 Space 조회
    /// 메뉴바를 클릭하는 순간 마우스는 그 모니터 위에 있으므로, 마우스 기준 모니터를 대상으로 삼는다
    static func readForMouseDisplay() -> DisplaySpaces? {
        let all = readAll()
        guard !all.isEmpty else { return nil }
        // "디스플레이마다 개별 Spaces" 옵션이 꺼져 있으면 항목이 하나("Main")뿐이다
        if all.count == 1 { return all[0] }

        if let uuid = mouseDisplayUUID(), let match = all.first(where: { $0.displayIdentifier == uuid }) {
            return match
        }
        let active = CGSGetActiveSpace(CGSMainConnectionID())
        return all.first { $0.currentID == active } ?? all[0]
    }

    private static func mouseDisplayUUID() -> String? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    //#endregion
}
