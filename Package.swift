// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NotchSub",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "NotchSub", targets: ["NotchSubApp"])],
  targets: [
    .target(name: "NotchSubCore"),
    .executableTarget(
      name: "NotchSubApp", dependencies: ["NotchSubCore"], resources: [.process("Resources")]),
    .executableTarget(
      name: "NotchSubChecks", dependencies: ["NotchSubCore"], path: "Tests/NotchSubCoreTests"),
  ],
  swiftLanguageModes: [.v5]
)
