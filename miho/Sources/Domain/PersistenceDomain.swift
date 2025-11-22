@preconcurrency import Combine
import ErrorKit
import Foundation
import OSLog
import SwiftData
import UserNotifications

@MainActor
@Observable
final class PersistenceDomain {
  static let shared = PersistenceDomain()

  struct State {
    var configs: [PersistenceModel]
    var remoteInstances: [RemoteInstance]
    var isLocalMode: Bool
    var activeRemoteInstance: RemoteInstance?
  }

  private let logger = MihoLog.shared.logger(for: .core)
  private let resourceManager = ResourceDomain.shared
  private let apiClient = MihomoDomain.shared

  private let stateSubject: CurrentValueSubject<State, Never>

  private(set) var modelContainer: ModelContainer?
  private(set) var configs: [PersistenceModel] = [] {
    didSet { emitState() }
  }

  private(set) var remoteInstances: [RemoteInstance] = [] {
    didSet { emitState() }
  }

  private var autoUpdateTask: Task<Void, Never>?
  private let defaultUpdateInterval: TimeInterval = 7200

  var isLocalMode: Bool {
    !remoteInstances.contains(where: { $0.isActive })
  }

  var activeRemoteInstance: RemoteInstance? {
    remoteInstances.first(where: { $0.isActive })
  }

  private init() {
    stateSubject = CurrentValueSubject(
      State(
        configs: [],
        remoteInstances: [],
        isLocalMode: true,
        activeRemoteInstance: nil,
      ),
    )
  }

  func statePublisher() -> AnyPublisher<State, Never> {
    stateSubject
      .receive(on: RunLoop.main)
      .eraseToAnyPublisher()
  }

  private var state: State {
    State(
      configs: configs,
      remoteInstances: remoteInstances,
      isLocalMode: isLocalMode,
      activeRemoteInstance: activeRemoteInstance,
    )
  }

  private func emitState() {
    stateSubject.send(state)
  }

  private func mapError(_ error: any Error) -> PersistenceError {
    if let remoteError = error as? PersistenceError {
      return remoteError
    }
    return .validationFailed(error.mihoMessage)
  }

  private func performDatabase<T>(_ operation: () throws -> T) throws(DatabaseError) -> T {
    try DatabaseError.catch(operation)
  }

  func initialize(container: ModelContainer) throws(PersistenceError) {
    modelContainer = container
    try loadConfigs()
    try loadRemoteInstances()
    setupAutoUpdate()
  }

  private func loadConfigs() throws(PersistenceError) {
    guard let container = modelContainer else {
      throw PersistenceError.notInitialized
    }

    let context = container.mainContext
    let descriptor = FetchDescriptor<PersistenceModel>(
      sortBy: [SortDescriptor(\.createdAt)],
    )

    do {
      configs = try performDatabase {
        try context.fetch(descriptor)
      }
      logger.info("Loaded \(configs.count) remote configurations.")
    } catch {
      throw mapError(error)
    }
  }

  private func loadRemoteInstances() throws(PersistenceError) {
    guard let container = modelContainer else {
      throw PersistenceError.notInitialized
    }

    let context = container.mainContext
    let descriptor = FetchDescriptor<RemoteInstance>(
      sortBy: [SortDescriptor(\.createdAt)],
    )

    do {
      let instances = try performDatabase {
        try context.fetch(descriptor)
      }
      let didMigrateSecrets = migrateLegacySecrets(for: instances)
      remoteInstances = instances
      if didMigrateSecrets {
        try performDatabase {
          try context.save()
        }
      }
      logger.info("Loaded \(remoteInstances.count) remote instances")
    } catch {
      throw mapError(error)
    }
  }

  func addConfig(name: String, url: String) async throws(PersistenceError) {
    guard let container = modelContainer else { throw PersistenceError.notInitialized }
    guard URL(string: url) != nil else { throw PersistenceError.invalidURL }
    guard !configs.contains(where: { $0.url == url }) else { throw PersistenceError.duplicateURL }

    do {
      let cfg = PersistenceModel(name: name, url: url)
      container.mainContext.insert(cfg)

      try container.mainContext.save()
      try loadConfigs()

      try await updateConfig(cfg)
    } catch {
      throw mapError(error)
    }
  }

  func removeConfig(_ config: PersistenceModel) throws(PersistenceError) {
    guard let container = modelContainer else {
      throw PersistenceError.notInitialized
    }

    let context = container.mainContext
    context.delete(config)

    do {
      try context.save()
      try loadConfigs()

      logger.info("Removed remote configuration: \(config.name).")
    } catch {
      throw mapError(error)
    }
  }

  func updateConfig(_ config: PersistenceModel) async throws(PersistenceError) {
    guard let url = URL(string: config.url) else { throw PersistenceError.invalidURL }

    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    req.setValue("miho/1.0", forHTTPHeaderField: "User-Agent")

    let capturedRequest = req
    do {
      let (data, resp) = try await NetworkError.catch { @Sendable () async throws -> (
        Data,
        URLResponse
      ) in
        try await URLSession.shared.data(for: capturedRequest)
      }

      guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw PersistenceError.downloadFailed
      }

      guard let content = String(data: data, encoding: .utf8) else {
        throw PersistenceError.invalidEncoding
      }

      let result = try await ConfigValidation.shared.validateContent(content)
      guard result.isValid else {
        throw PersistenceError.validationFailed(result.errorMessage ?? "Invalid configuration.")
      }

      let path = resourceManager.configDirectory.appendingPathComponent("\(config.name).yaml")
      try content.write(to: path, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)

      config.lastUpdated = Date()
      config.updatedAt = Date()

      try modelContainer?.mainContext.save()

      if config.isActive {
        try await reloadActiveConfig()
      }

      emitState()
    } catch {
      throw mapError(error)
    }
  }

  func activateConfig(_ config: PersistenceModel) async throws(PersistenceError) {
    configs.forEach { $0.isActive = false }

    config.isActive = true

    do {
      try modelContainer?.mainContext.save()

      let src = resourceManager.configDirectory.appendingPathComponent("\(config.name).yaml")
      let dst = resourceManager.configFilePath

      guard FileManager.default.fileExists(atPath: src.path) else {
        throw PersistenceError.validationFailed("Source configuration not found.")
      }

      try backupConfig()

      if FileManager.default.fileExists(atPath: dst.path) {
        try FileManager.default.removeItem(at: dst)
      }

      try FileManager.default.copyItem(at: src, to: dst)
      try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dst.path)
      try await reloadActiveConfig()

      emitState()
    } catch {
      throw mapError(error)
    }
  }

  func validateConfig(at path: String) async throws(PersistenceError) {
    do {
      let result = try await ConfigValidation.shared.validate(configPath: path)
      guard result.isValid else {
        throw PersistenceError.validationFailed(
          result.errorMessage ?? "Unknown configuration validation error.",
        )
      }
    } catch {
      throw mapError(error)
    }
  }

  private func reloadActiveConfig() async throws {
    try await apiClient.reloadConfig(
      path: resourceManager.configFilePath.path,
      payload: "",
    )
  }

  func backupConfig() throws(PersistenceError) {
    let path = resourceManager.configFilePath
    guard FileManager.default.fileExists(atPath: path.path) else {
      return
    }

    do {
      let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
      let backup = resourceManager.configDirectory
        .appendingPathComponent("config_backup_\(ts).yaml")

      try FileManager.default.copyItem(at: path, to: backup)
      try cleanupOldBackups()
    } catch {
      throw mapError(error)
    }
  }

  private func cleanupOldBackups() throws(PersistenceError) {
    do {
      let backups = try FileManager.default.contentsOfDirectory(
        at: resourceManager.configDirectory,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles],
      )
      .filter { $0.lastPathComponent.hasPrefix("config_backup_") }
      .sorted { url1, url2 in
        let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?
          .creationDate ?? .distantPast
        let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?
          .creationDate ?? .distantPast
        return d1 > d2
      }

      for old in backups.dropFirst(10) {
        try FileManager.default.removeItem(at: old)
      }
    } catch {
      throw mapError(error)
    }
  }

  private func setupAutoUpdate() {
    autoUpdateTask?.cancel()
    autoUpdateTask = Task(priority: .utility) { [weak self] in
      guard let self else {
        return
      }

      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(defaultUpdateInterval))
        guard !Task.isCancelled else { break }
        await performAutoUpdate()
      }
    }
  }

  private func performAutoUpdate() async {
    for cfg in configs where cfg.autoUpdate {
      do {
        try await updateConfig(cfg)
        if cfg.isActive {
          await sendNotification(
            title: "Configuration updated",
            body: "\(cfg.name) was updated successfully.",
          )
        }
      } catch {
        let chain = ErrorKit.errorChainDescription(for: error)
        logger.error(
          "Failed to update configuration \(cfg.name): \(error.localizedDescription)\n\(chain)",
        )
        if cfg.isActive {
          await sendNotification(
            title: "Configuration update failed",
            body: "\(cfg.name): \(error.localizedDescription)",
          )
        }
      }
    }
  }

  func updateAllConfigs() async {
    for config in configs {
      do {
        try await updateConfig(config)
      } catch {
        let chain = ErrorKit.errorChainDescription(for: error)
        logger.error(
          "Failed to update configuration \(config.name): \(error.localizedDescription)\n\(chain)",
        )
      }
    }

    emitState()
  }

  func addRemoteInstance(name: String, apiURL: String, secret: String?) throws(PersistenceError) {
    guard let container = modelContainer else {
      throw PersistenceError.notInitialized
    }

    let sanitizedName: String
    let sanitizedURL: String
    let sanitizedSecret: String?

    do {
      sanitizedName = try InputValidation.sanitizedIdentifier(name, fieldName: "instance name")
      sanitizedURL = try InputValidation.sanitizedURLString(apiURL)
      sanitizedSecret = try InputValidation.sanitizedSecret(secret)
    } catch {
      throw PersistenceError.validationFailed(error.mihoMessage)
    }

    let instance = RemoteInstance(name: sanitizedName, apiURL: sanitizedURL)
    let context = container.mainContext
    context.insert(instance)

    do {
      try instance.updateSecret(sanitizedSecret)
    } catch {
      context.delete(instance)
      throw PersistenceError.secretStorageFailed(error.mihoMessage)
    }

    do {
      try context.save()
      try loadRemoteInstances()

      logger.info("Added remote instance: \(sanitizedName).")
    } catch {
      throw mapError(error)
    }
  }

  func removeRemoteInstance(_ instance: RemoteInstance) throws(PersistenceError) {
    guard let container = modelContainer else {
      throw PersistenceError.notInitialized
    }

    let context = container.mainContext
    try? instance.clearSecret()
    context.delete(instance)

    do {
      try context.save()
      try loadRemoteInstances()

      logger.info("Removed remote instance: \(instance.name).")
    } catch {
      throw mapError(error)
    }
  }

  func activateRemoteInstance(_ instance: RemoteInstance?) {
    for inst in remoteInstances {
      inst.isActive = false
    }

    if let instance {
      instance.isActive = true
      instance.lastConnected = Date()

      apiClient.configure(baseURL: instance.apiURL, secret: instance.secret)

      logger.info("Activated remote instance: \(instance.name).")
    } else {
      apiClient.configure(baseURL: "http://127.0.0.1:9090", secret: nil)
      logger.info("Switched to local mode.")
    }

    try? modelContainer?.mainContext.save()

    apiClient.disconnect()
    apiClient.connect()

    emitState()
  }

  private func sendNotification(title: String, body: String) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

    try? await UNUserNotificationCenter.current().add(req)
  }

  private func migrateLegacySecrets(for instances: [RemoteInstance]) -> Bool {
    var didMigrate = false

    for instance in instances {
      guard let legacySecret = instance.persistedSecret, !legacySecret.isEmpty else {
        continue
      }

      do {
        try instance.updateSecret(legacySecret)
        didMigrate = true
      } catch {
        logger.error(
          "Failed migrating secret for instance \(instance.name): \(error.localizedDescription)",
          metadata: [
            "instance": instance.name,
            "error": error.localizedDescription,
          ],
        )
      }
    }

    return didMigrate
  }
}

enum PersistenceError: LocalizedError, Throwable {
  case notInitialized
  case invalidURL
  case duplicateURL
  case downloadFailed
  case invalidEncoding
  case validationFailed(String)
  case secretStorageFailed(String)

  var userFriendlyMessage: String {
    errorDescription ?? "Remote configuration error"
  }

  var errorDescription: String? {
    switch self {
    case .notInitialized:
      "Remote configuration manager is not initialized."

    case .invalidURL:
      "The URL is invalid."

    case .duplicateURL:
      "A configuration with this URL already exists."

    case .downloadFailed:
      "Failed to download configuration."

    case .invalidEncoding:
      "The configuration file uses an unsupported or invalid text encoding."

    case let .validationFailed(reason):
      "Configuration validation failed: \(reason)"

    case let .secretStorageFailed(reason):
      "Failed to store the secret securely: \(reason)"
    }
  }
}
