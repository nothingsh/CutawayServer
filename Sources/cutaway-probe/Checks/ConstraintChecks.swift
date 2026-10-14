import CutawayWire
import Foundation

/// What the constraints in layer details have to look like (PROTOCOL.md, P-LAYOUT-01 to
/// P-LAYOUT-08), and the demo app's known constraints. Every function throws a
/// `ProbeFailure` naming the first thing that is wrong.
enum ConstraintChecks {
    /// What earlier details of a stream sent, by ID: the same constraint and the same guide
    /// have to look the same everywhere (P-LAYOUT-03).
    struct Tables {
        var constraints: [UInt64: LayoutConstraint] = [:]
        var guides: [UInt64: LayoutItem] = [:]
    }

    /// One detail's constraints, the checks of the protocol's check-fixtures.py.
    ///
    /// - Parameters:
    ///   - node: The detail's layer in the hierarchy, if it is there.
    ///   - nodes: The hierarchy's nodes by ID; the items' layers are looked up in it.
    static func structure(
        _ detail: LayerDetail,
        for request: LayerDetailRequest,
        node: LayerNode?,
        nodes: [UInt64: LayerNode],
        tables: inout Tables,
        version: ProtocolVersion = .current
    ) throws {
        let layer = "layer \(detail.layerID)"
        guard !detail.constraints.isEmpty else { return }
        guard detail.status != .layerNotFound else {
            throw ProbeFailure("the detail of \(layer) is LayerNotFound and has constraints (P-DET-02)")
        }
        guard request.wantConstraints else {
            throw ProbeFailure(
                "the detail of \(layer) has constraints, but the request did not want them (P-LAYOUT-01)"
            )
        }
        guard node?.viewClassName != nil else {
            throw ProbeFailure("the detail of \(layer) has constraints, but the layer backs no view (P-LAYOUT-01)")
        }
        for constraint in detail.constraints {
            try check(constraint, of: detail.layerID, nodes: nodes, tables: &tables, version: version)
        }
    }

    private static func check(
        _ constraint: LayoutConstraint,
        of layerID: UInt64,
        nodes: [UInt64: LayerNode],
        tables: inout Tables,
        version: ProtocolVersion
    ) throws {
        let name = "constraint \(constraint.id) of layer \(layerID)"
        if version.minor >= 1, constraint.origin == .unknown {
            throw ProbeFailure("\(name) has no origin (P-LAYOUT-09)")
        }
        guard constraint.id != 0 else { throw ProbeFailure("\(name): id is 0 (P-LAYOUT-03)") }
        guard constraint.className?.isEmpty == false else {
            throw ProbeFailure("\(name) has no class_name (P-LAYOUT-02)")
        }
        guard let first = constraint.firstItem else {
            throw ProbeFailure("\(name) has no first_item (P-LAYOUT-04)")
        }
        // P-LAYOUT-08 lets a server send NotAnAttribute for an attribute the protocol does not
        // name, or one the client's version lacks. This probe speaks the server's version, so
        // only the first can happen: the system uses an attribute the protocol cannot express.
        let unnamed =
            "; with a server of this probe's version that means an attribute the protocol "
                + "does not name yet (P-LAYOUT-08)"
        guard constraint.firstAttribute != .notAnAttribute else {
            throw ProbeFailure("\(name) has first_attribute NotAnAttribute\(unnamed)")
        }
        switch (constraint.secondItem == nil, constraint.secondAttribute == .notAnAttribute) {
        case (true, false):
            throw ProbeFailure(
                "\(name) has no second_item, but second_attribute \(constraint.secondAttribute) (P-LAYOUT-05)"
            )
        case (false, true):
            throw ProbeFailure(
                "\(name) has a second_item, but second_attribute NotAnAttribute (P-LAYOUT-05)\(unnamed)"
            )
        default:
            break
        }
        guard (1...1000).contains(constraint.priority) else {
            throw ProbeFailure("\(name) has priority \(constraint.priority), not within 1 to 1000 (P-LAYOUT-05)")
        }
        guard constraint.multiplier.isFinite, constraint.constant.isFinite else {
            throw ProbeFailure(
                "\(name) has multiplier \(constraint.multiplier) and constant \(constraint.constant); both must be finite (P-LAYOUT-05)"
            )
        }
        let items = [first] + (constraint.secondItem.map { [$0] } ?? [])
        for item in items {
            try check(item, in: name, nodes: nodes, tables: &tables)
            try checkGuideKind(of: item, in: name, version: version)
        }
        // P-LAYOUT-01: the layer's view, or a guide the view owns.
        guard items.contains(where: { $0.kind != .other && $0.layerID == layerID }) else {
            throw ProbeFailure("\(name): neither item is layer \(layerID) or one of its layout guides (P-LAYOUT-01)")
        }
        if let earlier = tables.constraints[constraint.id] {
            guard earlier == constraint else {
                throw ProbeFailure(
                    "\(name) differs from the constraint with the same id in an earlier detail (P-LAYOUT-03)"
                )
            }
        } else {
            tables.constraints[constraint.id] = constraint
        }
    }

    /// P-LAYOUT-04: the fields each kind of item has.
    private static func check(
        _ item: LayoutItem,
        in name: String,
        nodes: [UInt64: LayerNode],
        tables: inout Tables
    ) throws {
        func backsView(_ layerID: UInt64) -> Bool { nodes[layerID]?.viewClassName != nil }
        func hasName(_ text: String?) -> Bool { text?.isEmpty == false }
        switch item.kind {
        case .view:
            guard item == LayoutItem(kind: .view, layerID: item.layerID) else {
                throw ProbeFailure("\(name): an item of kind View has fields other than layer_id (P-LAYOUT-04)")
            }
            guard backsView(item.layerID) else {
                throw ProbeFailure(
                    "\(name): an item of kind View has layer \(item.layerID), which is not a view's layer in the hierarchy (P-LAYOUT-04)"
                )
            }
        case .layoutGuide:
            guard item.guideID != 0, hasName(item.className), hasName(item.displayClassName),
                  item.guideFrame != nil
            else {
                throw ProbeFailure(
                    "\(name): an item of kind LayoutGuide needs guide_id, class_name, display_class_name and guide_frame (P-LAYOUT-04)"
                )
            }
            guard backsView(item.layerID) else {
                throw ProbeFailure(
                    "\(name): the owner of layout guide \(item.guideID) is layer \(item.layerID), which is not a view's layer in the hierarchy (P-LAYOUT-04)"
                )
            }
            if let earlier = tables.guides[item.guideID] {
                guard earlier == item else {
                    throw ProbeFailure(
                        "\(name): layout guide \(item.guideID) differs from where it was sent before (P-LAYOUT-03)"
                    )
                }
            } else {
                tables.guides[item.guideID] = item
            }
        case .other:
            guard item.layerID == 0, item.guideID == 0, item.identifier == nil, item.guideFrame == nil,
                  hasName(item.className), hasName(item.displayClassName)
            else {
                throw ProbeFailure(
                    "\(name): an item of kind Other has class_name and display_class_name, and nothing else (P-LAYOUT-04)"
                )
            }
        }
    }

    /// P-LAYOUT-04 (protocol 1.1): a guide's kind is given, of the negotiated version; other
    /// items have none.
    private static func checkGuideKind(of item: LayoutItem, in name: String, version: ProtocolVersion) throws {
        if item.kind != .layoutGuide {
            guard item.guideKind == .unknown else {
                throw ProbeFailure(
                    "\(name): an item of kind \(item.kind) has guide_kind \(item.guideKind) (P-LAYOUT-04)"
                )
            }
            return
        }
        // `Other` stands in for a kind the version does not have, so any version may get it.
        guard item.guideKind == .other || item.guideKind.minorVersion <= version.minor else {
            throw ProbeFailure(
                "\(name): layout guide \(item.guideID) has guide_kind \(item.guideKind), which protocol 1.\(version.minor) does not have (P-LAYOUT-04)"
            )
        }
        if version.minor >= 1, item.guideKind == .unknown {
            throw ProbeFailure("\(name): layout guide \(item.guideID) has no guide_kind (P-LAYOUT-04)")
        }
    }

    /// What a stream's constraints come to, for the probe's report.
    struct Summary: Equatable {
        /// Constraints in all details, each copy counted.
        var total = 0
        /// Details with at least one constraint.
        var layers = 0
        /// Constraints by ID.
        var distinct = 0
        var satisfied = 0
        var unsatisfied = 0
        var unknown = 0
    }

    static func summary(of details: [LayerDetail]) -> Summary {
        var byID: [UInt64: LayoutConstraint] = [:]
        for detail in details {
            for constraint in detail.constraints { byID[constraint.id] = constraint }
        }
        let distinct = Array(byID.values)
        return Summary(
            total: details.reduce(0) { $0 + $1.constraints.count },
            layers: details.filter { !$0.constraints.isEmpty }.count,
            distinct: distinct.count,
            satisfied: distinct.filter { $0.status == .satisfied }.count,
            unsatisfied: distinct.filter { $0.status == .unsatisfied }.count,
            unknown: distinct.filter { $0.status == .unknown }.count
        )
    }
}
