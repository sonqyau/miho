// swift-tools-version: 6.2

import Foundation
import PackageDescription

let package = Package(
  name: "miho",
  defaultLocalization: "en",
  platforms: [
    .macOS("26.0"),
  ],
  products: [
    .executable(name: "miho", targets: ["miho"]),
    .executable(name: "ProxyDaemon", targets: ["ProxyDaemon"]),
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams", from: "6.2.0"),
    .package(url: "https://github.com/hmlongco/Factory", from: "2.5.3"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/FlineDev/ErrorKit", from: "1.2.1"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.1"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2"),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.4"),
    .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.7.2"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.6"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.9"),
  ],

  targets: [
    .executableTarget(
      name: "miho",
      dependencies: [
        .product(name: "Yams", package: "Yams"),
        .product(name: "Factory", package: "Factory"),
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "ErrorKit", package: "ErrorKit"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Perception", package: "swift-perception"),
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CombineSchedulers", package: "combine-schedulers"),
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "SwiftNavigation", package: "swift-navigation"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      path: "miho",
      exclude: [
        "Sources/Daemons/ProxyDaemon",
        "Resources/Kernel/source",
        "Resources/Kernel/toolchain",
      ],
      resources: [
        .process("Resources"),
        .process("Sources/Daemons/LaunchDaemon"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
      ],
      linkerSettings: [
        .unsafeFlags([
          "-Lmiho/Resources/Kernel/build",
          "-lmihomo"
        ], .when(platforms: [.macOS])),
      ],
    ),
    .executableTarget(
      name: "ProxyDaemon",
      dependencies: [],
      path: "miho/Sources/Daemons/ProxyDaemon",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
      ],
    ),
  ],
)
