#if !canImport(UIKit) || DEBUG || ReleaseEnabled

internal import CutawayFlatBuffers

// The environment (protocol 1.2): its messages to generated types for the object API, and its
// tables read back from the raw bytes.
extension FrameCodec {
    /// The messages of the environment, as `union(for:)` writes them.
    static func environmentUnion(for message: Message) -> Cutaway_Wire_BodyUnion {
        switch message {
        case .getEnvironment:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetEnvironmentT(), type: .getenvironment)
        case .setEnvironment(let overrides):
            let object = Cutaway_Wire_SetEnvironmentT()
            object.overrides = overrides.map(traitsObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .setenvironment)
        case .environment(let environment):
            let object = Cutaway_Wire_EnvironmentT()
            // P-ENV-01: absent is the same as every trait unspecified, as the fixtures write it.
            // Unknown values are not written, so they do not count.
            object.overrides = environment.overrides.hasKnownValues ? traitsObject(for: environment.overrides) : nil
            object.current = environment.current.hasKnownValues ? traitsObject(for: environment.current) : nil
            object.overridable = environment.overridable.map(\.generated)
            return Cutaway_Wire_BodyUnion(object, type: .environment)
        default:
            preconditionFailure("not a message of the environment: \(message)")
        }
    }

    /// `unknownKinds` is not written: a value this build does not know cannot be (P-ENV-04).
    private static func traitsObject(for traits: Traits) -> Cutaway_Wire_TraitsT {
        let object = Cutaway_Wire_TraitsT()
        object.userInterfaceStyle = traits.userInterfaceStyle.generated
        object.contentSizeCategory = traits.contentSizeCategory.generated
        object.layoutDirection = traits.layoutDirection.generated
        object.horizontalSizeClass = traits.horizontalSizeClass.generated
        object.verticalSizeClass = traits.verticalSizeClass.generated
        return object
    }
}

// The environment's tables, read from the raw bytes of a verified buffer. The generated
// accessors read an enumeration value they do not know as its first case, and a server must
// refuse such a value rather than take it for `Unspecified` (P-ENV-04).
extension FrameCodec {
    /// `Traits`: its five fields are `ubyte`s, in the order of `TraitKind`.
    static func traits(of table: RawTable) -> Traits {
        var traits = Traits()
        for kind in TraitKind.allCases {
            let raw = table.byte(at: Int(kind.rawValue))
            switch kind {
            case .userInterfaceStyle:
                if let value = UserInterfaceStyle(rawValue: raw) { traits.userInterfaceStyle = value } else {
                    traits.unknownKinds.insert(kind)
                }
            case .contentSizeCategory:
                if let value = ContentSizeCategory(rawValue: raw) { traits.contentSizeCategory = value } else {
                    traits.unknownKinds.insert(kind)
                }
            case .layoutDirection:
                if let value = LayoutDirection(rawValue: raw) { traits.layoutDirection = value } else {
                    traits.unknownKinds.insert(kind)
                }
            case .horizontalSizeClass:
                if let value = SizeClass(rawValue: raw) { traits.horizontalSizeClass = value } else {
                    traits.unknownKinds.insert(kind)
                }
            case .verticalSizeClass:
                if let value = SizeClass(rawValue: raw) { traits.verticalSizeClass = value } else {
                    traits.unknownKinds.insert(kind)
                }
            }
        }
        return traits
    }

    /// `Environment`: `overrides`, `current` and `overridable`, in that order. A kind this
    /// build does not know is left out of `overridable`: it cannot be overridden from here.
    static func environment(of table: RawTable) -> Environment {
        Environment(
            overrides: table.table(at: 0).map(traits(of:)) ?? .none,
            current: table.table(at: 1).map(traits(of:)) ?? .none,
            overridable: (table.bytes(at: 2) ?? []).compactMap(TraitKind.init(rawValue:))
        )
    }
}

/// Any table of a verified buffer, read field by field: field `n` is the schema's `n`th field,
/// counting a union as two.
struct RawTable: FlatbuffersInitializable {
    private let table: Table

    init(_ buffer: ByteBuffer, o position: Int32) {
        table = Table(bb: buffer, position: position)
    }

    /// The vtable offset of field `index`.
    private static func slot(_ index: Int) -> Int32 {
        Int32(4 + 2 * index)
    }

    /// A `ubyte` field; 0 when absent.
    func byte(at index: Int) -> UInt8 {
        let offset = table.offset(Self.slot(index))
        return offset == 0 ? 0 : table.readBuffer(of: UInt8.self, at: offset)
    }

    /// A table field; `nil` when absent.
    func table(at index: Int) -> Self? {
        let offset = table.offset(Self.slot(index))
        return offset == 0 ? nil : Self(table.bb, o: table.indirect(offset &+ table.position))
    }

    /// A vector of `ubyte`s; `nil` when absent.
    func bytes(at index: Int) -> [UInt8]? {
        table.getVector(at: Self.slot(index))
    }
}
#endif
