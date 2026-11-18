// swift-tools-version: 5.9
import PackageDescription

// AxyomRemoteCore: everything in AXYOM Remote that is pure logic -- sync wire
// protocol, end-to-end crypto, personal-key JWTs, pairing, the fleet model
// behind the home screen, and voice-command parsing. No Apple-only
// frameworks, so it builds and tests on Linux (cheap CI). The SwiftUI app in
// ../app is a thin layer on top and is the only part that needs macOS.
let package = Package(
    name: "AxyomRemoteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AxyomRemoteCore", targets: ["AxyomRemoteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.3.0"),
    ],
    targets: [
        .target(
            name: "AxyomRemoteCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "AxyomRemoteCoreTests",
            dependencies: ["AxyomRemoteCore"]
        ),
    ]
)
