import CutawayWire

/// What a server of protocol 1.1 adds to the hierarchies the tests make up: addresses, and
/// the facts about classes.
enum Addresses {
    /// Gives every node a layer address, and a view's and a view controller's address exactly
    /// where it names their classes (P-HIER-14). Call it again after changing a hierarchy.
    static func add(to hierarchy: inout Hierarchy) {
        for index in hierarchy.nodes.indices {
            let id = hierarchy.nodes[index].id
            hierarchy.nodes[index].layerAddress = 0x6000_0000_0000 + 0x40 * id
            hierarchy.nodes[index].viewAddress = hierarchy.nodes[index].viewClassName.map { _ in
                0x1_0000_0000 + 0x200 * id
            }
            hierarchy.nodes[index].viewControllerAddress = hierarchy.nodes[index].viewControllerClassName.map { _ in
                0x1_1000_0000 + 0x200 * id
            }
            addClassFacts(to: &hierarchy.nodes[index])
        }
    }

    /// The origins (P-HIER-16), the base classes of the classes the tables name themselves
    /// (P-HIER-17), and the view controllers shown (P-HIER-18), exactly where the class names
    /// are given. The demo app's own classes are in its module.
    private static func addClassFacts(to node: inout LayerNode) {
        func origin(_ name: String) -> Origin {
            name.hasPrefix("CutawayDemo.") || name.hasPrefix("Demo.") ? .app : .system
        }
        let views = KnownClasses.names(of: KnownClasses.views, at: .current)
        let layers = KnownClasses.names(of: KnownClasses.layers, at: .current)
        node.layerClassOrigin = origin(node.className)
        node.viewClassOrigin = node.viewClassName.map(origin) ?? .unknown
        node.viewControllerClassOrigin = node.viewControllerClassName.map(origin) ?? .unknown
        node.viewControllerVisibility = node.viewControllerClassName == nil ? .unknown : .shown
        node.layerBaseClassName = layers.contains(node.className) ? node.className : nil
        node.viewBaseClassName = node.viewClassName.flatMap { views.contains($0) ? $0 : nil }
    }
}
