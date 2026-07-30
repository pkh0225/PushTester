import Foundation

enum PushPlatform: String, CaseIterable, Identifiable, Codable {
    case ios
    case android

    /// 마지막 선택 탭 저장용 UserDefaults 키
    static let lastSelectionDefaultsKey = "PushTester.lastPlatform"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}
