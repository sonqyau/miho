import ErrorKit
import Foundation
import SwiftData

@Model
final class SettingsModel {
  var proxyMode = "rule"
  var allowLAN = false
  var systemProxyEnabled = false
  var tunModeEnabled = false
  var apiPort = 9090
  var apiSecret = ""
  var externalControllerURL: String?

  var customGeoIPURL: String?
  var lastGeoIPUpdate: Date?

  var showNetworkSpeed = true
  var selectedConfigName = "config"
  var logLevel = "info"
  var launchAtLogin = false

  var benchmarkURL = "https://www.apple.com/library/test/success.html"
  var benchmarkTimeout = 5000
  var autoUpdateGeoIP = false
  var autoUpdateInterval: TimeInterval = 86400
  var lastSelectedTab = "overview"
  var dashboardRefreshInterval: TimeInterval = 5.0

  var trafficCaptureMode = TrafficCaptureMode.manual.rawValue
  var trafficCapturePreferredDrivers: [String: String] = [:]
  var trafficCaptureAutoFallbackEnabled = true

  var createdAt = Date()
  var updatedAt = Date()

  init() { }

  func updateTimestamp() {
    updatedAt = Date()
  }
}

@MainActor
@Observable
final class SettingsManager {
  static let shared = SettingsManager()

  private(set) var modelContainer: ModelContainer?
  private(set) var settings: SettingsModel?

  private init() { }

  func initialize() throws {
    let schema = Schema([
      SettingsModel.self,
      PersistenceModel.self,
      RemoteInstance.self,
    ])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false,
      allowsSave: true,
    )

    do {
      let container = try ModelContainer(for: schema, configurations: [configuration])
      modelContainer = container

      let context = container.mainContext
      let descriptor = FetchDescriptor<SettingsModel>()
      let existingSettings = try context.fetch(descriptor)

      if let existing = existingSettings.first {
        settings = existing
      } else {
        let newSettings = SettingsModel()
        context.insert(newSettings)
        try context.save()
        settings = newSettings
      }
    } catch {
      throw SettingsError.initializationFailed(error)
    }
  }

  func save() throws {
    guard let container = modelContainer else {
      throw SettingsError.notInitialized
    }

    settings?.updateTimestamp()
    try container.mainContext.save()
  }

  var proxyMode: String {
    get { settings?.proxyMode ?? "rule" }
    set {
      settings?.proxyMode = newValue
      try? save()
    }
  }

  var allowLAN: Bool {
    get { settings?.allowLAN ?? false }
    set {
      settings?.allowLAN = newValue
      try? save()
    }
  }

  var systemProxyEnabled: Bool {
    get { settings?.systemProxyEnabled ?? false }
    set {
      settings?.systemProxyEnabled = newValue
      try? save()
    }
  }

  var tunModeEnabled: Bool {
    get { settings?.tunModeEnabled ?? false }
    set {
      settings?.tunModeEnabled = newValue
      try? save()
    }
  }

  var showNetworkSpeed: Bool {
    get { settings?.showNetworkSpeed ?? true }
    set {
      settings?.showNetworkSpeed = newValue
      try? save()
    }
  }

  var showSpeedInMenuBar: Bool {
    get { settings?.showNetworkSpeed ?? true }
    set {
      settings?.showNetworkSpeed = newValue
      try? save()
    }
  }

  var selectedConfigName: String {
    get { settings?.selectedConfigName ?? "config" }
    set {
      settings?.selectedConfigName = newValue
      try? save()
    }
  }

  var customGeoIPURL: String? {
    get { settings?.customGeoIPURL }
    set {
      settings?.customGeoIPURL = newValue
      try? save()
    }
  }

  var launchAtLogin: Bool {
    get { settings?.launchAtLogin ?? false }
    set {
      settings?.launchAtLogin = newValue
      try? save()
    }
  }

  var trafficCaptureMode: TrafficCaptureMode {
    get {
      TrafficCaptureMode(rawValue: settings?.trafficCaptureMode ?? TrafficCaptureMode.manual
        .rawValue) ?? .manual
    }
    set {
      settings?.trafficCaptureMode = newValue.rawValue
      try? save()
    }
  }

  var trafficCapturePreferredDrivers: [TrafficCaptureMode: TrafficCaptureDriverID] {
    get {
      guard let stored = settings?.trafficCapturePreferredDrivers else {
        return [:]
      }
      var mapping: [TrafficCaptureMode: TrafficCaptureDriverID] = [:]
      for (modeRaw, driverRaw) in stored {
        guard let mode = TrafficCaptureMode(rawValue: modeRaw) else {
          continue
        }
        mapping[mode] = TrafficCaptureDriverID(rawValue: driverRaw)
      }
      return mapping
    }
    set {
      let stored = Dictionary(uniqueKeysWithValues: newValue.map { pair in
        (pair.key.rawValue, pair.value.rawValue)
      })
      settings?.trafficCapturePreferredDrivers = stored
      try? save()
    }
  }

  var trafficCaptureAutoFallbackEnabled: Bool {
    get { settings?.trafficCaptureAutoFallbackEnabled ?? true }
    set {
      settings?.trafficCaptureAutoFallbackEnabled = newValue
      try? save()
    }
  }
}

enum SettingsError: LocalizedError, Throwable {
  case notInitialized
  case initializationFailed(any Error)

  var userFriendlyMessage: String {
    errorDescription ?? "Settings configuration error"
  }

  var errorDescription: String? {
    switch self {
    case .notInitialized:
      "Settings manager has not been initialized"

    case let .initializationFailed(error):
      "Unable to initialize settings: \(error.localizedDescription)"
    }
  }
}

struct SettingsSnapshots {
  let proxy: ProxySnapshot
  let capture: TrafficCaptureSnapshot
  let daemon: DaemonSnapshot
  let launch: LaunchSnapshot
}
