// Compiled in every configuration; see CutawayServer+Description.swift.
#if canImport(UIKit)
import UIKit

extension CutawayServer {
    /// A group of attributes the host app adds to a view, a layer or a virtual node.
    public struct AttributeGroup {
        let id: String
        let title: String?
        let typeName: String?
        let attributes: [Attribute]

        /// - Parameters:
        ///   - id: Stable: Cutaway sends it as `app.` followed by this. Each attribute's ID is the
        ///     group's, a dot and the attribute's name.
        ///   - title: For display; made from `id` when absent.
        ///   - typeName: The type that declares what the group shows. When absent it is the
        ///     registered class, or for a virtual node the node's type.
        public init(_ id: String, title: String? = nil, typeName: String? = nil, _ attributes: [Attribute]) {
            self.id = id
            self.title = title
            self.typeName = typeName
            self.attributes = attributes
        }

        /// The same, with the type that declares what the group shows.
        public init(_ id: String, title: String? = nil, type: Any.Type, _ attributes: [Attribute]) {
            self.init(id, title: title, typeName: String(reflecting: type), attributes)
        }
    }

    /// Where an inspector shows an attribute.
    public enum Section: Sendable {
        case general
        /// What identifies the object.
        case identity
        /// Its geometry.
        case layout
        /// What is particular to its type.
        case content
        /// How it looks.
        case appearance
        /// How it responds to interaction.
        case behavior
        /// What it gives assistive technologies.
        case accessibility
    }

    /// How to read the numbers of an attribute.
    public enum Unit: Sendable {
        case none
        /// Lengths in points.
        case points
        /// A proportion where 1 is the whole.
        case fraction
    }

    /// The values a number may be set to. One limit applies to every component of a value;
    /// otherwise give one per component, in the order of its fields (x, y; width, height;
    /// top, left, bottom, right; m11 to m44), with `free` for a component without one.
    public struct Limit: Sendable {
        let minimum: Double?
        let minimumIsExclusive: Bool
        let maximum: Double?
        let maximumIsExclusive: Bool

        public static let free = Self(minimum: nil, minimumIsExclusive: false, maximum: nil, maximumIsExclusive: false)

        public static func atLeast(_ minimum: Double) -> Self {
            Self(minimum: minimum, minimumIsExclusive: false, maximum: nil, maximumIsExclusive: false)
        }

        public static func greaterThan(_ minimum: Double) -> Self {
            Self(minimum: minimum, minimumIsExclusive: true, maximum: nil, maximumIsExclusive: false)
        }

        public static func atMost(_ maximum: Double) -> Self {
            Self(minimum: nil, minimumIsExclusive: false, maximum: maximum, maximumIsExclusive: false)
        }

        public static func lessThan(_ maximum: Double) -> Self {
            Self(minimum: nil, minimumIsExclusive: false, maximum: maximum, maximumIsExclusive: true)
        }

        public static func between(_ minimum: Double, _ maximum: Double) -> Self {
            Self(minimum: minimum, minimumIsExclusive: false, maximum: maximum, maximumIsExclusive: false)
        }
    }

    /// A compound row an inspector may show the attribute in, and its part in it. Both names
    /// come from Cutaway's protocol; one it does not have is left out.
    public struct Cluster: Sendable {
        let name: String
        let slot: String

        public init(_ name: String, slot: String) {
            self.name = name
            self.slot = slot
        }
    }

    /// One attribute: its value now, and how to change it. Make one with the function for its
    /// kind of value.
    ///
    /// An attribute with `set` may be edited. `set` gets a value that passed every check (its
    /// kind, its limits, nil only when `acceptsNil`), on the main thread; it throws to refuse
    /// the value, and the error's description is shown. When it fails after changing part of
    /// the app, putting the app back is up to it.
    public struct Attribute {
        /// A value of one kind; nil is a value too.
        enum Value {
            case bool(Bool?)
            case int(Int64?)
            case double(Double?)
            case string(String?)
            case color(UIColor?)
            case point(CGPoint?)
            case size(CGSize?)
            case rect(CGRect?)
            case insets(UIEdgeInsets?)
            case transform(CATransform3D?)
            /// The raw value and every case's name and raw value, in declaration order.
            case enumeration(Int64?, cases: [(name: String, value: Int64)])
            case references([AnyObject]?)
        }

        /// Thrown to `set` with a value of the wrong kind; Cutaway's checks never let one through.
        struct WrongKind: Error {}

        let name: String
        let title: String?
        let section: Section
        let unit: Unit
        let limits: [Limit]
        let cluster: Cluster?
        let inactiveBecauseOf: String?
        let acceptsNil: Bool
        let value: Value
        /// Writes a value of the same case as `value`.
        let write: (@MainActor (Value) throws -> Void)?

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
            unwrap: @escaping @MainActor (Value) -> T??
        ) -> Self {
            var write: (@MainActor (Value) throws -> Void)?
            if let set {
                write = { value in
                    guard let typed = unwrap(value) else { throw WrongKind() }
                    try set(typed)
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

        // `inactiveBecauseOf` names another attribute of the same object, as "group.name", whose
        // value now makes this one have no effect.

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
                .bool(value),
                title: title,
                section: section,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .bool(let value) = stored { return value }
                return nil
            }
        }

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
                .int(value.map(Int64.init)),
                title: title,
                section: section,
                unit: unit,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .int(let value) = stored { return value.map { Int(clamping: $0) } }
                return nil
            }
        }

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
                .double(value),
                title: title,
                section: section,
                unit: unit,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .double(let value) = stored { return value }
                return nil
            }
        }

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
                .string(value),
                title: title,
                section: section,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .string(let value) = stored { return value }
                return nil
            }
        }

        /// A dynamic color is shown as it resolves for the object, and in light and dark.
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
                .color(value),
                title: title,
                section: section,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .color(let value) = stored { return value }
                return nil
            }
        }

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
                .point(value),
                title: title,
                section: section,
                unit: unit,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .point(let value) = stored { return value }
                return nil
            }
        }

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
                .size(value),
                title: title,
                section: section,
                unit: unit,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .size(let value) = stored { return value }
                return nil
            }
        }

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
                .rect(value),
                title: title,
                section: section,
                unit: unit,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .rect(let value) = stored { return value }
                return nil
            }
        }

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
                .insets(value),
                title: title,
                section: section,
                unit: unit,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .insets(let value) = stored { return value }
                return nil
            }
        }

        /// A transform has no unit.
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
                .transform(value),
                title: title,
                section: section,
                limits: limits,
                cluster: cluster,
                inactiveBecauseOf: inactiveBecauseOf,
                acceptsNil: acceptsNil,
                set: set
            ) { stored in
                if case .transform(let value) = stored { return value }
                return nil
            }
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
            ) { stored -> Case?? in
                guard case .enumeration(let raw, _) = stored else { return nil }
                guard let raw else { return .some(nil) }
                // The first case with the raw value; Cutaway only sends raw values it listed.
                return Case.allCases.first { Int64(clamping: $0.rawValue) == raw }.map { .some($0) }
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
                if case .enumeration(let raw, _) = stored { return raw.map { Int(clamping: $0) } }
                return nil
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
}
#endif
