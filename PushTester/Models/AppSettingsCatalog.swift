import Foundation

/// 설정 화면 섹션. 새 설정 그룹을 추가할 때 case를 늘리면 됩니다.
enum AppSettingsSectionID: String, CaseIterable, Identifiable {
    case update
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .update: return "업데이트"
        case .data: return "데이터"
        }
    }
}

/// 설정 항목 식별자. 새 기능을 넣을 때 case와 카탈로그 항목을 추가합니다.
enum AppSettingsItemID: String, Identifiable {
    case checkForUpdateOnLaunch
    case checkForUpdate
    case resetAllData

    var id: String { rawValue }
}

enum AppSettingsItemRole {
    case normal
    case destructive
}

/// 설정 행의 조작 방식
enum AppSettingsControl {
    /// 탭하면 액션 실행
    case action
    /// UserDefaults Bool 토글 (`defaultValue`는 키 부재 시)
    case toggle(defaultsKey: String, defaultValue: Bool)
}

/// 설정 목록에 표시되는 한 줄
struct AppSettingsItem: Identifiable {
    let id: AppSettingsItemID
    let section: AppSettingsSectionID
    let title: String
    let subtitle: String
    let systemImage: String
    let role: AppSettingsItemRole
    let control: AppSettingsControl

    init(
        id: AppSettingsItemID,
        section: AppSettingsSectionID,
        title: String,
        subtitle: String,
        systemImage: String,
        role: AppSettingsItemRole,
        control: AppSettingsControl = .action
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.role = role
        self.control = control
    }
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
        case .update:
            return [
                AppSettingsItem(
                    id: .checkForUpdateOnLaunch,
                    section: .update,
                    title: "실행 시 업데이트 체크",
                    subtitle: "앱을 시작할 때 GitHub 최신 릴리즈를 확인합니다.",
                    systemImage: "arrow.clockwise.circle",
                    role: .normal,
                    control: .toggle(
                        defaultsKey: AppUpdatePreferences.checkOnLaunchKey,
                        defaultValue: true
                    )
                ),
                AppSettingsItem(
                    id: .checkForUpdate,
                    section: .update,
                    title: "업데이트 확인",
                    subtitle: "GitHub 최신 릴리즈와 현재 앱 버전을 비교합니다.",
                    systemImage: "arrow.triangle.2.circlepath",
                    role: .normal
                )
            ]
        case .data:
            return [
                AppSettingsItem(
                    id: .resetAllData,
                    section: .data,
                    title: "전체 데이터 초기화",
                    subtitle: "히스토리, 저장목록, 프리셋, Payload 템플릿, 마지막 세션을 모두 삭제합니다.",
                    systemImage: "trash",
                    role: .destructive
                )
            ]
        }
    }
}
