// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DiskLedger",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "DiskLedger", targets: ["DiskLedger"]),
        .executable(name: "ledger-scan", targets: ["ledger-scan"]),
    ],
    targets: [
        .target(name: "LedgerCore"),
        .executableTarget(name: "DiskLedger", dependencies: ["LedgerCore"]),
        // 画面を通さずに走査だけを動かし、速さと結果を確かめるための道具。
        .executableTarget(name: "ledger-scan", dependencies: ["LedgerCore"]),
        .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"]),
    ]
)
