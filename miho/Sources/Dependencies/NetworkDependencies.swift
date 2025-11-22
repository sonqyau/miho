import Dependencies

struct NetworkInspectorClient {
  var isSystemProxySetToMihomo: @Sendable (_ httpPort: Int, _ socksPort: Int, _ strict: Bool) async
    -> Bool
  var getPrimaryInterfaceName: @Sendable () async -> String?
  var getPrimaryIPAddress: @Sendable (_ allowIPv6: Bool) async -> String?
}

enum NetworkInspectorClientKey: DependencyKey {
  static let liveValue = NetworkInspectorClient(
    isSystemProxySetToMihomo: { httpPort, socksPort, strict in
      await MainActor.run {
        NetworkDomain.shared.isSystemProxySetToMihomo(
          httpPort: httpPort,
          socksPort: socksPort,
          strict: strict,
        )
      }
    },
    getPrimaryInterfaceName: {
      await MainActor.run {
        NetworkDomain.shared.getPrimaryInterfaceName()
      }
    },
    getPrimaryIPAddress: { allowIPv6 in
      await MainActor.run {
        NetworkDomain.shared.getPrimaryIPAddress(allowIPv6: allowIPv6)
      }
    },
  )
}

extension DependencyValues {
  var networkInspector: NetworkInspectorClient {
    get { self[NetworkInspectorClientKey.self] }
    set { self[NetworkInspectorClientKey.self] = newValue }
  }
}

struct NetworkDependencies { }
