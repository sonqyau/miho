import ErrorKit
import Foundation
import Security

final class Keychain: @unchecked Sendable {
  static let shared = Keychain()

  private let service = "com.swift.miho.secrets"

  private init() { }

  private func performKeychain<T>(_ operation: () throws -> T) throws(GenericError) -> T {
    try GenericError.catch(operation)
  }

  func setSecret(_ secret: String, for key: String) throws {
    let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmedSecret.data(using: .utf8) else {
      throw KeychainError.stringEncodingFailure
    }

    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]

    let attributesToUpdate: [CFString: Any] = [kSecValueData: data]

    let status: OSStatus = try performKeychain {
      SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    }

    switch status {
    case errSecSuccess:
      return

    case errSecItemNotFound:
      var addQuery = query
      addQuery[kSecValueData] = data
      let addStatus: OSStatus = try performKeychain {
        SecItemAdd(addQuery as CFDictionary, nil)
      }
      guard addStatus == errSecSuccess else {
        throw KeychainError.unexpectedStatus(addStatus)
      }

    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  func secret(for key: String) throws -> String? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecReturnData: true,
    ]

    var item: CFTypeRef?
    let status: OSStatus = try performKeychain {
      SecItemCopyMatching(query as CFDictionary, &item)
    }

    switch status {
    case errSecSuccess:
      guard let data = item as? Data else {
        throw KeychainError.unexpectedStatus(errSecInternalError)
      }
      guard let secret = String(data: data, encoding: .utf8) else {
        throw KeychainError.stringEncodingFailure
      }
      return secret

    case errSecItemNotFound:
      return nil

    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  func deleteSecret(for key: String) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key,
    ]

    let status: OSStatus = try performKeychain {
      SecItemDelete(query as CFDictionary)
    }

    switch status {
    case errSecSuccess, errSecItemNotFound:
      return

    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }
}

enum KeychainError: LocalizedError, Throwable {
  case unexpectedStatus(OSStatus)
  case stringEncodingFailure

  var userFriendlyMessage: String {
    errorDescription ?? "Keychain operation failed"
  }

  var errorDescription: String? {
    switch self {
    case let .unexpectedStatus(status):
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "Keychain operation failed: \(message)"
      }
      return "Keychain operation failed with status code \(status)"

    case .stringEncodingFailure:
      return "Unable to encode secret for secure storage"
    }
  }
}
