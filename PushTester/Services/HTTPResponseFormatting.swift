import Foundation

enum HTTPResponseFormatting {
    static func headersText(from http: HTTPURLResponse) -> String {
        http.allHeaderFields
            .compactMap { key, value -> (String, String)? in
                let name = String(describing: key)
                // Authorization 등은 응답에 거의 없지만, 민감 헤더는 제외합니다.
                if name.lowercased() == "authorization" { return nil }
                return (name, String(describing: value))
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            .map { "\($0): \($1)" }
            .joined(separator: "\n")
    }

    static func prettyBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              var text = String(data: pretty, encoding: .utf8)
        else {
            return body
        }
        text = text.replacingOccurrences(of: "\\/", with: "/")
        return text
    }
}
