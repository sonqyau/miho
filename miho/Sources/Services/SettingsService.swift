import Foundation

@MainActor
protocol SettingsService: AnyObject {
  func initialize() throws
  var allowLAN: Bool { get set }
  var launchAtLogin: Bool { get set }
}

@MainActor
final class SettingsManagerServiceAdapter: SettingsService {
  private let manager: SettingsManager

  init(manager: SettingsManager = .shared) {
    self.manager = manager
  }

  func initialize() throws {
    try manager.initialize()
  }

  var allowLAN: Bool {
    get { manager.allowLAN }
    set { manager.allowLAN = newValue }
  }

  var launchAtLogin: Bool {
    get { manager.launchAtLogin }
    set { manager.launchAtLogin = newValue }
  }
}
