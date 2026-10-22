import CutawayFlatBuffers
import Foundation
import XCTest

@testable import CutawayWire

/// The environment's messages (protocol 1.2; PROTOCOL.md, P-ENV-01 to 04) decode into the
/// project's value types and encode back.
final class EnvironmentCodecTests: XCTestCase {
    private func fixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(RepositoryFiles.fixture(path))
    }

    private let phone = Traits(
        userInterfaceStyle: .light,
        contentSizeCategory: .large,
        layoutDirection: .leftToRight,
        horizontalSizeClass: .compact,
        verticalSizeClass: .regular
    )

    func test_S_ENV_01_decodesTheEnvironmentFixtures() throws {
        let all = TraitKind.allCases
        let threeOverrides = Traits(
            userInterfaceStyle: .dark,
            contentSizeCategory: .accessibilityLarge,
            layoutDirection: .rightToLeft
        )
        var overridden = phone
        overridden.userInterfaceStyle = .dark
        overridden.contentSizeCategory = .accessibilityLarge
        overridden.layoutDirection = .rightToLeft
        var dark = phone
        dark.userInterfaceStyle = .dark
        let expected: [(String, Frame)] = [
            ("environment/01-c2s-get-environment.bin", Frame(requestID: 1, body: .getEnvironment)),
            (
                "environment/02-s2c-environment.bin",
                Frame(requestID: 1, body: .environment(Environment(overrides: .none, current: phone, overridable: all)))
            ),
            (
                "environment/03-c2s-set-environment.bin",
                Frame(requestID: 2, body: .setEnvironment(overrides: threeOverrides))
            ),
            (
                "environment/04-s2c-environment.bin",
                Frame(
                    requestID: 2,
                    body: .environment(Environment(overrides: threeOverrides, current: overridden, overridable: all))
                )
            ),
            (
                "environment/05-c2s-set-environment.bin",
                Frame(requestID: 3, body: .setEnvironment(overrides: Traits(userInterfaceStyle: .dark)))
            ),
            (
                "environment/06-s2c-environment.bin",
                Frame(
                    requestID: 3,
                    body: .environment(
                        Environment(overrides: Traits(userInterfaceStyle: .dark), current: dark, overridable: all)
                    )
                )
            ),
            // No `overrides`: every override goes (P-ENV-02).
            ("environment/07-c2s-set-environment.bin", Frame(requestID: 4, body: .setEnvironment(overrides: nil))),
            (
                "environment/08-s2c-environment.bin",
                Frame(requestID: 4, body: .environment(Environment(overrides: .none, current: phone, overridable: all)))
            )
        ]
        for (path, frame) in expected {
            XCTAssertEqual(try fixture(path), frame, path)
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame, path)
        }
    }

    func test_S_ENV_04_decodesTheRejectedEnvironmentFixtures() throws {
        XCTAssertEqual(
            try fixture("environment-rejected/02-s2c-environment.bin"),
            Frame(
                requestID: 1,
                body: .environment(Environment(overrides: .none, current: phone, overridable: [.userInterfaceStyle]))
            )
        )
        XCTAssertEqual(
            try fixture("environment-rejected/03-c2s-set-environment.bin"),
            Frame(
                requestID: 2,
                body: .setEnvironment(overrides: Traits(userInterfaceStyle: .dark, layoutDirection: .rightToLeft))
            )
        )
        XCTAssertEqual(
            try fixture("environment-rejected/04-s2c-error.bin"),
            Frame(
                requestID: 2,
                body: .error(
                    WireError(code: .notSupported, message: "the layout direction cannot be overridden on this device")
                )
            )
        )
    }

    /// P-ENV-04: a value this build does not know stays known as unknown, not `Unspecified`.
    func test_S_ENV_04_unknownTraitValuesAreKept() throws {
        var builder = FlatBufferBuilder(initialSize: 64)
        let traitsStart = builder.startTable(with: 5)
        builder.add(element: UInt8(2), def: 0, at: 4)   // user_interface_style: Dark
        builder.add(element: UInt8(99), def: 0, at: 8)  // layout_direction: unknown
        builder.add(element: UInt8(7), def: 0, at: 12)  // vertical_size_class: unknown
        let traits = Offset(offset: builder.endTable(at: traitsStart))
        let setStart = builder.startTable(with: 1)
        builder.add(offset: traits, at: 4)
        let set = Offset(offset: builder.endTable(at: setStart))
        let frame = Cutaway_Wire_Frame.createFrame(
            &builder,
            requestId: 7,
            bodyType: .setenvironment,
            bodyOffset: set
        )
        Cutaway_Wire_Frame.finish(&builder, end: frame)

        let decoded = try FrameCodec.decode(Data(builder.sizedByteArray))
        guard case .setEnvironment(let overrides?)? = decoded.body else {
            return XCTFail("not a SetEnvironment with overrides: \(decoded)")
        }
        XCTAssertEqual(overrides.userInterfaceStyle, .dark)
        XCTAssertEqual(overrides.layoutDirection, .unspecified)
        XCTAssertEqual(overrides.unknownKinds, [.layoutDirection, .verticalSizeClass])
        XCTAssertEqual(overrides.specifiedKinds, [.userInterfaceStyle, .layoutDirection, .verticalSizeClass])
    }

    /// The raw values are the protocol's, so that the two mappings of `EnumMapping.swift`
    /// and the raw reading meet.
    func test_S_ENV_01_rawValuesAreTheProtocols() {
        XCTAssertEqual(UserInterfaceStyle.allCases.map(\.generated), [.unspecified, .light, .dark])
        XCTAssertEqual(LayoutDirection.allCases.map(\.generated), [.unspecified, .lefttoright, .righttoleft])
        XCTAssertEqual(SizeClass.allCases.map(\.generated), [.unspecified, .compact, .regular])
        XCTAssertEqual(ContentSizeCategory.allCases.map(\.generated.rawValue), Array(0...12))
        XCTAssertEqual(
            ContentSizeCategory.accessibilityExtraExtraExtraLarge.generated,
            .accessibilityextraextraextralarge
        )
        XCTAssertEqual(
            TraitKind.allCases.map(\.generated),
            [.userinterfacestyle, .contentsizecategory, .layoutdirection, .horizontalsizeclass, .verticalsizeclass]
        )
        XCTAssertEqual(ErrorCode.notSupported.generated, .notsupported)
        XCTAssertEqual(ErrorCode(.notsupported), .notSupported)
    }
}
