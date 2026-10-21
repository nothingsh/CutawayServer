// Compiled in every configuration; see CutawayServer+Description.swift.
#if canImport(UIKit)
import CoreGraphics

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
        /// Called only when the node's attributes are read, not when the hierarchy is.
        let attributes: @MainActor () -> [AttributeGroup]
        let children: [Self]

        /// - Parameters:
        ///   - id: What the node stands for, the same value every time: a model's identifier
        ///     rather than an index. Among the nodes of one layer an identity appears once; a
        ///     node that repeats one is left out with its children. Cutaway keeps every identity
        ///     it was given until the connection ends or the node's layer is released, so it
        ///     should be a value such as a `String`, an `Int` or a `UUID`, not an object.
        ///   - type: The type of what the node stands for. Cutaway shows its name.
        ///   - name: A short label, for example the bar's category.
        ///   - frame: In the coordinate space of the parent: the layer's bounds, or the parent
        ///     node's frame with its origin at zero.
        ///   - transform: Applied about the center of `frame`.
        ///   - isHidden: Shown as hidden, as a layer's `isHidden`.
        ///   - opacity: Shown as the node's opacity, as a layer's `opacity`.
        ///   - isCollapsedByDefault: Asks Cutaway to show the node collapsed at first.
        ///   - attributes: Shown when the node is selected; they may be edited like any other.
        ///     Worked out only then, on the main thread, and not when the hierarchy is read.
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
            attributes: @autoclosure @escaping @MainActor () -> [AttributeGroup] = [],
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
        ///
        /// - Parameter typeName: Shown as the name of the node's type. The other parameters are
        ///   those of `init(id:type:…)`.
        public init(
            id: AnyHashable,
            typeName: String,
            name: String? = nil,
            frame: CGRect,
            transform: CGAffineTransform = .identity,
            isHidden: Bool = false,
            opacity: Float = 1,
            isCollapsedByDefault: Bool = false,
            attributes: @autoclosure @escaping @MainActor () -> [AttributeGroup] = [],
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
            attributes: @escaping @MainActor () -> [AttributeGroup],
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
