import Foundation
import OSLog

@MainActor
final class PortValidation {
  static let shared = PortValidation()

  private let logger = MihoLog.shared.logger(for: .network)

  private init() { }

  func isPortAvailable(_ port: Int) -> Bool {
    guard port > 0, port < 65536 else {
      return false
    }
    return checkIPv4Port(port) && checkIPv6Port(port)
  }

  func isLocalhostPortAvailable(_ port: Int) -> Bool {
    guard port > 0, port < 65536 else {
      return false
    }
    return checkIPv4Port(port, address: "127.0.0.1")
  }

  func findAvailablePort(startingFrom startPort: Int = 7890) -> Int? {
    for offset in 0..<65536 {
      let port = startPort + offset
      if isPortAvailable(port) {
        return port
      }
    }
    return nil
  }

  func getUsedPorts() -> [Int] {
    var ports: Set<Int> = []

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
    proc.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
    proc.environment = ["PATH": "/usr/bin:/bin"]

    let pipe = Pipe()
    proc.standardOutput = pipe

    do {
      try proc.run()
      proc.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: data, encoding: .utf8) else {
        return []
      }

      for line in output.split(separator: "\n") {
        let comps = line.split(separator: " ").map(String.init)
        if comps.count >= 9,
           let idx = comps[8].lastIndex(of: ":"),
           let port = Int(comps[8][comps[8].index(after: idx)...])
        {
          ports.insert(port)
        }
      }
    } catch {
      logger.debug("Failed to get used ports: \(error.localizedDescription)")
    }

    return ports.sorted()
  }

  func isPortInUse(_ port: Int) -> Bool {
    !isPortAvailable(port)
  }

  private func checkIPv4Port(_ port: Int, address: String = "0.0.0.0") -> Bool {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian

    if address == "0.0.0.0" {
      addr.sin_addr.s_addr = INADDR_ANY
    } else {
      inet_pton(AF_INET, address, &addr.sin_addr)
    }

    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else {
      return false
    }
    defer { close(sock) }

    var reuseAddr: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

    let result = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPtr in
        bind(sock, reboundPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }

    return result == 0
  }

  private func checkIPv6Port(_ port: Int, address: String = "::") -> Bool {
    var addr = sockaddr_in6()
    addr.sin6_family = sa_family_t(AF_INET6)
    addr.sin6_port = in_port_t(port).bigEndian

    if address == "::" {
      addr.sin6_addr = in6addr_any
    } else {
      inet_pton(AF_INET6, address, &addr.sin6_addr)
    }

    let sock = socket(AF_INET6, SOCK_STREAM, 0)
    guard sock >= 0 else {
      logger.debug("Failed to create IPv6 socket for port \(port)")
      return false
    }
    defer { close(sock) }

    var reuseAddr: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

    var ipv6Only: Int32 = 0
    setsockopt(sock, IPPROTO_IPV6, IPV6_V6ONLY, &ipv6Only, socklen_t(MemoryLayout<Int32>.size))

    let result = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPtr in
        bind(sock, reboundPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
      }
    }

    return result == 0
  }
}

extension NetworkDomain {
  func isPortAvailable(_ port: Int) -> Bool {
    PortValidation.shared.isPortAvailable(port)
  }

  func findAvailablePort(startingFrom startPort: Int = 7890) -> Int? {
    PortValidation.shared.findAvailablePort(startingFrom: startPort)
  }

  func getUsedPorts() -> [Int] {
    PortValidation.shared.getUsedPorts()
  }
}
