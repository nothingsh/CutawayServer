// The extension interface is compiled in every configuration, so that the host app can call it
// without conditions of its own; without DEBUG or the trait ReleaseEnabled registering does
// nothing. Every type is nested in `CutawayServer`, the module's only other public symbol.
#if canImport(UIKit)
import UIKit

extension CutawayServer {
    /// What Cutaway shows of instances of `Subject` and its subclasses, beyond what it reads
    /// itself. Register it with `describe(_:_:)`.
    ///
    /// The closures are called on the main thread each time Cutaway reads what they give: a
    /// hierarchy, a node's attributes, and the node's attributes again after a change made
    /// through an attribute's `set`, so that the answer shows the change. Within one request for
    /// details, a layer's virtual children are asked for once, however many of its nodes the
    /// request names. What they return is dropped once the request is answered, except the
    /// identities of virtual nodes (see `VirtualNode.init`). They must only
    /// read: change the app in an attribute's `set` closure, nowhere else.
    public struct Description<Subject: AnyObject> {
        /// Attribute groups of the instance, shown after Cutaway's own.
        public var attributes: (@MainActor (Subject) -> [AttributeGroup])?
        /// Parts of the interface the instance draws itself, shown as children of its layer,
        /// before its sublayers.
        public var virtualChildren: (@MainActor (Subject) -> [VirtualNode])?
        /// Asks Cutaway to show the instance collapsed at first, for example the inside of a
        /// complex control.
        public var isCollapsedByDefault: Bool
        /// Leaves the instance and everything inside it out of every image: for content that is
        /// sensitive, or slow or impossible to capture.
        public var isExcludedFromCapture: Bool

        /// A description with any of its parts; one left out adds nothing.
        public init(
            attributes: (@MainActor (Subject) -> [AttributeGroup])? = nil,
            virtualChildren: (@MainActor (Subject) -> [VirtualNode])? = nil,
            isCollapsedByDefault: Bool = false,
            isExcludedFromCapture: Bool = false
        ) {
            self.attributes = attributes
            self.virtualChildren = virtualChildren
            self.isCollapsedByDefault = isCollapsedByDefault
            self.isExcludedFromCapture = isExcludedFromCapture
        }
    }

    /// Describes the views of a class and of its subclasses. Takes effect from the next request;
    /// a later call for the same class replaces this one.
    ///
    /// When several descriptions apply to one layer (its class and its view's, and their
    /// superclasses), all their attribute groups are shown, the layer's before the view's and
    /// each from the superclass down; the virtual children come from the most specific
    /// description that has them, a view's before a layer's; and either flag set on any of them
    /// holds.
    @MainActor
    public static func describe<View: UIView>(_ type: View.Type, _ description: Description<View>) {
        #if DEBUG || ReleaseEnabled
        ExtensionStore.shared.describe(type, description, isView: true)
        #endif
    }

    /// Describes the layers of a class and of its subclasses, as `describe(_:_:)` does views.
    @MainActor
    public static func describe<Layer: CALayer>(_ type: Layer.Type, _ description: Description<Layer>) {
        #if DEBUG || ReleaseEnabled
        ExtensionStore.shared.describe(type, description, isView: false)
        #endif
    }

    /// Registers a color by name: a color value equal to it is shown with this name. When
    /// several registered colors are equal, the first registered is used. Registering a name
    /// again replaces its color and keeps its place.
    ///
    /// A dynamic color is resolved on the main thread with the traits of the view whose color
    /// it is compared with: once for each set of traits within a request (all the layers of one
    /// request for details count as one), and again in every later request.
    @MainActor
    public static func registerColor(_ color: UIColor, named name: String) {
        #if DEBUG || ReleaseEnabled
        ExtensionStore.shared.registerColor(color, named: name)
        #endif
    }
}
#endif
