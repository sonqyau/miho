import Foundation

struct ConnectionModel { }

enum ConnectionFilter: CaseIterable {
  case all
  case http
  case https
  case socks

  var displayName: String {
    switch self {
    case .all:
      "All"

    case .http:
      "HTTP"

    case .https:
      "HTTPS"

    case .socks:
      "SOCKS"
    }
  }

  var icon: String {
    switch self {
    case .all:
      "network"

    case .http, .https:
      "globe"

    case .socks:
      "arrow.left.arrow.right.circle"
    }
  }

  func matches(_ type: String) -> Bool {
    switch self {
    case .all:
      true

    case .http:
      type.lowercased().contains("http") && !type.lowercased().contains("https")

    case .https:
      type.lowercased().contains("https")

    case .socks:
      type.lowercased().contains("socks")
    }
  }
}
