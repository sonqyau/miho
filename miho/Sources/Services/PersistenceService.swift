import Combine
import Foundation
import SwiftData

@MainActor
protocol PersistenceService {
  var statePublisher: AnyPublisher<PersistenceDomain.State, Never> { get }
  var configs: [PersistenceModel] { get }
  var remoteInstances: [RemoteInstance] { get }
  var isLocalMode: Bool { get }
  var activeRemoteInstance: RemoteInstance? { get }
  func initialize(container: ModelContainer) throws
  func addConfig(name: String, url: String) async throws
  func removeConfig(_ config: PersistenceModel) throws
  func updateConfig(_ config: PersistenceModel) async throws
  func activateConfig(_ config: PersistenceModel) async throws
  func updateAllConfigs() async
  func addRemoteInstance(name: String, apiURL: String, secret: String?) throws
  func removeRemoteInstance(_ instance: RemoteInstance) throws
  func activateRemoteInstance(_ instance: RemoteInstance?)
}

@MainActor
struct RemoteConfigPersistenceServiceAdapter: PersistenceService {
  private let domain: PersistenceDomain

  init(domain: PersistenceDomain = .shared) {
    self.domain = domain
  }

  var statePublisher: AnyPublisher<PersistenceDomain.State, Never> {
    domain.statePublisher()
  }

  var configs: [PersistenceModel] { domain.configs }
  var remoteInstances: [RemoteInstance] { domain.remoteInstances }
  var isLocalMode: Bool { domain.isLocalMode }
  var activeRemoteInstance: RemoteInstance? { domain.activeRemoteInstance }

  func initialize(container: ModelContainer) throws {
    try domain.initialize(container: container)
  }

  func addConfig(name: String, url: String) async throws {
    try await domain.addConfig(name: name, url: url)
  }

  func removeConfig(_ config: PersistenceModel) throws {
    try domain.removeConfig(config)
  }

  func updateConfig(_ config: PersistenceModel) async throws {
    try await domain.updateConfig(config)
  }

  func activateConfig(_ config: PersistenceModel) async throws {
    try await domain.activateConfig(config)
  }

  func updateAllConfigs() async {
    await domain.updateAllConfigs()
  }

  func addRemoteInstance(name: String, apiURL: String, secret: String?) throws {
    try domain.addRemoteInstance(name: name, apiURL: apiURL, secret: secret)
  }

  func removeRemoteInstance(_ instance: RemoteInstance) throws {
    try domain.removeRemoteInstance(instance)
  }

  func activateRemoteInstance(_ instance: RemoteInstance?) {
    domain.activateRemoteInstance(instance)
  }
}
