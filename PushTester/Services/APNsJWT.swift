import Foundation
import CryptoKit
import Security

enum APNsJWTError: LocalizedError {
    case invalidP8Key
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidP8Key:
            return "유효한 .p8 인증 키를 읽을 수 없습니다. AuthKey_XXXX.p8 파일을 다시 Import 해 주세요."
        case .encodingFailed:
            return "JWT 인코딩에 실패했습니다."
        }
    }
}

enum APNsJWT {
    /// Apple은 provider JWT를 너무 자주 갱신하면 429 TooManyProviderTokenUpdates를 반환합니다.
    /// 같은 키로는 약 50분 동안 재사용합니다. (유효 시간은 최대 1시간)
    private static let tokenMaxAge: TimeInterval = 50 * 60
    private static let cacheLock = NSLock()
    private static var tokenCache: [String: CachedToken] = [:]

    private struct CachedToken {
        let jwt: String
        let createdAt: Date
    }

    static func makeToken(teamID: String, keyID: String, p8PEM: String) throws -> String {
        let cacheKey = "\(teamID)|\(keyID)|\(p8PEM.hashValue)"

        cacheLock.lock()
        if let cached = tokenCache[cacheKey],
           Date().timeIntervalSince(cached.createdAt) < tokenMaxAge {
            let jwt = cached.jwt
            cacheLock.unlock()
            return jwt
        }
        cacheLock.unlock()

        let privateKey = try loadPrivateKey(from: p8PEM)

        let header: [String: String] = [
            "alg": "ES256",
            "kid": keyID
        ]
        let claims: [String: Any] = [
            "iss": teamID,
            "iat": Int(Date().timeIntervalSince1970)
        ]

        let headerPart = try base64URLJSONObject(header)
        let claimsPart = try base64URLJSONObject(claims)
        let signingInput = "\(headerPart).\(claimsPart)"

        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        let signaturePart = base64URL(signature.rawRepresentation)
        let jwt = "\(signingInput).\(signaturePart)"

        cacheLock.lock()
        tokenCache[cacheKey] = CachedToken(jwt: jwt, createdAt: Date())
        cacheLock.unlock()

        return jwt
    }

    static func validateP8Key(_ pem: String) throws {
        _ = try loadPrivateKey(from: pem)
    }

    static func loadPrivateKey(from pem: String) throws -> P256.Signing.PrivateKey {
        let normalized = normalizePEM(pem)

        if let key = try? P256.Signing.PrivateKey(pemRepresentation: normalized) {
            return key
        }

        guard let der = derData(from: normalized) else {
            throw APNsJWTError.invalidP8Key
        }

        if let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
            return key
        }

        if let raw = extractECPrivateKeyRaw(from: der),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            return key
        }

        if let key = privateKeyUsingSecKey(from: der) {
            return key
        }

        throw APNsJWTError.invalidP8Key
    }

    private static func normalizePEM(_ pem: String) -> String {
        var text = pem
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        if !text.contains("\n"), text.contains("\\n") {
            text = text.replacingOccurrences(of: "\\n", with: "\n")
        }
        if text.contains("\\r\\n") {
            text = text.replacingOccurrences(of: "\\r\\n", with: "\n")
        }

        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = text
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "-----BEGIN PRIVATE KEY-----\n")
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "-----BEGIN EC PRIVATE KEY-----\n")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "\n-----END PRIVATE KEY-----")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "\n-----END EC PRIVATE KEY-----")

        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("-----") {
                return trimmed
            }
            return trimmed
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\t", with: "")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func derData(from pem: String) -> Data? {
        let lines = pem
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }

        let base64 = lines.joined()
        return Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
    }

    /// PKCS#8 / SEC1에서 P-256 private key(32바이트)를 추출합니다.
    /// 일부 오래된 .p8는 private key OCTET STRING이 31바이트 등으로 짧게 인코딩되어 있어 앞에 0을 패딩합니다.
    private static func extractECPrivateKeyRaw(from der: Data) -> Data? {
        if let raw = parsePKCS8ECPrivateKey(der) ?? parseECPrivateKey(der) {
            return normalizeP256RawKey(raw)
        }

        // 최후 수단: OCTET STRING 후보를 스캔
        let bytes = [UInt8](der)
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0x04 {
                let length = Int(bytes[index + 1])
                // 짧은 길이 형식만 (0x00~0x7f)
                if length < 0x80 {
                    let start = index + 2
                    let end = start + length
                    if end <= bytes.count, (1...33).contains(length) {
                        let candidate = Data(bytes[start..<end])
                        if let normalized = normalizeP256RawKey(candidate),
                           (try? P256.Signing.PrivateKey(rawRepresentation: normalized)) != nil {
                            return normalized
                        }
                    }
                }
            }
            index += 1
        }
        return nil
    }

    private static func normalizeP256RawKey(_ raw: Data) -> Data? {
        if raw.count == 32 {
            return raw
        }
        // INTEGER 부호 바이트로 앞에 0x00이 붙은 경우
        if raw.count == 33, raw.first == 0x00 {
            return raw.suffix(32)
        }
        // 앞의 0이 잘린 짧은 키 (이 사용자 키: 31바이트)
        if raw.count > 0, raw.count < 32 {
            var padded = Data(count: 32 - raw.count)
            padded.append(raw)
            return padded
        }
        return nil
    }

    private static func parsePKCS8ECPrivateKey(_ der: Data) -> Data? {
        // PrivateKeyInfo ::= SEQUENCE { version, algorithm, privateKey OCTET STRING }
        guard
            let outer = ASN1Node.parse(der),
            outer.tag == 0x30,
            outer.children.count >= 3,
            outer.children[2].tag == 0x04
        else {
            return nil
        }
        return parseECPrivateKey(outer.children[2].content)
    }

    private static func parseECPrivateKey(_ der: Data) -> Data? {
        // ECPrivateKey ::= SEQUENCE { version, privateKey OCTET STRING, ... }
        guard
            let root = ASN1Node.parse(der),
            root.tag == 0x30,
            root.children.count >= 2,
            root.children[1].tag == 0x04
        else {
            return nil
        }
        return root.children[1].content
    }

    private static func privateKeyUsingSecKey(from der: Data) -> P256.Signing.PrivateKey? {
        // 짧은 OCTET STRING을 패딩한 raw 키로 SecKey를 만들 필요는 없고,
        // 이미 extract 단계에서 처리합니다.
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            return nil
        }

        var exportError: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(secKey, &exportError) as Data? else {
            return nil
        }

        if external.count == 97 {
            return try? P256.Signing.PrivateKey(rawRepresentation: Data(external.suffix(32)))
        }
        if external.count == 32 {
            return try? P256.Signing.PrivateKey(rawRepresentation: external)
        }
        return nil
    }

    private static func base64URLJSONObject(_ object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw APNsJWTError.encodingFailed
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// 매우 단순한 DER 노드 파서 (이 앱의 .p8 용도)
private struct ASN1Node {
    let tag: UInt8
    let content: Data
    let children: [ASN1Node]

    static func parse(_ data: Data) -> ASN1Node? {
        var offset = 0
        return parseNode(data, offset: &offset)
    }

    private static func parseNode(_ data: Data, offset: inout Int) -> ASN1Node? {
        guard offset < data.count else { return nil }
        let tag = data[offset]
        offset += 1
        guard let length = readLength(data, offset: &offset) else { return nil }
        guard offset + length <= data.count else { return nil }
        let content = data.subdata(in: offset..<(offset + length))
        offset += length

        var children: [ASN1Node] = []
        if tag == 0x30 || tag == 0xa0 || tag == 0xa1 {
            var childOffset = 0
            while childOffset < content.count {
                var local = childOffset
                guard let child = parseNode(content, offset: &local) else { break }
                children.append(child)
                childOffset = local
            }
        }

        return ASN1Node(tag: tag, content: content, children: children)
    }

    private static func readLength(_ data: Data, offset: inout Int) -> Int? {
        guard offset < data.count else { return nil }
        let first = Int(data[offset])
        offset += 1
        if first < 0x80 {
            return first
        }
        let count = first & 0x7f
        guard count > 0, offset + count <= data.count else { return nil }
        var value = 0
        for _ in 0..<count {
            value = (value << 8) | Int(data[offset])
            offset += 1
        }
        return value
    }
}
