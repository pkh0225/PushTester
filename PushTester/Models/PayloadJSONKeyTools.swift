import Foundation

enum PayloadJSONKeyTools {
    struct KeyEntry: Identifiable, Hashable {
        var id: String { path }
        /// Dot path, e.g. `data.push_info`
        let path: String
        /// Last key segment, e.g. `push_info`
        let name: String
    }

    enum ToolError: LocalizedError {
        case invalidJSON
        case keyNotFound(String)
        case serializeFailed
        case notRestorable
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "Payload가 올바른 JSON 형식이 아닙니다."
            case .keyNotFound(let path):
                return "선택한 key를 찾을 수 없습니다: \(path)"
            case .serializeFailed:
                return "JSON을 문자열로 변환하지 못했습니다."
            case .notRestorable:
                return "원복할 수 있는 값이 아닙니다."
            case .encodeFailed:
                return "URL 인코딩에 실패했습니다."
            }
        }
    }

    static func collectKeys(from jsonString: String) -> [KeyEntry] {
        guard let root = parseObject(jsonString) else { return [] }
        var result: [KeyEntry] = []
        collect(from: root, pathPrefix: "", into: &result)
        return result
    }

    static func value(in jsonString: String, atPath path: String) throws -> Any {
        guard let root = parseObject(jsonString) else {
            throw ToolError.invalidJSON
        }
        let segments = pathSegments(path)
        return try value(in: root, segments: segments)
    }

    /// Converts the value at `path` to a JSON string value (primitives → String, object/array → compact JSON text).
    /// Returns the updated payload and a JSON fragment of the original value (for restore).
    static func stringifyValue(in jsonString: String, atPath path: String) throws -> (payload: String, originalFragment: String) {
        guard var root = parseObject(jsonString) else {
            throw ToolError.invalidJSON
        }

        let segments = pathSegments(path)
        let original = try value(in: root, segments: segments)
        let fragment = try encodeFragment(original)
        try setValue(try stringValue(from: original), in: &root, segments: segments)
        return (try serializePretty(root), fragment)
    }

    /// Restores a previously saved JSON fragment at `path`.
    static func restoreValue(in jsonString: String, atPath path: String, originalFragment: String) throws -> String {
        guard var root = parseObject(jsonString) else {
            throw ToolError.invalidJSON
        }
        let segments = pathSegments(path)
        let restored = try decodeFragment(originalFragment)
        try setValue(restored, in: &root, segments: segments)
        return try serializePretty(root)
    }

    /// If the value at `path` is a String that parses as a JSON object/array, restore it to that structure.
    static func restoreParsedJSONString(in jsonString: String, atPath path: String) throws -> String {
        let current = try value(in: jsonString, atPath: path)
        guard let string = current as? String,
              let parsed = try? decodeFragment(string),
              parsed is [String: Any] || parsed is [Any]
        else {
            throw ToolError.notRestorable
        }

        guard var root = parseObject(jsonString) else {
            throw ToolError.invalidJSON
        }
        try setValue(parsed, in: &root, segments: pathSegments(path))
        return try serializePretty(root)
    }

    static func canRestoreWithoutCache(in jsonString: String, atPath path: String) -> Bool {
        guard let current = try? value(in: jsonString, atPath: path) as? String,
              let parsed = try? decodeFragment(current)
        else {
            return false
        }
        return parsed is [String: Any] || parsed is [Any]
    }

    static func isAlreadyPlainString(in jsonString: String, atPath path: String) -> Bool {
        guard let current = try? value(in: jsonString, atPath: path) else { return false }
        return current is String && !canRestoreWithoutCache(in: jsonString, atPath: path)
    }

    /// Percent-encodes the value at `path` (non-strings are stringified first).
    static func percentEncodeValue(in jsonString: String, atPath path: String) throws -> (payload: String, originalFragment: String) {
        guard var root = parseObject(jsonString) else {
            throw ToolError.invalidJSON
        }

        let segments = pathSegments(path)
        let original = try value(in: root, segments: segments)
        let fragment = try encodeFragment(original)
        let plain = try stringValue(from: original)
        guard let encoded = plain.addingPercentEncoding(withAllowedCharacters: urlEncodeAllowed) else {
            throw ToolError.encodeFailed
        }
        try setValue(encoded, in: &root, segments: segments)
        return (try serializePretty(root), fragment)
    }

    static func canDecodePercentEncoding(in jsonString: String, atPath path: String) -> Bool {
        guard let current = try? value(in: jsonString, atPath: path) as? String,
              current.contains("%"),
              let decoded = current.removingPercentEncoding,
              decoded != current
        else {
            return false
        }
        return true
    }

    /// URL-decodes a percent-encoded string value. If the decoded text is JSON object/array, restores that structure.
    static func decodePercentEncodedValue(in jsonString: String, atPath path: String) throws -> String {
        let current = try value(in: jsonString, atPath: path)
        guard let encoded = current as? String,
              let decoded = encoded.removingPercentEncoding,
              decoded != encoded
        else {
            throw ToolError.notRestorable
        }

        guard var root = parseObject(jsonString) else {
            throw ToolError.invalidJSON
        }

        let segments = pathSegments(path)
        if let parsed = try? decodeFragment(decoded),
           parsed is [String: Any] || parsed is [Any] {
            try setValue(parsed, in: &root, segments: segments)
        } else {
            try setValue(decoded, in: &root, segments: segments)
        }
        return try serializePretty(root)
    }

    // MARK: - Private

    /// RFC 3986 unreserved characters — everything else is percent-encoded.
    private static let urlEncodeAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()


    private static func pathSegments(_ path: String) -> [String] {
        path.split(separator: ".").map(String.init)
    }

    private static func parseObject(_ jsonString: String) -> [String: Any]? {
        let data = Data(jsonString.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func collect(from value: Any, pathPrefix: String, into result: inout [KeyEntry]) {
        guard let dict = value as? [String: Any] else { return }
        for key in dict.keys.sorted() {
            let path = pathPrefix.isEmpty ? key : "\(pathPrefix).\(key)"
            result.append(KeyEntry(path: path, name: key))
            if let nested = dict[key] as? [String: Any] {
                collect(from: nested, pathPrefix: path, into: &result)
            }
        }
    }

    private static func value(in dict: [String: Any], segments: [String]) throws -> Any {
        guard let first = segments.first else {
            throw ToolError.keyNotFound("")
        }
        guard let value = dict[first] else {
            throw ToolError.keyNotFound(segments.joined(separator: "."))
        }
        if segments.count == 1 {
            return value
        }
        guard let nested = value as? [String: Any] else {
            throw ToolError.keyNotFound(segments.joined(separator: "."))
        }
        return try self.value(in: nested, segments: Array(segments.dropFirst()))
    }

    private static func setValue(_ newValue: Any, in dict: inout [String: Any], segments: [String]) throws {
        guard let first = segments.first else { return }

        if segments.count == 1 {
            guard dict[first] != nil else {
                throw ToolError.keyNotFound(first)
            }
            dict[first] = newValue
            return
        }

        guard var nested = dict[first] as? [String: Any] else {
            throw ToolError.keyNotFound(segments.joined(separator: "."))
        }
        try setValue(newValue, in: &nested, segments: Array(segments.dropFirst()))
        dict[first] = nested
    }

    private static func stringValue(from value: Any) throws -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return "null"
        default:
            guard JSONSerialization.isValidJSONObject(value) else {
                throw ToolError.serializeFailed
            }
            let data = try JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys]
            )
            return try utf8JSONString(from: data)
        }
    }

    private static func encodeFragment(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys]
        )
        return try utf8JSONString(from: data)
    }

    private static func decodeFragment(_ string: String) throws -> Any {
        let data = Data(string.utf8)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func serializePretty(_ root: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ToolError.serializeFailed
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        return try utf8JSONString(from: data)
    }

    /// `JSONSerialization`이 `/`를 `\/`로 이스케이프하는 것을 되돌립니다.
    private static func utf8JSONString(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.serializeFailed
        }
        return text.replacingOccurrences(of: "\\/", with: "/")
    }
}

enum PayloadJSONValidator {
    struct CheckResult {
        let isValid: Bool
        let message: String
    }

    /// 전송 시와 같이 스마트 따옴표를 정규화한 뒤 JSON 유효성을 검사합니다.
    static func check(_ text: String) -> CheckResult {
        let normalized = JSONTextNormalizer.normalizeQuotes(text)
        let data = Data(normalized.utf8)
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return CheckResult(isValid: true, message: "유효한 JSON입니다.")
        } catch {
            return CheckResult(isValid: false, message: error.localizedDescription)
        }
    }
}

/// 웹에서 복사한 스마트 따옴표 등을 JSON용 ASCII 따옴표로 정규화합니다.
/// 편집 중에는 적용하지 않고, Push 전송 직전에만 사용합니다(한글 IME 커서 점프 방지).
enum JSONTextNormalizer {
    private static let doubleQuotes: Set<Character> = [
        "\u{201C}", // “
        "\u{201D}", // ”
        "\u{201E}", // „
        "\u{201F}", // ‟
        "\u{2033}", // ″
        "\u{2036}", // ‶
        "\u{00AB}", // «
        "\u{00BB}", // »
        "\u{FF02}", // ＂
        "\u{301D}", // 〝
        "\u{301E}", // 〞
    ]

    private static let singleQuotes: Set<Character> = [
        "\u{2018}", // ‘
        "\u{2019}", // ’
        "\u{201A}", // ‚
        "\u{201B}", // ‛
        "\u{2032}", // ′
        "\u{FF07}", // ＇
    ]

    static func normalizeQuotes(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count)

        for character in text {
            if doubleQuotes.contains(character) {
                result.append("\"")
            } else if singleQuotes.contains(character) {
                result.append("'")
            } else {
                result.append(character)
            }
        }
        return result
    }
}
