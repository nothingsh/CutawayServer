import CutawayWire
import QuartzCore

@testable import CutawayServer

// Reading without a connection: a registry of its own and the app's windows. The tests of the
// attributes that refer to other objects pass the registry they look the IDs up in.

@MainActor
extension AttributeReading {
    /// A registry of its own and the app's windows.
    static func standalone() -> AttributeReading {
        AttributeReading(registry: LayerRegistry(), windows: HostWindows.all())
    }
}

@MainActor
extension AttributeCatalog {
    func read(_ layer: CALayer) -> [AttributeGroup] {
        read(layer, reading: .standalone())
    }

    func attributeForEditing(_ id: String, of layer: CALayer) -> AttributeEdit? {
        attributeForEditing(id, of: layer, reading: .standalone())
    }
}
