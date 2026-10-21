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
        ///   - attributes: The group's attributes, in the order they are shown.
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

    /// One attribute: its value now, and how to change it. Make one with the function for its
    /// kind of value.
    ///
    /// The functions take these options, as far as they apply to the kind:
    /// - `name`: Stable, unique in the group; the attribute's ID is the group's, a dot and this.
    /// - `title`: For display; made from `name` when absent.
    /// - `section`: Where an inspector shows the attribute.
    /// - `unit`: How to read its numbers; only for numbers.
    /// - `limits`: The values a number may be set to; only for numbers.
    /// - `cluster`: A compound row the attribute is part of.
    /// - `inactiveBecauseOf`: Another attribute of the same object, as "group.name", whose value
    ///   now makes this one have no effect, such as a border color while the border width is 0.
    /// - `acceptsNil`: `set` may be given nil.
    /// - `set`: Changes the value; without it the attribute is read-only.
    ///
    /// An attribute with `set` may be edited. `set` gets a value that passed every check (its
    /// kind, its limits, nil only when `acceptsNil`), on the main thread; it throws to refuse
    /// the value, and the error's description is shown. When it fails after changing part of
    /// the app, putting the app back is up to it.
    public struct Attribute {
        /// Where an inspector shows an attribute.
        public enum Section: Sendable {
            /// No particular section.
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
            /// None in particular: a count, a scale, a priority.
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

            /// Any value.
            public static let free = Self(
                minimum: nil,
                minimumIsExclusive: false,
                maximum: nil,
                maximumIsExclusive: false
            )

            /// `minimum` or more.
            public static func atLeast(_ minimum: Double) -> Self {
                Self(minimum: minimum, minimumIsExclusive: false, maximum: nil, maximumIsExclusive: false)
            }

            /// More than `minimum`.
            public static func greaterThan(_ minimum: Double) -> Self {
                Self(minimum: minimum, minimumIsExclusive: true, maximum: nil, maximumIsExclusive: false)
            }

            /// `maximum` or less.
            public static func atMost(_ maximum: Double) -> Self {
                Self(minimum: nil, minimumIsExclusive: false, maximum: maximum, maximumIsExclusive: false)
            }

            /// Less than `maximum`.
            public static func lessThan(_ maximum: Double) -> Self {
                Self(minimum: nil, minimumIsExclusive: false, maximum: maximum, maximumIsExclusive: true)
            }

            /// From `minimum` to `maximum`, both included.
            public static func between(_ minimum: Double, _ maximum: Double) -> Self {
                Self(minimum: minimum, minimumIsExclusive: false, maximum: maximum, maximumIsExclusive: false)
            }
        }

        /// A compound row an inspector may show the attribute in, and its part in it: `.font.size`,
        /// `.shadow.color`. The constants are the clusters and slots of Cutaway's protocol. The
        /// attributes of one cluster must be in the same section, and one object gives each slot
        /// once; a cluster that breaks either, or that the protocol does not have, is left out.
        public struct Cluster: Sendable {
            let name: String
            let slot: String

            /// A cluster and a slot by their names in Cutaway's protocol, for one that has no
            /// constant here.
            public init(_ name: String, slot: String) {
                self.name = name
                self.slot = slot
            }
        }

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
        /// Writes a value of the same case as `value`; `nil` writes nil.
        let write: (@MainActor (Value?) throws -> Void)?
    }
}
#endif
