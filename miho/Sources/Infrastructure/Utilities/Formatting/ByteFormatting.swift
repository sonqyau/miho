import Foundation

struct ByteFormatting { }

extension ByteCountFormatter {
  static func string(fromByteCount byteCount: Int64, countStyle: CountStyle = .binary) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = countStyle
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: byteCount)
  }
}
