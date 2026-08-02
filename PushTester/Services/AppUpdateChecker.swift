import Foundation
import AppKit

/// 업데이트 확인 관련 UserDefaults 키와 기본값
enum AppUpdatePreferences {
    static let checkOnLaunchKey = "PushTester.checkForUpdateOnLaunch"
    static let snoozeUntilKey = "PushTester.updatePromptSnoozeUntil"

    /// 실행 시 업데이트 체크. 키가 없으면 기본값 `true`.
    static var checkOnLaunch: Bool {
        get {
            guard UserDefaults.standard.object(forKey: checkOnLaunchKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: checkOnLaunchKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: checkOnLaunchKey) }
    }

    static var isSnoozed: Bool {
        guard let until = UserDefaults.standard.object(forKey: snoozeUntilKey) as? Date else {
            return false
        }
        return until > Date()
    }

    static func snooze(forDays days: Int = 7) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(days * 86_400))
        UserDefaults.standard.set(until, forKey: snoozeUntilKey)
    }

    static func clearSnooze() {
        UserDefaults.standard.removeObject(forKey: snoozeUntilKey)
    }
}

/// GitHub Releases 최신 태그와 앱 버전을 비교해 업데이트를 안내합니다.
enum AppUpdateChecker {
    static let repositoryOwner = "pkh0225"
    static let repositoryName = "PushTester"

    /// API rate limit을 피하기 위해 HTML latest 리다이렉트 URL을 사용합니다.
    /// 예: https://github.com/pkh0225/PushTester/releases/latest → .../tag/1.2.3
    private static let latestReleasePageURL = URL(
        string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/latest"
    )!

    struct AvailableUpdate {
        let localVersion: String
        let remoteVersion: String
        let pageURL: URL
    }

    private enum CheckResult {
        case updateAvailable(AvailableUpdate)
        case upToDate(local: String, remote: String)
        case unavailable
    }

    /// 앱 시작 시: 설정·스누즈를 반영하고, 새 버전이 있을 때만 안내합니다.
    static func checkAndPrompt(using alertCenter: AppAlertCenter) {
        guard AppUpdatePreferences.checkOnLaunch else { return }
        guard !AppUpdatePreferences.isSnoozed else { return }
        check(using: alertCenter, reportWhenCurrentOrFailed: false, allowSnooze: true)
    }

    /// 설정에서 수동 확인: 최신/실패도 결과를 보여 줍니다. 스누즈는 적용하지 않습니다.
    static func checkFromSettings(using alertCenter: AppAlertCenter) {
        check(using: alertCenter, reportWhenCurrentOrFailed: true, allowSnooze: false)
    }

    private static func check(
        using alertCenter: AppAlertCenter,
        reportWhenCurrentOrFailed: Bool,
        allowSnooze: Bool
    ) {
        Task {
            let result = await performCheck()
            await MainActor.run {
                switch result {
                case .updateAvailable(let update):
                    alertCenter.confirm(
                        title: "새 버전 안내",
                        message: """
                        GitHub에 새 버전 \(update.remoteVersion)이 있습니다.
                        현재 버전: \(update.localVersion)

                        GitHub 릴리즈에서 다시 받아 설치해 주세요.
                        """,
                        cancelTitle: "나중에",
                        confirmTitle: "GitHub에서 받기",
                        isDestructive: false,
                        checkboxTitle: allowSnooze ? "일주일동안 보지 않기" : nil,
                        onCheckboxResult: allowSnooze
                            ? { checked in
                                if checked {
                                    AppUpdatePreferences.snooze(forDays: 7)
                                }
                            }
                            : nil
                    ) {
                        NSWorkspace.shared.open(update.pageURL)
                    }
                case .upToDate(let local, let remote):
                    guard reportWhenCurrentOrFailed else { return }
                    alertCenter.notice(
                        title: "최신 버전입니다",
                        message: "현재 버전 \(local) · GitHub 최신 \(remote)"
                    )
                case .unavailable:
                    guard reportWhenCurrentOrFailed else { return }
                    alertCenter.notice(
                        title: "확인하지 못했습니다",
                        message: "네트워크 상태를 확인한 뒤 다시 시도해 주세요."
                    )
                }
            }
        }
    }

    private static func performCheck() async -> CheckResult {
        guard let localString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let localVersion = AppVersion(string: localString) else {
            return .unavailable
        }

        do {
            guard let pageURL = try await resolveLatestReleaseURL(),
                  let tagName = tagName(from: pageURL),
                  let remoteVersion = AppVersion(string: tagName) else {
                return .unavailable
            }

            if localVersion < remoteVersion {
                return .updateAvailable(
                    AvailableUpdate(
                        localVersion: localString,
                        remoteVersion: tagName,
                        pageURL: pageURL
                    )
                )
            }
            return .upToDate(local: localString, remote: tagName)
        } catch {
            return .unavailable
        }
    }

    private static func resolveLatestReleaseURL() async throws -> URL? {
        var request = URLRequest(url: latestReleasePageURL)
        request.timeoutInterval = 8
        request.httpMethod = "HEAD"
        request.setValue("PushTester", forHTTPHeaderField: "User-Agent")
        // 본문 없이 리다이렉트된 최종 URL(.../releases/tag/x.y.z)만 사용합니다.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode),
              let finalURL = http.url else {
            return nil
        }
        return finalURL
    }

    private static func tagName(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let tagIndex = parts.firstIndex(of: "tag"),
              tagIndex + 1 < parts.count else {
            return nil
        }
        return parts[tagIndex + 1]
            .removingPercentEncoding
    }
}

/// `1.2.3` / `v1.2.3` 형태 버전 비교
private struct AppVersion: Comparable {
    let components: [Int]

    init?(string: String) {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        for part in parts {
            let digits = part.prefix(while: \.isNumber)
            guard !digits.isEmpty, let number = Int(digits) else { return nil }
            parsed.append(number)
        }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
