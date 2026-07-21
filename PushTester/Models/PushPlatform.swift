import Foundation

enum PushPlatform: String, CaseIterable, Identifiable, Codable {
    case ios
    case android

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}
