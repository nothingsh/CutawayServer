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
        /// The member of `AttributeValue` the attribute uses (P-ATTR-06).
        let kind: AttributeValueKind
        /// May be set to nil. Whether it may read as nil is up to `read`.
        let acceptsNil: Bool
        /// `nil` for an attribute that cannot be changed.
        let write: AttributeWriter<Subject>?
        let read: (Subject) -> AttributeValue?

        var isEditable: Bool { write != nil }

        init(
            _ name: String,
            _ kind: AttributeValueKind,
            acceptsNil: Bool = false,
            write: AttributeWriter<Subject>?,
            read: @escaping (Subject) -> AttributeValue?
        ) {
            self.name = name
            self.kind = kind
            self.acceptsNil = acceptsNil
            self.write = write
            self.read = read
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
        /// IDs and titles of the attributes, in order.
        let attributes: [AttributeName]
        /// The attributes in the order of `attributes`; `nil` when the group does not apply.
        private let values: (CALayer, UIView?) -> [Attribute]?
        /// The attribute with an ID, and how to change it; `nil` when the group does not apply or
        /// has no attribute with that ID.
        private let edits: (String, CALayer, UIView?) -> AttributeEdit?

        init<Subject>(
            _ id: String,
            subject: @escaping (CALayer, UIView?) -> Subject?,
            _ definitions: [AttributeDefinition<Subject>]
        ) {
            self.id = id
            title = AttributeCatalog.title(for: id)
            let attributes = definitions.map {
                AttributeName(id: "\(id).\($0.name)", title: AttributeCatalog.title(for: $0.name))
            }
            self.attributes = attributes
            values = { layer, view in
                guard let subject = subject(layer, view) else { return nil }
                return zip(attributes, definitions).map { name, definition in
                    AttributeCatalog.attribute(
                        id: name.id,
                        title: name.title,
                        value: definition.read(subject),
                        definition: definition
                    )
                }
            }
            edits = { attributeID, layer, view in
                guard let index = attributes.firstIndex(where: { $0.id == attributeID }),
                      let subject = subject(layer, view) else {
                    return nil
                }
                let definition = definitions[index]
                let attribute = AttributeCatalog.attribute(
                    id: attributeID,
                    title: attributes[index].title,
                    value: definition.read(subject),
                    definition: definition
                )
                guard attribute.editable, let writer = definition.write else {
                    return AttributeEdit(attribute: attribute, prepare: nil)
                }
                return AttributeEdit(attribute: attribute, prepare: { writer.prepare(subject, $0) })
            }
        }

        func read(_ layer: CALayer, _ view: UIView?) -> AttributeGroup? {
            guard let attributes = values(layer, view) else { return nil }
            return AttributeGroup(id: id, title: title, attributes: attributes)
        }

        func attributeForEditing(_ attributeID: String, _ layer: CALayer, _ view: UIView?) -> AttributeEdit? {
            edits(attributeID, layer, view)
        }
    }

    /// P-ATTR-06: the kind is the declared one, also for nil. A value that fell back to a
    /// `StringValue` (P-ATTR-03) is of another kind; that reading is sent as read-only, with
    /// the kind it has. Nil is only offered for an attribute that can be changed.
    nonisolated static func attribute<Subject>(
        id: String,
        title: String,
        value: AttributeValue?,
        definition: AttributeDefinition<Subject>
    ) -> Attribute {
        if let value, value.kind != definition.kind {
            return Attribute(id: id, title: title, value: value, valueKind: value.kind)
        }
        return Attribute(
            id: id,
            title: title,
            value: value,
            editable: definition.isEditable,
            acceptsNil: definition.isEditable && definition.acceptsNil,
            valueKind: definition.kind
        )
    }
}
#endif
