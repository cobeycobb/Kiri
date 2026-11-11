// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Kiri", platforms: [.macOS(.v14)],
                      targets: [.executableTarget(name: "Kiri")], swiftLanguageModes: [.v5])
