import Foundation

@MainActor
final class PreferencesManager {
  private enum Keys {
    static let showSpeedInMenuBar = "showSpeedInMenuBar"
    static let showNetworkSpeed = "showNetworkSpeed"
    static let lastSelectedDashboardTab = "lastSelectedDashboardTab"

    static let selectedProxies = "selectedProxies"
    static let lastProxyMode = "lastProxyMode"

    static let benchmarkURL = "benchmarkURL"
    static let benchmarkTimeout = "benchmarkTimeout"
    static let logLevel = "logLevel"

    static let dashboardWindowFrame = "dashboardWindowFrame"
    static let settingsWindowFrame = "settingsWindowFrame"
    static let configWindowFrame = "configWindowFrame"
  }

  static let shared = PreferencesManager()

  private let defaults = UserDefaults.standard

  private init() {
    registerDefaults()
  }

  private func registerDefaults() {
    defaults.register(defaults: [
      Keys.showSpeedInMenuBar: true,
      Keys.showNetworkSpeed: true,
      Keys.benchmarkURL: "https://www.apple.com/library/test/success.html",
      Keys.benchmarkTimeout: 5000,
      Keys.logLevel: "info",
      Keys.lastProxyMode: "rule",
    ])
  }

  var showSpeedInMenuBar: Bool {
    get { defaults.bool(forKey: Keys.showSpeedInMenuBar) }
    set { defaults.set(newValue, forKey: Keys.showSpeedInMenuBar) }
  }

  var showNetworkSpeed: Bool {
    get { defaults.bool(forKey: Keys.showNetworkSpeed) }
    set { defaults.set(newValue, forKey: Keys.showNetworkSpeed) }
  }

  var lastSelectedDashboardTab: String? {
    get { defaults.string(forKey: Keys.lastSelectedDashboardTab) }
    set { defaults.set(newValue, forKey: Keys.lastSelectedDashboardTab) }
  }

  var selectedProxies: [String: String] {
    get {
      guard let data = defaults.data(forKey: Keys.selectedProxies),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
      else { return [:] }
      return decoded
    }
    set {
      if let encoded = try? JSONEncoder().encode(newValue) {
        defaults.set(encoded, forKey: Keys.selectedProxies)
      }
    }
  }

  var lastProxyMode: String {
    get { defaults.string(forKey: Keys.lastProxyMode) ?? "rule" }
    set { defaults.set(newValue, forKey: Keys.lastProxyMode) }
  }

  var benchmarkURL: String {
    get {
      defaults
        .string(forKey: Keys.benchmarkURL) ?? "https://www.apple.com/library/test/success.html"
    }
    set { defaults.set(newValue, forKey: Keys.benchmarkURL) }
  }

  var benchmarkTimeout: Int {
    get { defaults.integer(forKey: Keys.benchmarkTimeout) }
    set { defaults.set(newValue, forKey: Keys.benchmarkTimeout) }
  }

  var logLevel: String {
    get { defaults.string(forKey: Keys.logLevel) ?? "info" }
    set { defaults.set(newValue, forKey: Keys.logLevel) }
  }

  func saveWindowFrame(_ frame: NSRect, for window: WindowIdentifier) {
    let key = windowFrameKey(for: window)
    defaults.set(NSStringFromRect(frame), forKey: key)
  }

  func loadWindowFrame(for window: WindowIdentifier) -> NSRect? {
    let key = windowFrameKey(for: window)
    guard let string = defaults.string(forKey: key) else {
      return nil
    }
    return NSRectFromString(string)
  }

  private func windowFrameKey(for window: WindowIdentifier) -> String {
    switch window {
    case .dashboard:
      Keys.dashboardWindowFrame

    case .settings:
      Keys.settingsWindowFrame

    case .config:
      Keys.configWindowFrame
    }
  }

  func clearAll() {
    if let bundleID = Bundle.main.bundleIdentifier {
      defaults.removePersistentDomain(forName: bundleID)
      registerDefaults()
    }
  }

  func exportPreferences() -> [String: Any] {
    [
      "showSpeedInMenuBar": showSpeedInMenuBar,
      "showNetworkSpeed": showNetworkSpeed,
      "selectedProxies": selectedProxies,
      "lastProxyMode": lastProxyMode,
      "benchmarkURL": benchmarkURL,
      "benchmarkTimeout": benchmarkTimeout,
      "logLevel": logLevel,
    ]
  }
}

enum WindowIdentifier {
  case dashboard
  case settings
  case config
}

enum Preferences { }
