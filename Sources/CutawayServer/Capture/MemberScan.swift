#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import ObjectiveC
import UIKit

/// Finds the instance variables that hold each layer of a hierarchy, or the view the layer
/// backs (PROTOCOL.md, P-HIER-08, P-HIER-09).
///
/// The holders' own memory is read word by word, at the offsets the Objective-C runtime
/// gives for their variables, and each word is compared with the addresses of the
/// hierarchy's layers and views. A word is never used as an object: nothing is retained, no
/// getter runs, and a reference to a released object cannot crash. What this cannot see:
/// plain `unowned` properties, which do not hold the
/// address; references inside collections, which live outside the holder.
@MainActor
enum MemberScan {
    /// One variable of a class, and where its words are.
    struct Variable: Equatable {
        /// As sent (P-HIER-09).
        var name: String
        /// Byte offsets into an instance, each the start of a word to compare.
        var offsets: [Int]
    }

    /// The bytes of one word: an object reference.
    private static let wordSize = MemoryLayout<UInt>.size

    /// The storage Swift gives a `lazy` property is named with this in front of the property.
    static let lazyStoragePrefix = "$__lazy_storage_$_"

    /// The references to each node, nearest holder first.
    ///
    /// - Parameters:
    ///   - nodes: the hierarchy in pre-order.
    ///   - layers: the layer of each node, at the same index.
    ///   - views: the view each layer backs, or `nil`, at the same index.
    ///   - controllers: the controller whose root view that is, or `nil`, at the same index.
    static func references(
        nodes: [LayerNode],
        layers: [CALayer],
        views: [UIView?],
        controllers: [UIViewController?],
        classNames: inout ClassNames.Cache
    ) -> [[MemberReference]] {
        let ends = subtreeEnds(of: nodes)
        let targets = targets(layers: layers, views: views)
        var state = ScanState(found: Array(repeating: [], count: nodes.count), classNames: classNames)
        defer { classNames = state.classNames }
        for holderIndex in 0..<nodes.count {
            // A holder only counts for what lies strictly below it.
            guard let view = views[holderIndex], ends[holderIndex] > holderIndex + 1 else { continue }
            var holders: [AnyObject] = [view]
            if let controller = controllers[holderIndex] {
                holders.append(controller)
            }
            for (rank, holder) in holders.enumerated() {
                scan(
                    holder,
                    rank: rank,
                    holderIndex: holderIndex,
                    subtreeEnd: ends[holderIndex],
                    targets: targets,
                    state: &state
                )
            }
        }
        return state.found.map { entries in entries.sorted { $0.key < $1.key }.map(\.reference) }
    }

    /// One reference found, with where it sorts.
    private typealias Found = (key: Key, reference: MemberReference)

    /// A variable of a holder's class or one of its superclasses up to `UIResponder`.
    private struct Slot {
        /// How many classes up from the holder's own; the variable's place in that class.
        var depth: Int
        var position: Int
        var ownerNames: (runtime: String, display: String)
        var variable: Variable
    }

    /// What a scan reads and adds to across holders.
    private struct ScanState {
        /// The variables of each class seen so far.
        var plans: [ObjectIdentifier: [Variable]] = [:]
        /// The slots of each holder class seen so far, subclass first.
        var slots: [ObjectIdentifier: [Slot]] = [:]
        /// The references found to each node, at its index.
        var found: [[Found]]
        var classNames: ClassNames.Cache
    }

    /// In pre-order, the subtree of node i is i..<ends[i].
    private static func subtreeEnds(of nodes: [LayerNode]) -> [Int] {
        var indexOfID: [UInt64: Int] = [:]
        for (index, node) in nodes.enumerated() { indexOfID[node.id] = index }
        var end = (0..<nodes.count).map { $0 + 1 }
        for index in stride(from: nodes.count - 1, through: 0, by: -1) {
            if let parent = indexOfID[nodes[index].parentID] {
                end[parent] = max(end[parent], end[index])
            }
        }
        return end
    }

    /// What a word may point at, by address: a node's layer, or the view it backs.
    private static func targets(layers: [CALayer], views: [UIView?]) -> [UInt: Int] {
        var targets: [UInt: Int] = [:]
        for (index, layer) in layers.enumerated() {
            targets[address(of: layer)] = index
            if let view = views[index] { targets[address(of: view)] = index }
        }
        return targets
    }

    /// Reads the words of `holder`'s variables, class by class up to `UIResponder`, and records
    /// each one that points at a node below the holder: after `holderIndex`, before
    /// `subtreeEnd`.
    private static func scan(
        _ holder: AnyObject,
        rank: Int,
        holderIndex: Int,
        subtreeEnd: Int,
        targets: [UInt: Int],
        state: inout ScanState
    ) {
        let base = UnsafeRawPointer(Unmanaged.passUnretained(holder).toOpaque())
        guard let holderClass = object_getClass(holder) else { return }
        let slots = state.slots[ObjectIdentifier(holderClass)]
            ?? slots(for: holderClass, plans: &state.plans, classNames: &state.classNames)
        state.slots[ObjectIdentifier(holderClass)] = slots
        for slot in slots {
            for offset in slot.variable.offsets {
                let word = base.load(fromByteOffset: offset, as: UInt.self)
                guard let target = targets[word], target > holderIndex, target < subtreeEnd else { continue }
                let key = Key(holder: holderIndex, rank: rank, depth: slot.depth, position: slot.position)
                guard !state.found[target].contains(where: { $0.key == key }) else { continue }
                state.found[target].append(
                    (
                        key,
                        MemberReference(
                            ownerClassName: slot.ownerNames.runtime,
                            ownerDisplayClassName: slot.ownerNames.display,
                            name: slot.variable.name
                        )
                    )
                )
            }
        }
    }

    /// The variables of `type` and its superclasses below `UIResponder`, subclass first.
    private static func slots(
        for type: AnyClass,
        plans: inout [ObjectIdentifier: [Variable]],
        classNames: inout ClassNames.Cache
    ) -> [Slot] {
        var slots: [Slot] = []
        var current: AnyClass? = type
        var depth = 0
        while let owner = current, ObjectIdentifier(owner) != ObjectIdentifier(UIResponder.self) {
            let variables = plans[ObjectIdentifier(owner)] ?? plan(for: owner)
            plans[ObjectIdentifier(owner)] = variables
            if !variables.isEmpty {
                let ownerNames = classNames.names(of: owner)
                for (position, variable) in variables.enumerated() {
                    slots.append(Slot(depth: depth, position: position, ownerNames: ownerNames, variable: variable))
                }
            }
            current = class_getSuperclass(owner)
            depth += 1
        }
        return slots
    }

    /// The variables `type` declares itself, in the order of declaration, with the words to
    /// read. Every word lies inside an instance of `type`.
    static func plan(for type: AnyClass) -> [Variable] {
        var count: UInt32 = 0
        guard let list = class_copyIvarList(type, &count) else { return [] }
        defer { free(list) }
        let ivars = (0..<Int(count)).map { list[$0] }
        let starts = ivars.map(ivar_getOffset)
        let instanceSize = class_getInstanceSize(type)
        var variables: [Variable] = []
        for (index, ivar) in ivars.enumerated() {
            guard let rawName = ivar_getName(ivar) else { continue }
            let start = starts[index]
            // A variable reaches to the next one in memory, or to the end of the instance.
            let next = starts.filter { $0 > start }.min() ?? instanceSize
            let encoding = ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? ""
            var offsets: [Int] = []
            if encoding.isEmpty {
                // Swift gives no encoding. Every aligned word: a tuple or a struct may hold a
                // reference after its first word.
                var offset = (start + wordSize - 1) / wordSize * wordSize
                while offset + wordSize <= next {
                    offsets.append(offset)
                    offset += wordSize
                }
            } else if encoding.hasPrefix("@"), encoding != "@?", start % wordSize == 0,
                      start + wordSize <= next {
                // An Objective-C object, but not a block.
                offsets.append(start)
            }
            guard !offsets.isEmpty else { continue }
            variables.append(Variable(name: name(of: String(cString: rawName)), offsets: offsets))
        }
        return variables
    }

    /// P-HIER-09: without what the Swift compiler puts in front of a `lazy` property's storage.
    /// Objective-C's leading underscore stays.
    static func name(of variable: String) -> String {
        variable.hasPrefix(lazyStoragePrefix)
            ? String(variable.dropFirst(lazyStoragePrefix.count)) : variable
    }

    private static func address(of object: AnyObject) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
    }

    /// The order of P-HIER-08: the nearest holder first (a deeper node has a larger index in
    /// pre-order); on one node the view before its controller; then subclass before superclass;
    /// then the order of declaration.
    private struct Key: Equatable, Comparable {
        var holder: Int
        var rank: Int
        var depth: Int
        var position: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.holder != rhs.holder { return lhs.holder > rhs.holder }
            return (lhs.rank, lhs.depth, lhs.position) < (rhs.rank, rhs.depth, rhs.position)
        }
    }
}
#endif
