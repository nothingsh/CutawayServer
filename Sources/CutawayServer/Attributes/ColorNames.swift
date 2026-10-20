#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The names of the colors the host app registered (PROTOCOL.md, P-ATTR-20).
@MainActor
enum ColorNames {
    /// `groups` with every color value that equals a registered color named after the first
    /// such color. A registered color resolves with the traits of `view`, by the rules of the
    /// values (P-ATTR-04, 17); two are equal when, in 8 bits, their values are, and their light
    /// and dark values are absent on both sides or equal.
    static func named(
        _ groups: [AttributeGroup],
        colors: [ExtensionStore.NamedColor],
        in view: UIView?
    ) -> [AttributeGroup] {
        guard !colors.isEmpty, let view else { return groups }
        let registered = colors.compactMap { named -> (name: String, key: Key)? in
            guard case .color(let value, _, let light, let dark, _)? = AttributeOutputs.color(named.color, in: view)
            else {
                return nil
            }
            return (named.name, Key(value: value, light: light, dark: dark))
        }
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

    /// A color as P-ATTR-20 compares it.
    private struct Key: Equatable {
        let value: [Int]
        let light: [Int]?
        let dark: [Int]?

        init(value: WireColor, light: WireColor?, dark: WireColor?) {
            self.value = value.in8Bits
            self.light = light?.in8Bits
            self.dark = dark?.in8Bits
        }
    }
}
#endif
