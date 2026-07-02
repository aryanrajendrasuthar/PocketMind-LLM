//
// PocketMind — On-Device Private LLM for iPhone
// Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
//
// PROPRIETARY AND CONFIDENTIAL
// Unauthorized copying, distribution, modification, or use of this file,
// via any medium, is strictly prohibited without the express written
// permission of the copyright owner.
//
// For licensing inquiries: aryanrajendrasuthar@gmail.com
//

import CryptoKit
import Foundation
import os.log
import Security

/// Derives and manages the SQLCipher database encryption key using the Secure Enclave.
///
/// Key derivation process:
/// 1. Generate (or retrieve) an EC-P256 private key stored in the Secure Enclave.
/// 2. Generate an ephemeral EC-P256 public key on the app side.
/// 3. Perform ECDH to produce a shared secret.
/// 4. Derive the final 32-byte key using HKDF-SHA256.
///
/// The Secure Enclave key is hardware-bound: it cannot be extracted, and is
/// destroyed on factory reset. The derived key exists only in memory.
enum SecureEnclaveKeyManager {

    private static let logger = Logger(
        subsystem: Constants.bundleIdentifier,
        category: "SecureEnclaveKeyManager"
    )

    // MARK: - Public API

    /// Returns the 32-byte SQLCipher database key, deriving it if necessary.
    /// This is safe to call from any actor context — it performs no async work.
    static func deriveDatabaseKey() throws -> SymmetricKey {
        let enclaveKey = try loadOrCreateSecureEnclaveKey()
        return try deriveKey(from: enclaveKey)
    }

    /// Deletes the Secure Enclave key from the keychain.
    /// After this call, any existing SQLCipher database is permanently inaccessible.
    static func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(Constants.Keychain.secureEnclaveKeyTag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.keychainError(status)
        }
        logger.info("Secure Enclave key deleted.")
    }

    // MARK: - Key lifecycle

    private static func loadOrCreateSecureEnclaveKey() throws -> SecKey {
        if let existing = try? loadKey() {
            return existing
        }
        return try createKey()
    }

    private static func loadKey() throws -> SecKey {
        let tag = Data(Constants.Keychain.secureEnclaveKeyTag.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let secKey = result, CFGetTypeID(secKey) == SecKeyGetTypeID() else {
            throw KeyManagerError.keychainError(status)
        }
        return secKey as! SecKey  // swiftlint:disable:this force_cast — type checked via CFGetTypeID above
    }

    private static func createKey() throws -> SecKey {
        let tag = Data(Constants.Keychain.secureEnclaveKeyTag.utf8)

        let accessControl = try makeAccessControl()
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: accessControl,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? KeyManagerError.keyCreationFailed
        }
        logger.info("Secure Enclave key created.")
        return privateKey
    }

    private static func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let ac = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            throw error?.takeRetainedValue() ?? KeyManagerError.accessControlCreationFailed
        }
        return ac
    }

    // MARK: - Key derivation

    private static func deriveKey(from enclavePrivateKey: SecKey) throws -> SymmetricKey {
        guard SecKeyCopyPublicKey(enclavePrivateKey) != nil else {
            throw KeyManagerError.publicKeyExtractionFailed
        }

        // Generate an ephemeral P-256 key pair on the CPU side
        let ephemeralKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKeyData = ephemeralKey.publicKey.x963Representation

        // Perform ECDH: Secure Enclave private × ephemeral public → shared secret
        let params: [String: Any] = [
            SecKeyKeyExchangeParameter.requestedSize.rawValue as String: 32,
            SecKeyKeyExchangeParameter.sharedInfo.rawValue as String: Data("pocketmind.dbkey.v1".utf8),
        ]

        // Convert ephemeral public key bytes into a SecKey for the exchange
        let ephemeralSecKey = try secKeyFromData(ephemeralPublicKeyData)

        var exchangeError: Unmanaged<CFError>?
        guard let sharedSecretData = SecKeyCopyKeyExchangeResult(
            enclavePrivateKey,
            .ecdhKeyExchangeStandard,
            ephemeralSecKey,
            params as CFDictionary,
            &exchangeError
        ) else {
            throw exchangeError?.takeRetainedValue() ?? KeyManagerError.keyExchangeFailed
        }

        // HKDF-SHA256 to produce the final 32-byte SQLCipher key
        let inputKeyMaterial = SymmetricKey(data: sharedSecretData as Data)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: Data("pocketmind".utf8),
            info: Data("dbkey.v1".utf8),
            outputByteCount: 32
        )
        return derivedKey
    }

    private static func secKeyFromData(_ data: Data) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? KeyManagerError.keyCreationFailed
        }
        return key
    }

    // MARK: - Errors

    enum KeyManagerError: Error, LocalizedError {
        case keychainError(OSStatus)
        case keyCreationFailed
        case accessControlCreationFailed
        case publicKeyExtractionFailed
        case keyExchangeFailed

        var errorDescription: String? {
            switch self {
            case .keychainError(let status):
                return "Keychain operation failed with status \(status)."
            case .keyCreationFailed:
                return "Failed to create Secure Enclave key."
            case .accessControlCreationFailed:
                return "Failed to create access control for Secure Enclave key."
            case .publicKeyExtractionFailed:
                return "Failed to extract public key from Secure Enclave key."
            case .keyExchangeFailed:
                return "ECDH key exchange with Secure Enclave failed."
            }
        }
    }
}
