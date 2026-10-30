import AppKit
import Security

/// GitHub Releases 에서 새 버전을 확인하고, 서명·공증을 검증한 뒤 앱을 교체하는 업데이터
final class Updater {
    struct Release {
        let version: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum UpdateError: LocalizedError {
        case network(String)
        case noAsset
        case invalidSignature
        case notNotarized
        case versionMismatch(String)
        case install(String)

        var errorDescription: String? {
            switch self {
            case .network(let message): return "Couldn't reach GitHub: \(message)"
            case .noAsset: return "The latest release has no DeskJump zip."
            case .invalidSignature: return "The downloaded app isn't signed by the DeskJump developer."
            case .notNotarized: return "The downloaded app isn't notarized by Apple."
            case .versionMismatch(let found): return "The downloaded app reports version \(found)."
            case .install(let message): return "Couldn't replace the app: \(message)"
            }
        }
    }

    //#region 설정
    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/kaifacun/deskjump/releases/latest")!
    // 같은 팀의 Developer ID 로 서명된 DeskJump 만 설치한다
    private let requirement = """
        anchor apple generic and identifier "com.kaifacun.deskjump" \
        and certificate leaf[subject.OU] = "2Z8PMQ5YFB" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]
        """
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let lastCheckKey = "lastUpdateCheck"
    //#endregion

    /// 확인된 새 버전 (없으면 nil). 바뀌면 onChange 호출
    private(set) var available: Release? {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?
    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    //#region 자동 확인 (하루 한 번)
    func startAutomaticChecks() {
        // 앱 시작 직후 네트워크가 준비될 시간을 두고 확인
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    private func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= checkInterval else { return }
        check { _ in }
    }
    //#endregion

    //#region 최신 버전 확인
    /// 최신 Release 를 조회해 지금보다 새 버전이면 available 에 저장한다
    func check(completion: @escaping (Result<Release?, Error>) -> Void) {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DeskJump/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Release?, Error>
            if let error {
                result = .failure(UpdateError.network(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(UpdateError.network("HTTP \(http.statusCode)"))
            } else if let data, let release = Self.parse(data) {
                result = .success(Self.isNewer(release.version, than: Self.currentVersion) ? release : nil)
            } else {
                result = .failure(UpdateError.noAsset)
            }

            DispatchQueue.main.async {
                if case .success(let release) = result {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastCheckKey)
                    self.available = release
                }
                completion(result)
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let asset = assets.first(where: { ($0["name"] as? String) == "DeskJump-\(version).zip" }),
              let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: version, downloadURL: url, pageURL: page)
    }

    /// "1.0.10" > "1.0.9" 처럼 숫자 단위로 비교
    static func isNewer(_ a: String, than b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }
    //#endregion

    //#region 내려받기 → 검증 → 교체 → 재실행
    func install(_ release: Release, completion: @escaping (Error?) -> Void) {
        URLSession.shared.downloadTask(with: release.downloadURL) { location, _, error in
            let outcome: Error?
            if let error {
                outcome = UpdateError.network(error.localizedDescription)
            } else if let location {
                outcome = self.verifyAndReplace(zip: location, expectedVersion: release.version)
            } else {
                outcome = UpdateError.network("empty download")
            }
            DispatchQueue.main.async {
                if let outcome {
                    completion(outcome)
                } else {
                    Self.relaunch()
                }
            }
        }.resume()
    }

    private func verifyAndReplace(zip: URL, expectedVersion: String) -> Error? {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("DeskJump-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }

        // 압축 해제
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        } catch {
            return UpdateError.install("unzip failed")
        }
        let newApp = work.appendingPathComponent("DeskJump.app")

        // 1) 같은 팀 Developer ID 서명인지 2) Apple 공증을 받았는지 3) 버전이 맞는지
        guard Self.isValidSignature(newApp, requirement: requirement) else { return UpdateError.invalidSignature }
        guard (try? Self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path])) != nil else {
            return UpdateError.notNotarized
        }
        let found = Bundle(url: newApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard found == expectedVersion else { return UpdateError.versionMismatch(found) }

        // 실행 중인 앱 번들을 새 번들로 원자적으로 교체
        do {
            _ = try fm.replaceItemAt(Bundle.main.bundleURL, withItemAt: newApp)
        } catch {
            return UpdateError.install(error.localizedDescription)
        }
        return nil
    }

    private static func isValidSignature(_ app: URL, requirement text: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.install("\(tool) exited \(process.terminationStatus)") }
        return process.terminationStatus
    }

    /// 지금 프로세스가 끝난 뒤 새 번들을 다시 연다
    private static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
    //#endregion
}
