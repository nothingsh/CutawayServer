// swift-tools-version: 6.1
import PackageDescription

// SwiftPM reads the manifest's top-level constant by this name.
// swiftlint:disable:next prefixed_toplevel_constant
let package = Package(
    name: "CutawayServer",
    platforms: [.iOS(.v13), .macOS(.v13)],
    products: [
        .library(name: "CutawayServer", targets: ["CutawayServer"])
    ],
    traits: [
        // Off by default: without it, only builds that define DEBUG contain the server.
        .trait(name: "ReleaseEnabled", description: "Compile the server into every configuration.")
    ],
    dependencies: [],
    targets: [
        // The vendored FlatBuffers runtime. Written by scripts/vendor-flatbuffers.sh.
        .target(
            name: "CutawayFlatBuffers",
            exclude: ["LICENSE", "UPSTREAM"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(name: "CutawayWire", dependencies: ["CutawayFlatBuffers"]),
        // iOS only. Its tests run in the simulator from Demo/project.yml, not from here.
        .target(name: "CutawayServer", dependencies: ["CutawayWire"]),
        .executableTarget(name: "cutaway-probe", dependencies: ["CutawayWire"]),
        // These tests live inside the CutawayWire boundary, so they may use FlatBuffers types.
        .testTarget(
            name: "CutawayWireTests",
            dependencies: ["CutawayWire", "CutawayFlatBuffers"]
        ),
        // The probe's checks, tested on the Mac against the fixtures.
        .testTarget(name: "CutawayProbeTests", dependencies: ["cutaway-probe", "CutawayWire"])
    ],
    swiftLanguageModes: [.v6]
)
