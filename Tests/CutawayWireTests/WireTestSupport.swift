import CutawayWire
import Foundation

/// A small deterministic generator, so that "random" inputs are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func bytes(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &self) })
    }
}

enum WireTestSupport {
    /// Overwrites the `body_type` byte of an encoded frame that has a body.
    /// It walks the buffer by hand: root offset, vtable, then the second field's offset.
    static func settingBodyType(_ value: UInt8, in payload: Data) -> Data {
        var bytes = [UInt8](payload)
        func int32(at index: Int) -> Int {
            Int(Int32(bitPattern: UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
                    | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24))
        }
        let table = int32(at: 0)
        let vtable = table - int32(at: table)
        let fieldOffset = Int(bytes[vtable + 6]) | Int(bytes[vtable + 7]) << 8
        precondition(fieldOffset != 0, "the frame has no body_type field")
        bytes[table + fieldOffset] = value
        return Data(bytes)
    }

    /// The `.bin` files of one direction of a fixture scenario, in frame order.
    static func fixtureFrames(scenario: String, direction: String) throws -> [Data] {
        let directory = RepositoryFiles.root
            .appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(scenario)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".bin") && $0.contains("-\(direction)-") }
            .sorted()
            .map { try Data(contentsOf: directory.appendingPathComponent($0)) }
    }

    static let scenarios = [
        "handshake",
        "handshake-version-mismatch",
        "busy",
        "app-icon",
        "hierarchy",
        "layer-details",
        "layer-details-edge",
        "layer-details-cancelled",
        "app-not-active",
        "layer-details-failed",
        "set-attribute",
        "set-attribute-rejected",
        "subtree",
        "layout-constraints",
        "environment",
        "environment-rejected"
    ]
}

extension WireTestSupport {
    /// The name of a message's member of the `Body` union. The switch has no default, so a new
    /// member does not compile until it is named here and in `messageKinds`.
    static func kind(of message: Message) -> String {
        switch message {
        case .hello: return "Hello"
        case .getAppIcon: return "GetAppIcon"
        case .appIcon: return "AppIcon"
        case .getHierarchy: return "GetHierarchy"
        case .hierarchy: return "Hierarchy"
        case .getLayerDetails: return "GetLayerDetails"
        case .layerDetailsChunk: return "LayerDetailsChunk"
        case .streamEnd: return "StreamEnd"
        case .cancel: return "Cancel"
        case .error: return "Error"
        case .appStateChanged: return "AppStateChanged"
        case .setAttribute: return "SetAttribute"
        case .setAttributeResult: return "SetAttributeResult"
        case .getSubtree: return "GetSubtree"
        case .getEnvironment: return "GetEnvironment"
        case .setEnvironment: return "SetEnvironment"
        case .environment: return "Environment"
        }
    }

    static let messageKinds: Set<String> = [
        "Hello",
        "GetAppIcon",
        "AppIcon",
        "GetHierarchy",
        "Hierarchy",
        "GetLayerDetails",
        "LayerDetailsChunk",
        "StreamEnd",
        "Cancel",
        "Error",
        "AppStateChanged",
        "SetAttribute",
        "SetAttributeResult",
        "GetSubtree",
        "GetEnvironment",
        "SetEnvironment",
        "Environment"
    ]

    /// One message of every kind, each with as many of its fields filled in as the schema has.
    static let messageSamples: [Message] = {
        let image = WireImage(
            pixelWidth: 4,
            pixelHeight: 2,
            bytesPerRow: 16,
            scale: 2,
            data: Data((0..<40).map { UInt8($0) })
        )
        let transform = WireTransform(
            m11: 1,
            m12: 2,
            m13: 3,
            m14: 4,
            m21: 5,
            m22: 6,
            m23: 7,
            m24: 8,
            m31: 9,
            m32: 10,
            m33: 11,
            m34: 12,
            m41: 13,
            m42: 14,
            m43: 15,
            m44: 16
        )
        let values: [AttributeValue] = [
            .bool(true),
            .int(.min),
            .double(-0.5),
            .string("text ✓"),
            .color(WireColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)),
            .color(
                WireColor(red: 0, green: 0.47843137, blue: 1, alpha: 1),
                systemName: "systemBlue",
                light: WireColor(red: 0, green: 0.47843137, blue: 1, alpha: 1),
                dark: WireColor(red: 0.039215688, green: 0.5176471, blue: 1, alpha: 1)
            ),
            .point(WirePoint(x: 1, y: -1)),
            .size(WireSize(width: 3, height: 4)),
            .rect(WireRect(x: 1, y: 2, width: 3, height: 4)),
            .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4)),
            .transform(transform),
            .enumeration(value: 2, cases: ["a", "b", "c"], caseName: "c", caseValues: [0, 1, 2]),
            .layerReference([
                ObjectReference(
                    layerID: 2,
                    className: "Demo.HomeViewController",
                    displayClassName: "HomeViewController"
                ),
                ObjectReference(layerID: 0, className: "NSObject", displayClassName: "NSObject")
            ]),
            .layerReference([])
        ]
        let attributes = values.enumerated().map { index, value in
            Attribute(
                id: "sample.value\(index)",
                title: "Value \(index)",
                value: value,
                editable: index % 2 == 0,
                acceptsNil: index % 3 == 0,
                valueKind: value.kind
            )
        } + [Attribute(id: "sample.nil", title: "Nil", value: nil, editable: true, acceptsNil: true, valueKind: .color)]
        let groups = [
            AttributeGroup(id: "sample", title: "Sample", attributes: attributes),
            AttributeGroup(id: "empty", title: "Empty", attributes: [])
        ]
        let constraints = [
            LayoutConstraint(
                id: 30,
                className: "NSLayoutConstraint",
                identifier: "sample",
                firstItem: LayoutItem(kind: .view, layerID: 3, className: "UILabel", displayClassName: "UILabel"),
                firstAttribute: .leading,
                relation: .greaterThanOrEqual,
                secondItem: LayoutItem(
                    kind: .layoutGuide,
                    layerID: 2,
                    guideID: 31,
                    className: "UILayoutGuide",
                    displayClassName: "UILayoutGuide",
                    identifier: "UIViewSafeAreaLayoutGuide",
                    guideFrame: WireRect(x: 0, y: 47, width: 393, height: 771)
                ),
                secondAttribute: .leadingMargin,
                multiplier: 1.5,
                constant: -8,
                priority: 750,
                status: .satisfied
            ),
            LayoutConstraint(
                id: 32,
                className: "NSAutoresizingMaskLayoutConstraint",
                firstItem: LayoutItem(kind: .view, layerID: 3),
                firstAttribute: .minX,
                relation: .equal,
                multiplier: 1,
                constant: 100,
                priority: 1000,
                status: .unknown
            )
        ]
        let node = LayerNode(
            id: 3,
            parentID: 2,
            className: "_TtC4Demo5Label",
            displayClassName: "Demo.Label",
            viewClassName: "UILabel",
            viewDisplayClassName: "UILabel",
            bounds: WireRect(x: 0, y: 0, width: 100, height: 20),
            position: WirePoint(x: 50, y: 10),
            anchorPoint: WirePoint(x: 0, y: 1),
            transform: transform,
            zPosition: 2,
            isHidden: true,
            opacity: 0.5,
            masksToBounds: true,
            viewControllerClassName: "ViewController",
            viewControllerDisplayClassName: "Demo.ViewController",
            memberReferences: [
                MemberReference(
                    ownerClassName: "ViewController",
                    ownerDisplayClassName: "Demo.ViewController",
                    name: "label"
                )
            ]
        )
        let root = LayerNode(
            id: 2,
            parentID: 0,
            className: "UIWindowLayer",
            displayClassName: "UIWindowLayer",
            bounds: WireRect(x: 0, y: 0, width: 393, height: 852),
            position: WirePoint(x: 196.5, y: 426)
        )
        let app = AppInfo(
            name: "Demo",
            bundleID: "dev.cutaway.demo",
            appVersion: "1.0",
            deviceName: "iPhone",
            deviceKind: .pad,
            isSimulator: false,
            osName: "iPadOS",
            osVersion: "27.0",
            screenSize: WireSize(width: 1024, height: 1366),
            screenScale: 2,
            serverVersion: "0.5.0"
        )
        return [
            .hello(Hello(version: .current, role: .client, client: ClientInfo(name: "Cutaway", version: "1.0"))),
            .hello(Hello(version: .current, role: .server, app: app)),
            .getAppIcon,
            .appIcon(AppIcon(image: image)),
            .getHierarchy,
            .hierarchy(Hierarchy(nodes: [root, node], keyWindowID: 2)),
            .getLayerDetails(
                GetLayerDetails(
                    requests: [
                        LayerDetailRequest(
                            layerID: 3,
                            wantSolo: true,
                            wantGroup: true,
                            wantAttributes: true,
                            wantConstraints: true
                        ),
                        LayerDetailRequest(layerID: 0, wantSolo: false, wantGroup: false, wantAttributes: false)
                    ],
                    maxTextureDimension: 2048
                )
            ),
            .layerDetailsChunk(
                LayerDetailsChunk(
                    sequence: 7,
                    details: [
                        LayerDetail(
                            layerID: 3,
                            status: .ok,
                            solo: image,
                            group: image,
                            attributeGroups: groups,
                            constraints: constraints
                        ),
                        LayerDetail(layerID: 4, status: .captureFailed, attributeGroups: groups),
                        LayerDetail(layerID: 5, status: .layerNotFound)
                    ]
                )
            ),
            .streamEnd(
                StreamEnd(status: .failed, chunkCount: 2, error: WireError(code: .appNotActive, message: "inactive"))
            ),
            .cancel(targetRequestID: 9),
            .error(WireError(code: .invalidAttributeValue, message: "layer.opacity takes finite numbers only")),
            .appStateChanged(.background),
            .setAttribute(
                SetAttribute(layerID: 3, attributeID: "sample.value9", value: .transform(transform))
            ),
            .setAttributeResult(SetAttributeResult(layerID: 3, attributeGroups: groups)),
            .getSubtree(rootID: 3),
            .getEnvironment,
            .setEnvironment(
                overrides: Traits(userInterfaceStyle: .dark, layoutDirection: .rightToLeft, verticalSizeClass: .compact)
            ),
            .setEnvironment(overrides: nil),
            .environment(
                Environment(
                    overrides: Traits(contentSizeCategory: .accessibilityExtraExtraExtraLarge),
                    current: Traits(
                        userInterfaceStyle: .light,
                        contentSizeCategory: .accessibilityExtraExtraExtraLarge,
                        layoutDirection: .leftToRight,
                        horizontalSizeClass: .compact,
                        verticalSizeClass: .regular
                    ),
                    overridable: TraitKind.allCases
                )
            )
        ]
    }()

    /// Every fixture frame of both directions.
    static func allFixtureFrames() throws -> [Data] {
        var frames: [Data] = []
        for scenario in scenarios {
            for direction in ["c2s", "s2c"] {
                frames += try fixtureFrames(scenario: scenario, direction: direction)
            }
        }
        return frames
    }
}

/// Damages encoded frames in five ways (`Kind`), chosen in turn by a seeded generator.
struct FrameMutator {
    enum Kind: CaseIterable {
        case changeBytes, changeWord, truncate, insert, append
    }

    /// Where offsets, vector lengths and union types live, and so where a verifier would slip.
    static let extremeWords: [UInt32] = [
        0,
        1,
        4,
        8,
        0x7FFF_FFFF,
        0x8000_0000,
        0xFFFF_FFFE,
        0xFFFF_FFFF
    ]

    private var generator: SeededGenerator
    private let seeds: [Data]

    init(seed: UInt64, seeds: [Data]) {
        generator = SeededGenerator(seed: seed)
        self.seeds = seeds
    }

    /// A damaged copy of one of the seeds, and how it was damaged.
    mutating func next() -> (kind: Kind, bytes: Data) {
        var bytes = [UInt8](seeds.randomElement(using: &generator)!)
        let kind = Kind.allCases.randomElement(using: &generator)!
        switch kind {
        case .changeBytes:
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                bytes[Int.random(in: 0..<bytes.count, using: &generator)] = UInt8.random(
                    in: .min ... .max,
                    using: &generator
                )
            }
        case .changeWord:
            let start = Int.random(in: 0..<max(1, bytes.count / 4), using: &generator) * 4
            let word = Self.extremeWords.randomElement(using: &generator)!
            for byte in 0..<4 where start + byte < bytes.count {
                bytes[start + byte] = UInt8(truncatingIfNeeded: word >> UInt32(8 * byte))
            }
        case .truncate:
            bytes = Array(bytes.prefix(Int.random(in: 0..<bytes.count, using: &generator)))
        case .insert:
            let offset = Int.random(in: 0...bytes.count, using: &generator)
            let count = Int.random(in: 1...16, using: &generator)
            bytes.insert(
                contentsOf: (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) },
                at: offset
            )
        case .append:
            bytes += [UInt8](seeds.randomElement(using: &generator)!)
        }
        return (kind, Data(bytes))
    }
}
