// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XM6Controller",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "XM6Controller", targets: ["XM6Controller"])
    ],
    targets: [
        .executableTarget(
            name: "XM6Controller",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "XM6ControllerTests", dependencies: ["XM6Controller"])
    ]
)
