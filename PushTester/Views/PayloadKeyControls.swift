import SwiftUI

/// Payload 헤더 가운데 Key 선택 + String/인코딩 컨트롤
struct PayloadKeyControls: View {
    @Binding var payload: String
    var onStatus: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            PayloadKeyActionGroup(
                payload: $payload,
                onStatus: onStatus,
                mode: .stringify
            )
            PayloadKeyActionGroup(
                payload: $payload,
                onStatus: onStatus,
                mode: .encode
            )
        }
    }
}

// MARK: - Independent group

private enum PayloadKeyActionMode {
    case stringify
    case encode

    var activeColor: Color {
        switch self {
        case .stringify: return .orange
        case .encode: return .purple
        }
    }

    func actionTitle(canRestore: Bool) -> String {
        switch self {
        case .stringify:
            return canRestore ? "String 원복" : "String 치환"
        case .encode:
            return canRestore ? "인코딩 원복" : "인코딩"
        }
    }

    func actionHelp(canRestore: Bool) -> String {
        switch self {
        case .stringify:
            return canRestore
                ? "String으로 변환된 값을 원래 타입으로 되돌립니다."
                : "선택한 key의 value를 문자열로 변환합니다. object/array는 JSON 텍스트로 넣습니다."
        case .encode:
            return canRestore
                ? "인코딩된 값을 원래 값으로 되돌립니다."
                : "선택한 key의 value를 URL 인코딩합니다. object/array는 JSON 텍스트로 만든 뒤 인코딩합니다."
        }
    }
}

private struct PayloadKeyActionGroup: View {
    @Binding var payload: String
    var onStatus: (String) -> Void
    let mode: PayloadKeyActionMode

    @State private var selectedPath: String?
    @State private var selectedName: String?
    @State private var originals: [String: String] = [:]

    private var keys: [PayloadJSONKeyTools.KeyEntry] {
        PayloadJSONKeyTools.collectKeys(from: payload)
    }

    private var keyButtonTitle: String {
        selectedName ?? "Key 선택"
    }

    private var canRestore: Bool {
        guard let path = selectedPath else { return false }
        if originals[path] != nil { return true }
        switch mode {
        case .stringify:
            return PayloadJSONKeyTools.canRestoreWithoutCache(in: payload, atPath: path)
        case .encode:
            return PayloadJSONKeyTools.canDecodePercentEncoding(in: payload, atPath: path)
        }
    }

    private var keyButtonColor: Color {
        selectedName == nil ? Color.accentColor : Color.blue
    }

    private var actionColor: Color {
        if selectedPath == nil { return Color.secondary }
        return canRestore ? Color.green : mode.activeColor
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 14)
                Menu {
                    if keys.isEmpty {
                        Text("유효한 JSON key 없음")
                    } else {
                        ForEach(keys) { entry in
                            Button(entry.path) {
                                selectedPath = entry.path
                                selectedName = entry.name
                                onStatus("Key 선택: \(entry.path)")
                            }
                        }
                    }
                } label: {
                    Text(keyButtonTitle)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(keyButtonColor)
                .disabled(keys.isEmpty)
                .help("현재 Payload JSON의 key 목록에서 하나를 선택합니다.")
                Color.clear.frame(width: 14)
            }
            .padding(.vertical, 5)

            Divider()
                .frame(height: 16)

            Button(mode.actionTitle(canRestore: canRestore)) {
                performAction()
            }
            .buttonStyle(.plain)
            .foregroundStyle(actionColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .disabled(selectedPath == nil)
            .help(mode.actionHelp(canRestore: canRestore))
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .fixedSize()
        .onChange(of: payload) { _, _ in
            validateSelection()
            pruneOriginals()
        }
    }

    private func performAction() {
        guard let path = selectedPath else { return }

        do {
            switch mode {
            case .stringify:
                try toggleStringConversion(path: path)
            case .encode:
                try toggleEncoding(path: path)
            }
        } catch {
            onStatus(error.localizedDescription)
        }
    }

    private func toggleStringConversion(path: String) throws {
        if let originalFragment = originals[path] {
            payload = try PayloadJSONKeyTools.restoreValue(
                in: payload,
                atPath: path,
                originalFragment: originalFragment
            )
            originals.removeValue(forKey: path)
            onStatus("String 원복 완료: \(path)")
            return
        }

        if PayloadJSONKeyTools.canRestoreWithoutCache(in: payload, atPath: path) {
            payload = try PayloadJSONKeyTools.restoreParsedJSONString(in: payload, atPath: path)
            onStatus("String 원복 완료: \(path)")
            return
        }

        if PayloadJSONKeyTools.isAlreadyPlainString(in: payload, atPath: path) {
            onStatus("이미 문자열입니다: \(path)")
            return
        }

        let result = try PayloadJSONKeyTools.stringifyValue(in: payload, atPath: path)
        originals[path] = result.originalFragment
        payload = result.payload
        onStatus("String 치환 완료: \(path)")
    }

    private func toggleEncoding(path: String) throws {
        if let originalFragment = originals[path] {
            payload = try PayloadJSONKeyTools.restoreValue(
                in: payload,
                atPath: path,
                originalFragment: originalFragment
            )
            originals.removeValue(forKey: path)
            onStatus("인코딩 원복 완료: \(path)")
            return
        }

        if PayloadJSONKeyTools.canDecodePercentEncoding(in: payload, atPath: path) {
            payload = try PayloadJSONKeyTools.decodePercentEncodedValue(in: payload, atPath: path)
            onStatus("인코딩 원복 완료: \(path)")
            return
        }

        let result = try PayloadJSONKeyTools.percentEncodeValue(in: payload, atPath: path)
        originals[path] = result.originalFragment
        payload = result.payload
        onStatus("인코딩 완료: \(path)")
    }

    private func validateSelection() {
        guard let path = selectedPath else { return }
        if !keys.contains(where: { $0.path == path }) {
            selectedPath = nil
            selectedName = nil
        }
    }

    private func pruneOriginals() {
        let validPaths = Set(keys.map(\.path))
        originals = originals.filter { validPaths.contains($0.key) }
    }
}
