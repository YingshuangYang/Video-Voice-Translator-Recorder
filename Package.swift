// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "VideoVoiceTranslatorRecorder",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "VVTRApp", targets: ["VVTRApp"]),
    .library(name: "VVTRCore", targets: ["VVTRCore"]),
    .library(name: "VVTRCapture", targets: ["VVTRCapture"]),
    .library(name: "VVTRCloud", targets: ["VVTRCloud"]),
    .library(name: "VVTRStorage", targets: ["VVTRStorage"]),
  ],
  dependencies: [
    .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.0"),
  ],
  targets: [
    .executableTarget(
      name: "VVTRApp",
      dependencies: [
        "VVTRCore",
        "VVTRCapture",
        "VVTRCloud",
        "VVTRStorage",
      ],
      path: "Sources/VVTRApp"
    ),
    .target(name: "VVTRCore", path: "Sources/VVTRCore"),
    .target(name: "VVTRCapture", dependencies: ["VVTRCore"], path: "Sources/VVTRCapture"),
    .target(name: "VVTRCloud", dependencies: ["VVTRCore"], path: "Sources/VVTRCloud"),
    .target(
      name: "VVTRStorage",
      dependencies: [
        "VVTRCore",
        .product(name: "SQLite", package: "SQLite.swift"),
      ],
      path: "Sources/VVTRStorage"
    ),
  ]
)

