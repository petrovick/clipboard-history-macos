// swift-tools-version: 6.0

import PackageDescription

let developerDirectory = Context.environment["DEVELOPER_DIR"]
let testFrameworkSwiftSettings: [SwiftSetting]
let testFrameworkLinkerSettings: [LinkerSetting]

if let developerDirectory {
    let frameworkDirectory = "\(developerDirectory)/Library/Developer/Frameworks"
    let testingRuntimeDirectory = "\(developerDirectory)/Library/Developer/usr/lib"

    testFrameworkSwiftSettings = [
        .unsafeFlags(
            ["-F", frameworkDirectory],
            .when(platforms: [.macOS])
        )
    ]

    testFrameworkLinkerSettings = [
        .unsafeFlags(
            [
                "-F", frameworkDirectory,
                "-Xlinker", "-rpath",
                "-Xlinker", frameworkDirectory,
                "-Xlinker", "-rpath",
                "-Xlinker", testingRuntimeDirectory
            ],
            .when(platforms: [.macOS])
        )
    ]
} else {
    testFrameworkSwiftSettings = []
    testFrameworkLinkerSettings = []
}

let package = Package(
    name: "OptionVClipboard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OptionVClipboard", targets: ["OptionVClipboard"])
    ],
    targets: [
        .executableTarget(
            name: "OptionVClipboard",
            path: "Sources/OptionVClipboard"
        ),
        .testTarget(
            name: "OptionVClipboardTests",
            dependencies: ["OptionVClipboard"],
            path: "Tests/OptionVClipboardTests",
            swiftSettings: testFrameworkSwiftSettings,
            linkerSettings: testFrameworkLinkerSettings
        )
    ]
)
