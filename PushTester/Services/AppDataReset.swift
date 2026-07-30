import Foundation

/// 앱 내부 저장 데이터를 한곳에서 초기화합니다.
enum AppDataReset {
    @MainActor
    static func resetPersistedStores(
        history: HistoryStore,
        savedConfigs: SavedConfigStore,
        fieldPresets: FieldPresetStore,
        certificates: CertificatePresetStore
    ) {
        history.clearAll()
        savedConfigs.clearAll()
        fieldPresets.clearAll()
        certificates.clearAll()
        SessionStore.clearLastSession()
        AndroidSessionStore.clearLastSession()
        UserDefaults.standard.removeObject(forKey: PushPlatform.lastSelectionDefaultsKey)
    }
}
