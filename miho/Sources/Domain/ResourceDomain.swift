import Compression
import ErrorKit
import Foundation
import OSLog

@MainActor
@Observable
final class ResourceDomain {
  static let shared = ResourceDomain()

  private let logger = MihoLog.shared.logger(for: .core)

  let configDirectory: URL
  let configFilePath: URL
  let geoIPDatabasePath: URL
  let geoSiteDatabasePath: URL
  let geoIPv6DatabasePath: URL

  var isInitialized = false
  var initializationError: (any Error)?

  private init() {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    configDirectory =
      homeDirectory
        .appendingPathComponent(".config", isDirectory: true)
        .appendingPathComponent("clash", isDirectory: true)

    configFilePath = configDirectory.appendingPathComponent("config.yaml")
    geoIPDatabasePath = configDirectory.appendingPathComponent("Country.mmdb")
    geoSiteDatabasePath = configDirectory.appendingPathComponent("geosite.dat")
    geoIPv6DatabasePath = configDirectory.appendingPathComponent("GeoLite2-Country.mmdb")
  }

  func initialize() async throws {
    do {
      try createConfigDirectoryIfNeeded()
      try await ensureGeoIPDatabase()
      try await ensureGeoSiteDatabase()

      isInitialized = true
      initializationError = nil
      logger.info("Resource initialization complete")
    } catch {
      isInitialized = false
      initializationError = error
      let chain = ErrorKit.errorChainDescription(for: error)
      logger.error("Resource initialization failed\n\(chain)", error: error)
      throw error
    }
  }

  private func createConfigDirectoryIfNeeded() throws {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: configDirectory.path, isDirectory: &isDir)

    if exists, isDir.boolValue {
      return
    }
    if exists, !isDir.boolValue {
      throw ResourceError.configDirectoryIsFile
    }

    do {
      try performFile {
        try FileManager.default.createDirectory(
          at: configDirectory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o755],
        )
      }
    } catch {
      throw ResourceError.cannotCreateConfigDirectory(error)
    }
  }

  private func ensureGeoIPDatabase() async throws {
    if FileManager.default.fileExists(atPath: geoIPDatabasePath.path) {
      if isGeoIPDatabaseValid() {
        logger.debug("GeoIP database valid")
        return
      }
      try? FileManager.default.removeItem(at: geoIPDatabasePath)
    }

    try extractBundledGeoIPDatabase()
    logger.info("GeoIP database extracted")
  }

  private func isGeoIPDatabaseValid() -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: geoIPDatabasePath.path),
          let size = attrs[.size] as? Int64 else { return false }
    return size > 1_000_000
  }

  private func extractBundledGeoIPDatabase() throws {
    guard let path = Bundle.main.url(forResource: "Country.mmdb", withExtension: "lzfse") else {
      if let uncompressed = Bundle.main.url(forResource: "Country", withExtension: "mmdb") {
        try FileManager.default.copyItem(at: uncompressed, to: geoIPDatabasePath)
        return
      }
      throw ResourceError.bundledGeoIPNotFound
    }

    let compressed = try Data(contentsOf: path)
    let decompressed = try decompressLZFSE(compressed)
    try decompressed.write(to: geoIPDatabasePath, options: [.atomic, .completeFileProtection])
  }

  private func ensureGeoSiteDatabase() async throws {
    if FileManager.default.fileExists(atPath: geoSiteDatabasePath.path) {
      return
    }

    guard let path = Bundle.main.url(forResource: "geosite.dat", withExtension: "lzfse")
    else { return }

    do {
      let compressed = try Data(contentsOf: path)
      let decompressed = try decompressLZFSE(compressed)
      try decompressed.write(to: geoSiteDatabasePath, options: .atomic)
    } catch {
      logger.error("GeoSite extract failed", error: error)
    }
  }

  func updateGeoIPDatabase() async throws {
    let apis = [MihomoDomain.shared.upgradeGeo1, MihomoDomain.shared.upgradeGeo2]
    guard let updateAPI = apis.randomElement() else {
      throw ResourceError.updateFailed(NSError(domain: "ResourceDomain", code: -1))
    }
    try await updateAPI()
  }

  func ensureDefaultConfig() throws {
    if FileManager.default.fileExists(atPath: configFilePath.path) {
      return
    }

    guard let bundled = Bundle.main.url(forResource: "config", withExtension: "yaml") else {
      throw ResourceError.bundledConfigNotFound
    }

    try FileManager.default.copyItem(at: bundled, to: configFilePath)
  }

  func listConfigFiles() throws -> [String] {
    try FileManager.default.contentsOfDirectory(
      at: configDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles],
    )
    .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
    .map { $0.deletingPathExtension().lastPathComponent }
    .sorted()
  }

  func configPath(for name: String) -> URL {
    configDirectory.appendingPathComponent("\(name).yaml")
  }

  private func performFile<T>(_ operation: () throws -> T) throws(FileError) -> T {
    try FileError.catch(operation)
  }

  private func decompressLZFSE(_ data: Data) throws -> Data {
    let decompressed = try (data as NSData).decompressed(using: .lzfse) as Data
    guard !decompressed.isEmpty else { throw ResourceError.decompressionFailed }
    return decompressed
  }
}

enum ResourceError: LocalizedError, Throwable {
  case configDirectoryIsFile
  case cannotCreateConfigDirectory(any Error)
  case bundledGeoIPNotFound
  case cannotExtractGeoIP(any Error)
  case bundledConfigNotFound
  case cannotCreateConfig(any Error)
  case decompressionFailed
  case updateFailed(any Error)

  var userFriendlyMessage: String {
    errorDescription ?? "Resource error"
  }

  var errorDescription: String? {
    switch self {
    case .configDirectoryIsFile:
      "Configuration path exists but is a file, not a directory."

    case let .cannotCreateConfigDirectory(error):
      "Unable to create configuration directory: \(error.localizedDescription)"

    case .bundledGeoIPNotFound:
      "Bundled GeoIP database not found in the application bundle."

    case let .cannotExtractGeoIP(error):
      "Unable to extract GeoIP database: \(error.localizedDescription)"

    case .bundledConfigNotFound:
      "Bundled configuration file not found in the application bundle."

    case let .cannotCreateConfig(error):
      "Unable to create configuration file: \(error.localizedDescription)"

    case .decompressionFailed:
      "Failed to decompress LZFSE data."

    case let .updateFailed(error):
      "Failed to update resource: \(error.localizedDescription)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .configDirectoryIsFile:
      "Remove the file at ~/.config/clash, then restart the application."

    case .cannotCreateConfigDirectory:
      "Verify file system permissions and ensure you have write access to ~/.config."

    case .bundledGeoIPNotFound:
      "The application bundle may be corrupted. Reinstall the application."

    case .cannotExtractGeoIP:
      "Check available disk space and file system permissions."

    case .bundledConfigNotFound:
      "The application bundle may be corrupted. Reinstall the application."

    case .cannotCreateConfig:
      "Check file system permissions."

    case .decompressionFailed:
      "The bundled database file may be corrupted. Reinstall the application."

    case .updateFailed:
      "Check your network connection and try again."
    }
  }
}
