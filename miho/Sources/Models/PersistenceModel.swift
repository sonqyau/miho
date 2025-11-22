import Dependencies
import Foundation
import OSLog
import SwiftData

private struct PersistenceModelDependencies {
  @Dependency(\.uuid)
  var uuid

  @Dependency(\.date)
  var date
}

private enum RemoteInstanceKeychain {
  static let prefix = "com.swift.miho.remote-instance"

  static func key(for id: UUID) -> String {
    "\(prefix).\(id.uuidString)"
  }
}

private struct RemoteInstanceDependencies {
  @Dependency(\.keychain)
  var keychain
}

@Model
final class PersistenceModel {
  @Attribute(.unique)
  var id: UUID

  var name: String
  var url: String
  var lastUpdated: Date?
  var isActive: Bool
  var autoUpdate: Bool

  @Attribute var createdAt: Date

  @Attribute var updatedAt: Date

  init(name: String, url: String, autoUpdate: Bool = true) {
    let dependencies = PersistenceModelDependencies()
    id = dependencies.uuid()
    self.name = name
    self.url = url
    self.autoUpdate = autoUpdate
    isActive = false
    lastUpdated = nil
    createdAt = dependencies.date()
    updatedAt = dependencies.date()
  }

  func displayTimeString() -> String {
    guard let date = lastUpdated else {
      return String(localized: "Never updated", table: "Localizable", bundle: .module)
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
  }
}

@Model
final class RemoteInstance {
  private static let logger = MihoLog.shared.logger(for: .service)

  @Attribute(.unique)
  var id: UUID
  var name: String
  var apiURL: String
  var persistedSecret: String?
  var isActive: Bool

  var createdAt: Date
  var lastConnected: Date?

  init(name: String, apiURL: String, secret: String? = nil) {
    let dependencies = PersistenceModelDependencies()
    id = dependencies.uuid()
    self.name = name
    self.apiURL = apiURL
    persistedSecret = secret
    isActive = false
    createdAt = dependencies.date()
  }

  @Transient var secret: String? {
    do {
      let dependencies = RemoteInstanceDependencies()
      if let keychainSecret = try dependencies.keychain.secret(
        RemoteInstanceKeychain.key(for: id),
      ) {
        return keychainSecret
      }
    } catch {
      Self.logger.error(
        "Unable to read secret from Keychain",
        metadata: ["error": String(describing: error)],
      )
    }

    return persistedSecret
  }

  func updateSecret(_ newSecret: String?) throws {
    let dependencies = RemoteInstanceDependencies()
    if let secret = newSecret, !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try dependencies.keychain.setSecret(
        secret,
        RemoteInstanceKeychain.key(for: id),
      )
    } else {
      try dependencies.keychain.deleteSecret(
        RemoteInstanceKeychain.key(for: id),
      )
    }
    persistedSecret = nil
  }

  func clearSecret() throws {
    try updateSecret(nil)
  }
}
