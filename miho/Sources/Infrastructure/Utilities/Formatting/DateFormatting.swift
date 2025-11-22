import Foundation

enum DateFormatting {
  static func formatInternal(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
  }

  static func formatExternal(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    return formatter.string(from: date)
  }

  static func formatUserFriendly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .current
    return formatter.string(from: date)
  }

  static func formatUserFriendlyDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .current
    return formatter.string(from: date)
  }

  static func formatUserFriendlyTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .current
    return formatter.string(from: date)
  }

  static func parseISO8601(_ string: String) -> Date? {
    let api = ISO8601DateFormatter()
    api.formatOptions = [.withInternetDateTime]
    api.timeZone = TimeZone(identifier: "UTC")

    if let date = api.date(from: string) {
      return date
    }

    let detailed = ISO8601DateFormatter()
    detailed.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    detailed.timeZone = TimeZone(identifier: "UTC")
    return detailed.date(from: string)
  }

  static func parseRFC5322(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    return formatter.date(from: string)
  }
}

extension Date {
  var internalFormat: String { DateFormatting.formatInternal(self) }
  var externalFormat: String { DateFormatting.formatExternal(self) }
  var userFriendlyFormat: String { DateFormatting.formatUserFriendly(self) }
}
