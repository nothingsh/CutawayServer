// Compiled in every configuration; see CutawayServer+Description.swift.
#if canImport(UIKit)
import UIKit

// The functions that make an attribute, one for each kind of value. Their options are
// described on `CutawayServer.Attribute`.

extension CutawayServer.Attribute {
    private static func make<T>(
        _ name: String,
        _ value: Value,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (T?) throws -> Void)?,
        unwrap: @escaping @MainActor (Value) throws -> T?
    ) -> Self {
        var write: (@MainActor (Value?) throws -> Void)?
        if let set {
            write = { value in
                guard let value else { return try set(nil) }
                try set(unwrap(value))
            }
        }
        return Self(
            name: name,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            value: value,
            write: write
        )
    }

    /// An attribute whose value is a `Scalar`.
    private static func make<Wrapped: Scalar>(
        _ name: String,
        _ value: Wrapped?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (Wrapped?) throws -> Void)?
    ) -> Self {
        make(
            name,
            Wrapped.wrap(value),
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set,
            unwrap: { try Wrapped.unwrap($0) }
        )
    }

    /// A flag.
    public static func bool(
        _ name: String,
        _ value: Bool?,
        title: String? = nil,
        section: Section = .general,
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (Bool?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A whole number.
    public static func int(
        _ name: String,
        _ value: Int?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (Int?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A number; one that is not finite is shown as 0.
    public static func double(
        _ name: String,
        _ value: Double?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (Double?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// Text.
    public static func string(
        _ name: String,
        _ value: String?,
        title: String? = nil,
        section: Section = .general,
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (String?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A color. A dynamic color is shown as it resolves for the object, and in light and
    /// dark.
    public static func color(
        _ name: String,
        _ value: UIColor?,
        title: String? = nil,
        section: Section = .general,
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (UIColor?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A point.
    public static func point(
        _ name: String,
        _ value: CGPoint?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (CGPoint?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A size.
    public static func size(
        _ name: String,
        _ value: CGSize?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (CGSize?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A rectangle.
    public static func rect(
        _ name: String,
        _ value: CGRect?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (CGRect?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// Edge insets.
    public static func insets(
        _ name: String,
        _ value: UIEdgeInsets?,
        title: String? = nil,
        section: Section = .general,
        unit: Unit = .none,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (UIEdgeInsets?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            unit: unit,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// A 3D transform. A transform has no unit.
    public static func transform(
        _ name: String,
        _ value: CATransform3D?,
        title: String? = nil,
        section: Section = .general,
        limits: [Limit] = [],
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (CATransform3D?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            value,
            title: title,
            section: section,
            limits: limits,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        )
    }

    /// One of the cases of an enumeration with integer raw values, each shown by its name.
    public static func enumeration<Case: CaseIterable & RawRepresentable>(
        _ name: String,
        _ value: Case?,
        title: String? = nil,
        section: Section = .general,
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (Case?) throws -> Void)? = nil
    ) -> Self where Case.RawValue: BinaryInteger {
        let cases = Case.allCases.map { (name: String(describing: $0), value: Int64(clamping: $0.rawValue)) }
        return make(
            name,
            .enumeration(value.map { Int64(clamping: $0.rawValue) }, cases: cases),
            title: title,
            section: section,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        ) { stored -> Case? in
            guard case .enumeration(let raw, _) = stored else { throw WrongKind() }
            guard let raw else { return nil }
            // The first case with the raw value; Cutaway only sends raw values it listed.
            guard let found = Case.allCases.first(where: { Int64(clamping: $0.rawValue) == raw }) else {
                throw WrongKind()
            }
            return found
        }
    }

    /// One of a list of cases, given by name and raw value, for a value that is no Swift
    /// enumeration.
    public static func enumeration(
        _ name: String,
        _ value: Int?,
        cases: [(name: String, value: Int)],
        title: String? = nil,
        section: Section = .general,
        cluster: Cluster? = nil,
        inactiveBecauseOf: String? = nil,
        acceptsNil: Bool = false,
        set: (@MainActor (Int?) throws -> Void)? = nil
    ) -> Self {
        make(
            name,
            .enumeration(value.map(Int64.init), cases: cases.map { ($0.name, Int64($0.value)) }),
            title: title,
            section: section,
            cluster: cluster,
            inactiveBecauseOf: inactiveBecauseOf,
            acceptsNil: acceptsNil,
            set: set
        ) { stored in
            guard case .enumeration(let raw, _) = stored else { throw WrongKind() }
            return raw.map { Int(clamping: $0) }
        }
    }

    /// The objects a property holds, in order; a view or a view controller can be selected
    /// from it. Always read-only.
    public static func references(
        _ name: String,
        _ objects: [AnyObject]?,
        title: String? = nil,
        section: Section = .general
    ) -> Self {
        Self(
            name: name,
            title: title,
            section: section,
            unit: .none,
            limits: [],
            cluster: nil,
            inactiveBecauseOf: nil,
            acceptsNil: false,
            value: .references(objects),
            write: nil
        )
    }
}

// MARK: - Scalars

extension CutawayServer.Attribute {
    /// A Swift type an attribute's value can be, and the case of `Value` that holds it. Nested,
    /// as everything of the extension interface is, so that a build without the server defines
    /// nothing outside `CutawayServer`.
    protocol Scalar {
        /// The value, or nil, in its case.
        static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value
        /// The value `wrap` held; throws `WrongKind` for a value of another case.
        static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self?
    }
}

extension Bool: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .bool(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .bool(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension Int: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .int(value.map(Int64.init)) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .int(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value.map { Int(clamping: $0) }
    }
}

extension Double: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .double(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .double(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension String: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .string(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .string(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension UIColor: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: UIColor?) -> CutawayServer.Attribute.Value { .color(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .color(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        // `Self` is UIColor itself: the factory takes no subclass.
        return value.flatMap { $0 as? Self }
    }
}

extension CGPoint: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .point(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .point(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension CGSize: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .size(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .size(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension CGRect: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .rect(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .rect(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension UIEdgeInsets: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .insets(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .insets(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}

extension CATransform3D: CutawayServer.Attribute.Scalar {
    static func wrap(_ value: Self?) -> CutawayServer.Attribute.Value { .transform(value) }

    static func unwrap(_ value: CutawayServer.Attribute.Value) throws -> Self? {
        guard case .transform(let value) = value else { throw CutawayServer.Attribute.WrongKind() }
        return value
    }
}
#endif
