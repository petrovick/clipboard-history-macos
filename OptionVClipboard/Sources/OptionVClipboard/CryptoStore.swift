import Foundation
import CryptoKit

/// A store that encrypts and decrypts history payloads with AES-GCM.
protocol HistoryCrypting {
    /// Encrypts plaintext JSON with the supplied raw 32-byte key.
    func encrypt(_ plaintext: Data, using keyData: Data) throws -> Data

    /// Decrypts AES-GCM ciphertext with the supplied raw 32-byte key.
    func decrypt(_ ciphertext: Data, using keyData: Data) throws -> Data
}

/// Encrypts and decrypts clipboard history data.
struct CryptoStore: HistoryCrypting {
    /// Errors thrown by AES-GCM operations.
    private enum Error: Swift.Error {
        case invalidKeyLength
        case invalidSealedBoxRepresentation
    }

    /// Encrypts plaintext JSON using AES-GCM and returns the sealed box combined representation.
    func encrypt(_ plaintext: Data, using keyData: Data) throws -> Data {
        let symmetricKey = try makeSymmetricKey(from: keyData)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)

        guard let combined = sealedBox.combined else {
            throw Error.invalidSealedBoxRepresentation
        }

        return combined
    }

    /// Decrypts AES-GCM combined data back into plaintext JSON.
    func decrypt(_ ciphertext: Data, using keyData: Data) throws -> Data {
        let symmetricKey = try makeSymmetricKey(from: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    private func makeSymmetricKey(from keyData: Data) throws -> SymmetricKey {
        guard keyData.count == 32 else {
            throw Error.invalidKeyLength
        }

        return SymmetricKey(data: keyData)
    }
}
