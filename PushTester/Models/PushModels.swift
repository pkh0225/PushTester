import Foundation

enum APNsEnvironment: String, CaseIterable, Identifiable {
    case sandbox = "Sandbox"
    case production = "Production"

    var id: String { rawValue }

    var host: String {
        switch self {
        case .sandbox:
            return "api.sandbox.push.apple.com"
        case .production:
            return "api.push.apple.com"
        }
    }
}

enum APNsPriority: Int, CaseIterable, Identifiable {
    case powerConsiderations = 5
    case immediate = 10

    var id: Int { rawValue }

    var title: String { String(rawValue) }
}

enum APNsPushType: String, CaseIterable, Identifiable {
    case alert = "alert"
    case background = "background"
    case voip = "voip"
    case complication = "complication"
    case fileprovider = "fileprovider"
    case mdm = "mdm"
    case liveactivity = "liveactivity"
    case pushtotalk = "pushtotalk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alert: return "Alert"
        case .background: return "Background"
        case .voip: return "VoIP"
        case .complication: return "Complication"
        case .fileprovider: return "File Provider"
        case .mdm: return "MDM"
        case .liveactivity: return "Live Activity"
        case .pushtotalk: return "Push to Talk"
        }
    }
}

enum PayloadTemplates {
    static let alert = """
    {
      "aps" : {
        "alert" : {
          "title" : "Notification Title",
          "subtitle" : "Notification subtitle",
          "body" : "This is the body of push notification :)"
        },
        "sound" : "default"
      }
    }
    """

    static let background = """
    {
      "aps" : {
        "content-available" : 1
      }
    }
    """

    static let voip = """
    {
      "aps" : {
        "alert" : {
          "title" : "Incoming Call",
          "body" : "You have an incoming VoIP call"
        }
      }
    }
    """

    static let complication = """
    {
      "aps" : {
        "content-available" : 1
      },
      "watchkit" : {
        "complication" : 1
      }
    }
    """

    static let fileprovider = """
    {
      "aps" : {
        "content-available" : 1
      },
      "file-provider" : {
        "reason" : "item-changed"
      }
    }
    """

    static let mdm = """
    {
      "mdm" : "00000000-0000-0000-0000-000000000000"
    }
    """

    static let liveactivity = """
    {
      "aps" : {
        "timestamp" : 0,
        "event" : "update",
        "content-state" : {
          "status" : "in_progress",
          "progress" : 0.5
        }
      }
    }
    """

    static let pushtotalk = """
    {
      "aps" : {
        "alert" : {
          "title" : "Push to Talk",
          "body" : "Someone started speaking"
        }
      }
    }
    """

    static func template(for pushType: APNsPushType) -> String {
        switch pushType {
        case .alert:
            return alert
        case .background:
            return background
        case .voip:
            return voip
        case .complication:
            return complication
        case .fileprovider:
            return fileprovider
        case .mdm:
            return mdm
        case .liveactivity:
            return liveactivity
        case .pushtotalk:
            return pushtotalk
        }
    }
}
