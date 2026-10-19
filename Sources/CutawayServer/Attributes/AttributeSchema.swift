#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

// How the catalog is described: groups of attributes, each read from a subject and maybe
// written through an `AttributeWriter`. The groups themselves are in AttributeCatalog.swift.

extension AttributeCatalog {
    /// One attribute of one layer as it reads now, and how to change it.
    struct AttributeEdit {
        let attribute: Attribute
        /// Checks a value and returns what writes it; `nil` when the attribute reads as
        /// read-only now (P-ATTR-06).
        let prepare: ((AttributeValue?) -> Result<() -> Void, AttributeRejection>)?
    }

    /// Splits a name before each capital letter and at each dot, and capitalizes every word:
    /// `isUserInteractionEnabled` becomes "Is User Interaction Enabled", and
    /// `contentHuggingPriority.horizontal` "Content Hugging Priority Horizontal".
    nonisolated static func title(for name: String) -> String {
        var words: [String] = []
        var startsWord = true
        for character in name {
            if character == "." {
                startsWord = true
            } else if character.isUppercase || startsWord {
                words.append(String(character))
                startsWord = false
            } else {
                words[words.count - 1].append(character)
            }
        }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// One attribute of a group: how it is read, and what a client may do with it.
    struct AttributeDefinition<Subject> {
        /// The part of the ID after the group's ID and the dot.
        let name: String
        /// For a person (the convention after P-ATTR-01); `nil` makes one from `name`.
        let title: String?
        /// The member of `AttributeValue` the attribute uses (P-ATTR-06).
        let kind: AttributeValueKind
        /// May be set to nil. Whether it may read as nil is up to `read`.
        let acceptsNil: Bool
        /// Where an inspector shows it (P-ATTR-08).
        let section: AttributeSection
        /// The compound row it is part of, and its part in it (P-ATTR-12).
        let cluster: (name: String, slot: String)?
        /// How to read its numbers (P-ATTR-14).
        let unit: AttributeUnit
        /// The layer's side of a pair (P-ATTR-11): left out when the layer backs a view, whose
        /// attribute of the pair stands for it.
        let onlyWithoutView: Bool
        /// The ID of the attribute of the same layer whose current value makes this one have no
        /// effect, or `nil` (P-ATTR-13).
        let inactiveCause: ((Subject) -> String?)?
        /// The values a change may have (P-ATTR-09, 10). They are sent, and `AttributeEditing`
        /// refuses what lies outside them (P-SET-07): one list for both, so that the two cannot
        /// drift apart. Writers check nothing of the kind.
        let limits: [NumberLimit]
        /// `nil` for an attribute that cannot be changed.
        let write: AttributeWriter<Subject>?
        let read: (Subject, AttributeReading) -> AttributeValue?

        var isEditable: Bool { write != nil }

        init(
            _ name: String,
            _ kind: AttributeValueKind,
            title: String? = nil,
            acceptsNil: Bool = false,
            section: AttributeSection,
            cluster: (name: String, slot: String)? = nil,
            unit: AttributeUnit = .unspecified,
            limits: [NumberLimit] = [],
            onlyWithoutView: Bool = false,
            inactiveCause: ((Subject) -> String?)? = nil,
            write: AttributeWriter<Subject>?,
            read: @escaping (Subject) -> AttributeValue?
        ) {
            self.init(
                name,
                kind,
                title: title,
                acceptsNil: acceptsNil,
                section: section,
                cluster: cluster,
                unit: unit,
                limits: limits,
                onlyWithoutView: onlyWithoutView,
                inactiveCause: inactiveCause,
                write: write,
                readWith: { subject, _ in read(subject) }
            )
        }

        /// For an attribute that needs more than its subject to be read.
        init(
            _ name: String,
            _ kind: AttributeValueKind,
            title: String? = nil,
            acceptsNil: Bool = false,
            section: AttributeSection,
            cluster: (name: String, slot: String)? = nil,
            unit: AttributeUnit = .unspecified,
            limits: [NumberLimit] = [],
            onlyWithoutView: Bool = false,
            inactiveCause: ((Subject) -> String?)? = nil,
            write: AttributeWriter<Subject>?,
            readWith read: @escaping (Subject, AttributeReading) -> AttributeValue?
        ) {
            self.name = name
            self.title = title
            self.kind = kind
            self.acceptsNil = acceptsNil
            self.section = section
            self.cluster = cluster
            self.unit = unit
            self.onlyWithoutView = onlyWithoutView
            self.inactiveCause = inactiveCause
            self.limits = limits
            self.write = write
            self.read = read
        }

        /// P-ATTR-18: the objects a property holds, in its order; `nil` when it holds none
        /// that can be listed (a nil delegate). Read-only.
        @MainActor static func references(
            _ name: String,
            title: String? = nil,
            section: AttributeSection,
            _ objects: @escaping (Subject) -> [AnyObject]?
        ) -> Self {
            Self(name, .layerReference, title: title, section: section, write: nil, readWith: { subject, reading in
                objects(subject).map { objects in .layerReference(objects.map { reading.reference(to: $0) }) }
            })
        }
    }

    /// The ID and the title of one attribute of a group.
    struct AttributeName {
        let id: String
        let title: String
    }

    /// One group: where its subject comes from, and its attributes in order.
    struct GroupDefinition {
        let id: String
        let title: String
        /// The class that declares the group's properties (P-ATTR-16).
        let className: String
        /// IDs and titles of the attributes, in order.
        let attributes: [AttributeName]
        /// The attributes in the order of `attributes`; `nil` when the group does not apply.
        private let values: (CALayer, UIView?, AttributeReading) -> [Attribute]?
        /// The attribute with an ID, and how to change it; `nil` when the group does not apply or
        /// has no attribute with that ID.
        private let edits: (String, CALayer, UIView?, AttributeReading) -> AttributeEdit?

        init<Subject>(
            _ id: String,
            className: String,
            subject: @escaping (CALayer, UIView?) -> Subject?,
            _ definitions: [AttributeDefinition<Subject>]
        ) {
            self.id = id
            title = AttributeCatalog.title(for: id)
            self.className = className
            let attributes = definitions.map {
                AttributeName(id: "\(id).\($0.name)", title: $0.title ?? AttributeCatalog.title(for: $0.name))
            }
            self.attributes = attributes
            values = { layer, view, reading in
                guard let subject = subject(layer, view) else { return nil }
                return zip(attributes, definitions).compactMap { name, definition in
                    // P-ATTR-11: the view's attribute of a pair stands for the layer's.
                    if definition.onlyWithoutView, view != nil { return nil }
                    return AttributeCatalog.attribute(
                        id: name.id,
                        title: name.title,
                        value: definition.read(subject, reading),
                        inactiveCause: definition.inactiveCause?(subject),
                        definition: definition
                    )
                }
            }
            edits = { attributeID, layer, view, reading in
                guard let index = attributes.firstIndex(where: { $0.id == attributeID }),
                      let subject = subject(layer, view) else {
                    return nil
                }
                let definition = definitions[index]
                // Not among the layer's attributes, so not one that can be changed (P-SET-03).
                if definition.onlyWithoutView, view != nil { return nil }
                let attribute = AttributeCatalog.attribute(
                    id: attributeID,
                    title: attributes[index].title,
                    value: definition.read(subject, reading),
                    inactiveCause: definition.inactiveCause?(subject),
                    definition: definition
                )
                guard attribute.editable, let writer = definition.write else {
                    return AttributeEdit(attribute: attribute, prepare: nil)
                }
                return AttributeEdit(attribute: attribute, prepare: { writer.prepare(subject, $0) })
            }
        }

        func read(_ layer: CALayer, _ view: UIView?, _ reading: AttributeReading) -> AttributeGroup? {
            guard let attributes = values(layer, view, reading) else { return nil }
            return AttributeGroup(id: id, title: title, attributes: attributes, className: className)
        }

        func attributeForEditing(
            _ attributeID: String,
            _ layer: CALayer,
            _ view: UIView?,
            _ reading: AttributeReading
        ) -> AttributeEdit? {
            edits(attributeID, layer, view, reading)
        }
    }

    /// P-ATTR-06: the kind is the declared one, also for nil. A value that fell back to a
    /// `StringValue` (P-ATTR-03) is of another kind; that reading is sent as read-only, with
    /// the kind it has, and so without limits (P-ATTR-09). Nil is only offered for an attribute
    /// that can be changed. The section, the cluster and the inactive cause are the attribute's
    /// whatever its value (P-ATTR-08, 12, 13); a unit only goes with a number (P-ATTR-14).
    nonisolated static func attribute<Subject>(
        id: String,
        title: String,
        value: AttributeValue?,
        inactiveCause: String? = nil,
        definition: AttributeDefinition<Subject>
    ) -> Attribute {
        var attribute: Attribute
        if let value, value.kind != definition.kind {
            attribute = Attribute(
                id: id,
                title: title,
                value: value,
                valueKind: value.kind,
                section: definition.section
            )
        } else {
            let editable = definition.isEditable
            attribute = Attribute(
                id: id,
                title: title,
                value: value,
                editable: editable,
                acceptsNil: editable && definition.acceptsNil,
                valueKind: definition.kind,
                section: definition.section,
                limits: editable && definition.kind.isNumeric ? definition.limits : [],
                unit: definition.kind.isNumeric && definition.kind != .transform ? definition.unit : .unspecified
            )
        }
        attribute.cluster = definition.cluster?.name
        attribute.slot = definition.cluster?.slot
        attribute.inactiveCause = inactiveCause
        return attribute
    }
}
#endif
