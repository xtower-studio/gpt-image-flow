import Foundation
import Security
import Observation
import FlowCore

@MainActor @Observable final class APIConnection {
    private(set) var ready = false
    private(set) var checking = false
    private(set) var savedKeyNeedsPermission = false
    var message: String?
    @ObservationIgnored private var cached: APICredentials?
    init() { Task { await restoreSavedConnection() } }
    func restoreSavedConnection(interactive: Bool = false) async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        let (credentials, status) = await APIKeychain.shared.read(interactive: interactive)
        if let credentials {
            cached = credentials; ready = true; savedKeyNeedsPermission = false
            if interactive { message = "저장한 API 키를 사용할 수 있습니다." }
        } else if status != errSecItemNotFound {
            savedKeyNeedsPermission = true
            message = "저장한 API 키를 사용하려면 macOS 키체인 접근을 허용해 주세요."
        }
    }
    func credentials() throws -> APICredentials {
        guard let cached else { throw FlowError.message("설정에서 OpenAI API 키를 연결하세요.") }
        return cached
    }
    func connect(key: String, organization: String, project: String) async {
        guard !checking else { return }
        checking = true; message = nil
        defer { checking = false }
        let value = APICredentials(key: key.trimmingCharacters(in: .whitespacesAndNewlines), organization: organization.trimmingCharacters(in: .whitespacesAndNewlines), project: project.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await ImageAPIClient().verify(value)
            try await APIKeychain.shared.save(value)
            cached = value; ready = true; savedKeyNeedsPermission = false
            message = "연결되었습니다. 실제 이미지 생성 권한·잔액은 생성 요청 시 확인됩니다."
        } catch { message = Self.safeMessage(error) }
    }
    func disconnect() async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        let status = await APIKeychain.shared.delete()
        guard status == errSecSuccess || status == errSecItemNotFound else { message = "키체인에서 삭제하지 못했습니다 (\(status))."; return }
        cached = nil; ready = false; savedKeyNeedsPermission = false; message = "이 Mac에서 API 키를 삭제했습니다."
    }
    static func safeMessage(_ error: Error) -> String {
        if error is ImageAPIError || error is FlowError { return error.localizedDescription }
        return "API에 연결하지 못했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요."
    }
}

// File-based macOS keychain supports the unsigned/local development bundle too.
// Serialize blocking Security calls away from the main actor. LAContext's no-UI
// flag only covers the data-protection keychain, so suppress classic ACL prompts
// explicitly during automatic restore; the user can unlock from the connection UI.
private actor APIKeychain {
    static let shared = APIKeychain()
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.imageflow.mac.openai-api", kSecAttrAccount as String: "personal"]
    }
    func read(interactive: Bool) -> (APICredentials?, OSStatus) {
        var previous: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&previous)
        SecKeychainSetUserInteractionAllowed(interactive)
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess, let data = value as? Data,
              let credentials = try? JSONDecoder().decode(APICredentials.self, from: data) else { return (nil, status) }
        return (credentials, status)
    }
    func save(_ value: APICredentials) throws {
        let data = try JSONEncoder().encode(value)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FlowError.message("macOS 키체인에 저장하지 못했습니다 (\(status)).") }
    }
    func delete() -> OSStatus { SecItemDelete(query as CFDictionary) }
}
