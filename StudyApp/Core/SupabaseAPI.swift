import Foundation
import Security

struct BackendConfig {
    let url: URL
    let key: String
    static var current: BackendConfig? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: text), url.scheme == "https", let host = url.host,
              !host.contains("YOUR"),
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.contains("YOUR"), !key.contains("$(") else { return nil }
        return .init(url: url, key: key)
    }
}

enum SessionVault {
    private static let service = "de.elian.studyapp.session"
    static func read() -> AuthSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
    static func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppError.message("Die Sitzung konnte nicht sicher gespeichert werden.") }
        } else if update != errSecSuccess { throw AppError.message("Die Sitzung konnte nicht aktualisiert werden.") }
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// One actor serializes token rotation; concurrent requests share the same refresh task.
actor SupabaseAPI {
    private let config: BackendConfig
    private var session: AuthSession?
    private var refreshing: Task<AuthSession, Error>?
    init(config: BackendConfig) { self.config = config; self.session = SessionVault.read() }
    func storedUser() -> AuthUser? { session?.user }

    private func send(path: String, method: String = "GET", body: Data? = nil, token: String? = nil) async throws -> Data {
        guard let url = URL(string: config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw AppError.message("Ungültige Supabase-Adresse.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppError.message("Keine Antwort vom Server.") }
        guard (200..<300).contains(response.statusCode) else {
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = fields?["msg"] as? String ?? fields?["message"] as? String ?? fields?["error_description"] as? String ?? "Serverfehler (\(response.statusCode))."
            if response.statusCode == 401 { throw AppError.message("Sitzung abgelaufen. Bitte melde dich erneut an.") }
            throw AppError.message(detail)
        }
        return data
    }
    private func accessToken() async throws -> String {
        guard let session else { throw AppError.message("Bitte melde dich an.") }
        if session.expires_at > Date().timeIntervalSince1970 + 60 { return session.access_token }
        if let refreshing { return try await refreshing.value.access_token }
        let refresh = Task<AuthSession, Error> {
            let data = try await self.send(path: "/auth/v1/token?grant_type=refresh_token", method: "POST", body: JSONEncoder().encode(["refresh_token": session.refresh_token]))
            return try JSONDecoder().decode(AuthSession.self, from: data)
        }
        refreshing = refresh
        defer { refreshing = nil }
        let renewed = try await refresh.value
        try SessionVault.save(renewed)
        self.session = renewed
        return renewed.access_token
    }
    func authenticate(email: String, password: String, register: Bool) async throws -> AuthUser? {
        let data = try await send(path: register ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password", method: "POST", body: JSONEncoder().encode(["email": email, "password": password]))
        if let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
            try SessionVault.save(session)
            self.session = session
            return session.user
        }
        if register { return nil }
        throw AppError.message("Anmeldung konnte nicht abgeschlossen werden.")
    }
    func signOut() async {
        if let token = session?.access_token { _ = try? await send(path: "/auth/v1/logout", method: "POST", token: token) }
        session = nil
        SessionVault.clear()
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil, as type: T.Type = T.self) async throws -> T {
        let token = try await accessToken()
        let data = try await send(path: "/rest/v1/" + path, method: method, body: body, token: token)
        return try Self.decoder.decode(T.self, from: data)
    }
    func mutate(_ path: String, method: String, body: Data? = nil) async throws {
        let token = try await accessToken()
        _ = try await send(path: "/rest/v1/" + path, method: method, body: body, token: token)
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw AppError.message("Ungültiges Datumsformat vom Server.") }
            return date
        }
        return decoder
    }
}
