import Combine
import Foundation

@MainActor
protocol TrafficCaptureService: AnyObject {
  var statePublisher: AnyPublisher<TrafficCaptureDomain.State, Never> { get }
  func currentState() -> TrafficCaptureDomain.State
  func activate(mode: TrafficCaptureMode, context: TrafficCaptureActivationContext) async throws
  func deactivateCurrentMode() async
  func setPreferredDriver(_ id: TrafficCaptureDriverID?, for mode: TrafficCaptureMode)
  var autoFallbackEnabled: Bool { get set }
}

@MainActor
final class TrafficCaptureDomainServiceAdapter: TrafficCaptureService {
  private let domain: TrafficCaptureDomain

  init(domain: TrafficCaptureDomain = .shared) {
    self.domain = domain
  }

  var statePublisher: AnyPublisher<TrafficCaptureDomain.State, Never> {
    domain.statePublisher()
  }

  func currentState() -> TrafficCaptureDomain.State {
    domain.currentState()
  }

  func activate(mode: TrafficCaptureMode, context: TrafficCaptureActivationContext) async throws {
    try await domain.activate(mode: mode, context: context)
  }

  func deactivateCurrentMode() async {
    await domain.deactivateCurrentMode()
  }

  func setPreferredDriver(_ id: TrafficCaptureDriverID?, for mode: TrafficCaptureMode) {
    domain.setPreferredDriver(id, for: mode)
  }

  var autoFallbackEnabled: Bool {
    get { domain.autoFallbackEnabled }
    set { domain.autoFallbackEnabled = newValue }
  }
}
