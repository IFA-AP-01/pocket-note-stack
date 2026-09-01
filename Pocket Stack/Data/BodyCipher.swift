import CryptoKit
import Foundation

struct BodyCipher: Sendable {
    private let key: SymmetricKey

    init(keychain: KeychainStore = KeychainStore(), account: String = "notes-aes-key-v1") throws {
        if let stored = try keychain.data(for: account), stored.count == 32 {
            key = SymmetricKey(data: stored)
        } else {
            let generated = SymmetricKey(size: .bits256)
            let bytes = generated.withUnsafeBytes { Data($0) }
            try keychain.set(bytes, for: account)
            key = generated
        }
    }

    init(rawKey: Data) { key = SymmetricKey(data: rawKey) }

    func seal(_ text: String) throws -> Data {
        guard let combined = try AES.GCM.seal(Data(text.utf8), using: key).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return combined
    }

    func open(_ data: Data) throws -> String {
        let box = try AES.GCM.SealedBox(combined: data)
        return String(decoding: try AES.GCM.open(box, using: key), as: UTF8.self)
    }
}
