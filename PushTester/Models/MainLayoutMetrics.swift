import CoreGraphics

/// 메인 창 3영역(히스토리 / 입력 / 저장목록) 너비 정책
enum MainLayoutMetrics {
    /// 왼쪽 히스토리 · 오른쪽 저장목록 (완전히 접히지 않은 상태)
    static let sideMin: CGFloat = 260
    static let sideIdeal: CGFloat = 280
    static let sideMax: CGFloat = 360

    /// 가운데 입력 영역 권장 최소
    static let centerMin: CGFloat = 360

    /// 스플리터/크롬 여유
    static let chromeWidth: CGFloat = 24

    static let windowMinHeight: CGFloat = 480

    /// 히스토리·저장목록이 모두 접힌 상태의 절대 하한
    static var windowMinWidthCollapsed: CGFloat { centerMin }

    /// 현재 펼쳐진 컬럼을 반영한 창 최소 너비.
    /// 이 값보다 창이 작아지면 가운데가 잘리므로, 보이는 패널 합으로 하한을 올립니다.
    static func windowMinWidth(
        sidebarVisible: Bool,
        inspectorVisible: Bool
    ) -> CGFloat {
        var width = centerMin
        if sidebarVisible {
            width += sideMin
        }
        if inspectorVisible {
            width += sideMin
        }
        return width + chromeWidth
    }

}
