// Compiled in every configuration; see CutawayServer+Description.swift.
#if canImport(UIKit)
import UIKit

extension CutawayServer {
    /// A part of the interface that a view or a layer draws itself, such as one bar of a chart:
    /// Cutaway shows it as a node of the hierarchy that can be selected and inspected. Its
    /// appearance stays in the images of the layer that draws it.
    public struct VirtualNode {
        let identity: AnyHashable
        let className: String
        let displayClassName: String
        let name: String?
        let frame: CGRect
        let transform: CGAffineTransform
        let isHidden: Bool
        let opacity: Float
        let isCollapsedByDefault: Bool
        let attributes: [AttributeGroup]
        let children: [Self]

        /// - Parameters:
        ///   - id: What the node stands for, the same value every time: a model's identifier
        ///     rather than an index. Among the nodes of one layer an identity appears once; a
        ///     node that repeats one is left out with its children.
        ///   - type: The type of what the node stands for. Cutaway shows its name.
        ///   - name: A short label, for example the bar's category.
        ///   - frame: In the coordinate space of the parent: the layer's bounds, or the parent
        ///     node's frame with its origin at zero.
        ///   - transform: Applied about the center of `frame`.
        ///   - attributes: Shown when the node is selected; they may be edited like any other.
        ///   - children: Nodes drawn inside this one.
        public init(
            id: AnyHashable,
            type: Any.Type,
            name: String? = nil,
            frame: CGRect,
            transform: CGAffineTransform = .identity,
            isHidden: Bool = false,
            opacity: Float = 1,
            isCollapsedByDefault: Bool = false,
            attributes: [AttributeGroup] = [],
            children: [Self] = []
        ) {
            self.init(
                identity: id,
                className: String(reflecting: type),
                displayClassName: String(describing: type),
                name: name,
                frame: frame,
                transform: transform,
                isHidden: isHidden,
                opacity: opacity,
                isCollapsedByDefault: isCollapsedByDefault,
                attributes: attributes,
                children: children
            )
        }

        /// The same, with the type's name given as text, for a node that stands for no Swift type.
        public init(
            id: AnyHashable,
            typeName: String,
            name: String? = nil,
            frame: CGRect,
            transform: CGAffineTransform = .identity,
            isHidden: Bool = false,
            opacity: Float = 1,
            isCollapsedByDefault: Bool = false,
            attributes: [AttributeGroup] = [],
            children: [Self] = []
        ) {
            self.init(
                identity: id,
                className: typeName,
                displayClassName: typeName,
                name: name,
                frame: frame,
                transform: transform,
                isHidden: isHidden,
                opacity: opacity,
                isCollapsedByDefault: isCollapsedByDefault,
                attributes: attributes,
                children: children
            )
        }

        private init(
            identity: AnyHashable,
            className: String,
            displayClassName: String,
            name: String?,
            frame: CGRect,
            transform: CGAffineTransform,
            isHidden: Bool,
            opacity: Float,
            isCollapsedByDefault: Bool,
            attributes: [AttributeGroup],
            children: [Self]
        ) {
            self.identity = identity
            self.className = className
            self.displayClassName = displayClassName
            self.name = name
            self.frame = frame
            self.transform = transform
            self.isHidden = isHidden
            self.opacity = opacity
            self.isCollapsedByDefault = isCollapsedByDefault
            self.attributes = attributes
            self.children = children
        }
    }
}
#endif
