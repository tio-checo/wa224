// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WaveAce",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WaveAce", targets: ["WaveAce"]),
               .executable(name: "WaveAceCheck", targets: ["WaveAceCheck"])],
    targets: [.target(name: "ScopeCore"),
              .executableTarget(name: "WaveAce", dependencies: ["ScopeCore"]),
              .executableTarget(name: "WaveAceCheck", dependencies: ["ScopeCore"]),
              .testTarget(name: "ScopeCoreTests", dependencies: ["ScopeCore"])])
