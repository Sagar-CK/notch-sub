// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SubTracker",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "SubTracker", targets: ["SubTrackerApp"])],
  targets: [
    .target(name: "SubTrackerCore"),
    .executableTarget(
      name: "SubTrackerApp", dependencies: ["SubTrackerCore"], resources: [.process("Resources")]),
    .executableTarget(
      name: "SubTrackerChecks", dependencies: ["SubTrackerCore"], path: "Tests/SubTrackerCoreTests"),
  ],
  swiftLanguageModes: [.v5]
)
