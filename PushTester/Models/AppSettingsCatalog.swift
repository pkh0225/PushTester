import Foundation

/// 설정 화면 섹션. 새 설정 그룹을 추가할 때 case를 늘리면 됩니다.
enum AppSettingsSectionID: String, CaseIterable, Identifiable {
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .data: return "데이터"
        }
    }
}

/// 설정 항목 식별자. 새 기능을 넣을 때 case와 카탈로그 항목을 추가합니다.
enum AppSettingsItemID: String, Identifiable {
    case resetAllData

    var id: String { rawValue }
}

enum AppSettingsItemRole {
    case normal
    case destructive
}

/// 설정 목록에 표시되는 한 줄
struct AppSettingsItem: Identifiable {
    let id: AppSettingsItemID
    let section: AppSettingsSectionID
    let title: String
    let subtitle: String
    let systemImage: String
    let role: AppSettingsItemRole
}

struct AppSettingsSection: Identifiable {
    let id: AppSettingsSectionID
    var title: String { id.title }
    let items: [AppSettingsItem]
}

/// 설정 UI의 단일 진입점. 항목 추가/순서 변경은 여기만 수정하면 됩니다.
enum AppSettingsCatalog {
    static var sections: [AppSettingsSection] {
        AppSettingsSectionID.allCases.compactMap { sectionID in
            let items = items(in: sectionID)
            guard !items.isEmpty else { return nil }
            return AppSettingsSection(id: sectionID, items: items)
        }
    }

    static func items(in section: AppSettingsSectionID) -> [AppSettingsItem] {
        switch section {
        case .data:
            return [
                AppSettingsItem(
                    id: .resetAllData,
                    section: .data,
                    title: "전체 데이터 초기화",
                    subtitle: "히스토리, 저장목록, 프리셋, 마지막 세션을 모두 삭제합니다.",
                    systemImage: "trash",
                    role: .destructive
                )
            ]
        }
    }
}
