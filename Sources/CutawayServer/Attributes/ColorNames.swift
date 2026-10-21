#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The names of the colors the host app registered (PROTOCOL.md, P-ATTR-20).
@MainActor
enum ColorNames {
    /// `groups` with every color value that equals a registered color named after the first
    /// such color. A registered color resolves with the traits of `view`, by the rules of the
    /// values (P-ATTR-04, 17); two are equal when, in 8 bits, their values are, and their light
    /// and dark values are absent on both sides or equal. Nothing is resolved for groups without
    /// a color value.
    static func named(
        _ groups: [AttributeGroup],
        registered colors: Registered,
        cache: Cache,
        in view: UIView?
    ) -> [AttributeGroup] {
        guard !colors.colors.isEmpty, let view, groups.contains(where: hasColorValue) else { return groups }
        let registered = cache.resolve(colors, for: view)
        guard !registered.isEmpty else { return groups }
        return groups.map { group in
            var group = group
            for index in group.attributes.indices {
                guard case .color(let value, let systemName, let light, let dark, _)? = group.attributes[index].value
                else { continue }
                let key = Key(value: value, light: light, dark: dark)
                let name = registered.first { $0.key == key }?.name
                group.attributes[index].value = .color(
                    value,
                    systemName: systemName,
                    light: light,
                    dark: dark,
                    name: name
                )
            }
            return group
        }
    }

    /// Some attribute of `group` has a color value.
    private static func hasColorValue(_ group: AttributeGroup) -> Bool {
        group.attributes.contains { attribute in
            if case .color? = attribute.value { return true }
            return false
        }
    }

    /// The registered colors as a request found them when it began.
    struct Registered {
        let colors: [ExtensionStore.NamedColor]
        /// Where they were registered, and the store's revision then.
        let store: ObjectIdentifier
        let revision: Int

        @MainActor init(_ store: ExtensionStore) {
            colors = store.colors
            self.store = ObjectIdentifier(store)
            revision = store.revision
        }
    }

    /// A color as P-ATTR-20 compares it.
    struct Key: Equatable {
        let value: [Int]
        let light: [Int]?
        let dark: [Int]?

        init(value: WireColor, light: WireColor?, dark: WireColor?) {
            self.value = value.in8Bits
            self.light = light?.in8Bits
            self.dark = dark?.in8Bits
        }
    }

    /// The registered colors as they resolve, for one request (its `RequestMemo` keeps it):
    /// worked out once for each trait collection a view has, and again once something is
    /// registered. The next request, and the answer to a change, resolve them anew.
    @MainActor
    final class Cache {
        /// The colors in the order of the store, each with its key; a color whose key cannot be
        /// worked out is left out.
        typealias Resolved = [(name: String, key: Key)]

        /// The most trait collections remembered; the oldest is dropped first.
        static let capacity = 16

        /// The store and the revision that `resolved` was worked out from.
        private var source: (store: ObjectIdentifier, revision: Int)?
        private var resolved: [(traits: UITraitCollection, colors: Resolved)] = []

        /// `registered` resolved with the traits of `view`.
        func resolve(_ registered: Registered, for view: UIView) -> Resolved {
            if source?.store != registered.store || source?.revision != registered.revision {
                source = (registered.store, registered.revision)
                resolved = []
            }
            let traits = view.traitCollection
            // Equal when each has every trait the other gives a value.
            if let known = resolved.first(where: {
                $0.traits.containsTraits(in: traits) && traits.containsTraits(in: $0.traits)
            }) {
                return known.colors
            }
            let colors = registered.colors.compactMap { named -> (name: String, key: Key)? in
                guard case .color(let value, _, let light, let dark, _)? = AttributeOutputs.color(named.color, in: view)
                else {
                    return nil
                }
                return (named.name, Key(value: value, light: light, dark: dark))
            }
            if resolved.count == Self.capacity { resolved.removeFirst() }
            resolved.append((traits, colors))
            return colors
        }
    }
}
#endif
