import Foundation

enum FCMPriority: String, CaseIterable, Identifiable {
    case high = "HIGH"
    case normal = "NORMAL"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "high"
        case .normal: return "normal"
        }
    }

    var historyValue: Int {
        switch self {
        case .high: return 10
        case .normal: return 5
        }
    }

    static func from(historyValue: Int) -> FCMPriority {
        historyValue == 5 ? .normal : .high
    }
}

struct AndroidSession: Codable, Equatable {
    var projectID: String
    var deviceToken: String
    var priority: String
    var payload: String
    var serviceAccountFileName: String
    var serviceAccountJSON: String

    static let empty = AndroidSession(
        projectID: "",
        deviceToken: "",
        priority: FCMPriority.high.rawValue,
        payload: AndroidPayloadTemplates.notification,
        serviceAccountFileName: "No JSON imported",
        serviceAccountJSON: ""
    )
}

enum AndroidPayloadTemplates {
    static let notification = """
    {
      "notification" : {
        "title" : "Notification Title",
        "body" : "This is the body of Android push notification"
      },
      "data" : {
        "link_url" : "https://www.ssg.com"
      }
    }
    """

    static let dataOnly = """
    {
      "data" : {
        "link_url" : "https://www.ssg.com",
        "type" : "silent"
      }
    }
    """
}
