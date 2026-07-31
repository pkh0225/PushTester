import Foundation
import Security

enum FCMAuthError: LocalizedError {
    case invalidServiceAccount
    case invalidPrivateKey
    case tokenExchangeFailed(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidServiceAccount:
            return "유효한 Firebase 서비스 계정 JSON이 아닙니다."
        case .invalidPrivateKey:
            return "서비스 계정의 private_key를 읽을 수 없습니다."
        case .tokenExchangeFailed(let message):
            return "FCM 인증 토큰 발급 실패: \(message)"
        case .encodingFailed:
            return "JWT 인코딩에 실패했습니다."
        }
    }
}

struct GoogleServiceAccount: Equatable {
    let projectID: String
    let clientEmail: String
    let privateKeyPEM: String
    let tokenURI: String

    static func parse(from json: String) throws -> GoogleServiceAccount {
        guard
            let data = json.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let projectID = object["project_id"] as? String, !projectID.isEmpty,
            let clientEmail = object["client_email"] as? String, !clientEmail.isEmpty,
            let privateKey = object["private_key"] as? String, !privateKey.isEmpty
        else {
            throw FCMAuthError.invalidServiceAccount
        }

        let tokenURI = (object["token_uri"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "https://oauth2.googleapis.com/token"

        let pem = normalizePrivateKeyPEM(privateKey)

        // Import 시점에 키 파싱 가능 여부를 검증합니다.
        _ = try FCMAuth.makePrivateKey(fromPEM: pem)

        return GoogleServiceAccount(
            projectID: projectID,
            clientEmail: clientEmail,
            privateKeyPEM: pem,
            tokenURI: tokenURI
        )
    }

    private static func normalizePrivateKeyPEM(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FCMAuth {
    private static let scope = "https://www.googleapis.com/auth/firebase.messaging"
    private static let tokenCache = AccessTokenCache()

    private struct CachedToken: Sendable {
        let accessToken: String
        let createdAt: Date
    }

    /// async 컨텍스트에서 NSLock 대신 쓰는 토큰 캐시
    private actor AccessTokenCache {
        private let tokenMaxAge: TimeInterval = 50 * 60
        private var storage: [String: CachedToken] = [:]

        func token(for key: String) -> String? {
            guard let cached = storage[key],
                  Date().timeIntervalSince(cached.createdAt) < tokenMaxAge else {
                return nil
            }
            return cached.accessToken
        }

        func store(_ accessToken: String, for key: String) {
            storage[key] = CachedToken(accessToken: accessToken, createdAt: Date())
        }
    }

    static func accessToken(serviceAccountJSON: String) async throws -> (accessToken: String, projectID: String) {
        let account = try GoogleServiceAccount.parse(from: serviceAccountJSON)
        let cacheKey = account.clientEmail

        if let cached = await tokenCache.token(for: cacheKey) {
            return (cached, account.projectID)
        }

        let jwt = try makeJWT(account: account)
        let accessToken = try await exchangeJWTForAccessToken(jwt, tokenURI: account.tokenURI)
        await tokenCache.store(accessToken, for: cacheKey)

        return (accessToken, account.projectID)
    }

    fileprivate static func makePrivateKey(fromPEM pem: String) throws -> SecKey {
        guard let der = derFromPEM(pem) else {
            throw FCMAuthError.invalidPrivateKey
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]

        // 1) PKCS#8 또는 PKCS#1 그대로 시도
        var error: Unmanaged<CFError>?
        if let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) {
            return key
        }

        // 2) Google 서비스 계정은 보통 PKCS#8 → 안의 RSAPrivateKey(PKCS#1) 추출
        if let pkcs1 = extractPKCS1RSAPrivateKey(fromPKCS8: der),
           let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) {
            return key
        }

        throw FCMAuthError.invalidPrivateKey
    }

    private static func makeJWT(account: GoogleServiceAccount) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: String] = [
            "alg": "RS256",
            "typ": "JWT"
        ]
        let claims: [String: Any] = [
            "iss": account.clientEmail,
            "scope": scope,
            "aud": account.tokenURI,
            "iat": now,
            "exp": now + 3600
        ]

        let headerPart = try base64URLJSONObject(header)
        let claimsPart = try base64URLJSONObject(claims)
        let signingInput = "\(headerPart).\(claimsPart)"
        let signature = try signRS256(Data(signingInput.utf8), pem: account.privateKeyPEM)
        return "\(signingInput).\(base64URL(signature))"
    }

    private static func exchangeJWTForAccessToken(_ jwt: String, tokenURI: String) async throws -> String {
        guard let url = URL(string: tokenURI) else {
            throw FCMAuthError.tokenExchangeFailed("token_uri가 올바르지 않습니다.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // assertion JWT는 URL 인코딩이 필요합니다.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        let encodedJWT = jwt.addingPercentEncoding(withAllowedCharacters: allowed) ?? jwt
        let body = "grant_type=\(urlEncode("urn:ietf:params:oauth:grant-type:jwt-bearer"))&assertion=\(encodedJWT)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FCMAuthError.tokenExchangeFailed("응답을 해석할 수 없습니다.")
        }

        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if !(200..<300).contains(http.statusCode) {
            let message = (object?["error_description"] as? String)
                ?? (object?["error"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw FCMAuthError.tokenExchangeFailed(message)
        }

        guard let accessToken = object?["access_token"] as? String, !accessToken.isEmpty else {
            throw FCMAuthError.tokenExchangeFailed("access_token이 없습니다.")
        }
        return accessToken
    }

    private static func signRS256(_ data: Data, pem: String) throws -> Data {
        let secKey = try makePrivateKey(fromPEM: pem)

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &signError
        ) as Data? else {
            throw FCMAuthError.invalidPrivateKey
        }
        return signature
    }

    /// PKCS#8 PrivateKeyInfo에서 OCTET STRING(RSAPrivateKey)을 꺼냅니다.
    private static func extractPKCS1RSAPrivateKey(fromPKCS8 data: Data) -> Data? {
        var offset = 0
        guard let outer = readASN1(data, offset: &offset), outer.tag == 0x30 else { return nil }

        var cursor = 0
        let content = outer.content
        // version
        guard let version = readASN1(content, offset: &cursor), version.tag == 0x02 else { return nil }
        // algorithm
        guard let algorithm = readASN1(content, offset: &cursor), algorithm.tag == 0x30 else { return nil }
        _ = algorithm
        // privateKey OCTET STRING
        guard let privateKeyOctet = readASN1(content, offset: &cursor), privateKeyOctet.tag == 0x04 else {
            return nil
        }
        return privateKeyOctet.content
    }

    private struct ASN1Node {
        let tag: UInt8
        let content: Data
    }

    private static func readASN1(_ data: Data, offset: inout Int) -> ASN1Node? {
        guard offset < data.count else { return nil }
        let tag = data[offset]
        offset += 1
        guard let length = readASN1Length(data, offset: &offset) else { return nil }
        guard offset + length <= data.count else { return nil }
        let content = data.subdata(in: offset..<(offset + length))
        offset += length
        return ASN1Node(tag: tag, content: content)
    }

    private static func readASN1Length(_ data: Data, offset: inout Int) -> Int? {
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

    private static func derFromPEM(_ pem: String) -> Data? {
        let lines = pem
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
        return Data(base64Encoded: lines.joined(), options: [.ignoreUnknownCharacters])
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func base64URLJSONObject(_ object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw FCMAuthError.encodingFailed
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
