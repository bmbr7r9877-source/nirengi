// swift-tools-version: 6.0
import PackageDescription

// Çekirdek — UI'dan bağımsız saf analiz çekirdeği.
// Motorlar, modeller ve karar mantığı burada yaşar; iOS uygulaması bunu sarar.
let package = Package(
    name: "Cekirdek",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "Cekirdek", targets: ["Cekirdek"]),
        .executable(name: "demo", targets: ["demo"]),
        .executable(name: "ogrenme", targets: ["ogrenme"]),
    ],
    targets: [
        .target(name: "Cekirdek"),
        .executableTarget(name: "demo", dependencies: ["Cekirdek"]),
        .executableTarget(name: "ogrenme", dependencies: ["Cekirdek"]),
        .testTarget(name: "CekirdekTests", dependencies: ["Cekirdek"]),
    ]
)
