import Combine
import Foundation

@MainActor
protocol LaunchAtLoginService {
  var statePublisher: AnyPublisher<LaunchAtLoginManager.State, Never> { get }
  func currentState() -> LaunchAtLoginManager.State
  func toggle() throws
  func updateStatus()
  func openSystemSettings()
}

@MainActor
struct LaunchAtLoginManagerServiceAdapter: LaunchAtLoginService {
  private let manager: LaunchAtLoginManager

  init(manager: LaunchAtLoginManager = .shared) {
    self.manager = manager
  }

  var statePublisher: AnyPublisher<LaunchAtLoginManager.State, Never> {
    manager.statePublisher()
  }

  func currentState() -> LaunchAtLoginManager.State {
    manager.state
  }

  func toggle() throws {
    try manager.toggle()
  }

  func updateStatus() {
    manager.updateStatus()
  }

  func openSystemSettings() {
    manager.openSystemSettings()
  }
}
