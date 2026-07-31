import Foundation
import AppKit

/// GitHub Releases 최신 태그와 앱 버전을 비교해 업데이트를 안내합니다.
/// 네트워크 실패·타임아웃·파싱 실패는 조용히 무시합니다.
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

    static func checkAndPrompt(using alertCenter: AppAlertCenter) {
        Task {
            guard let update = await fetchAvailableUpdate() else { return }
            await MainActor.run {
                alertCenter.confirm(
                    title: "새 버전 안내",
                    message: """
                    GitHub에 새 버전 \(update.remoteVersion)이 있습니다.
                    현재 버전: \(update.localVersion)

                    GitHub 릴리즈에서 다시 받아 설치해 주세요.
                    """,
                    cancelTitle: "나중에",
                    confirmTitle: "GitHub에서 받기",
                    isDestructive: false
                ) {
                    NSWorkspace.shared.open(update.pageURL)
                }
            }
        }
    }

    private static func fetchAvailableUpdate() async -> AvailableUpdate? {
        guard let localString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let localVersion = AppVersion(string: localString) else {
            return nil
        }

        do {
            guard let pageURL = try await resolveLatestReleaseURL(),
                  let tagName = tagName(from: pageURL),
                  let remoteVersion = AppVersion(string: tagName),
                  localVersion < remoteVersion else {
                return nil
            }

            return AvailableUpdate(
                localVersion: localString,
                remoteVersion: tagName,
                pageURL: pageURL
            )
        } catch {
            return nil
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
