import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Reports raw attribute values that no protocol version names.
private final class UnnamedAttributeConstraint: NSLayoutConstraint {
    var first = NSLayoutConstraint.Attribute(rawValue: 99)!
    var second = NSLayoutConstraint.Attribute(rawValue: 34)!
    override var firstAttribute: NSLayoutConstraint.Attribute { first }
    override var secondAttribute: NSLayoutConstraint.Attribute { second }
}

/// The attributes of UIKit's autoresizing mask constraints
/// (S-LAYOUT-05; PROTOCOL.md, P-LAYOUT-07, P-LAYOUT-08). No server, no
/// connection.
final class AutoresizingConstraintTests: CaptureTestCase {
    private let registry = LayerRegistry()
    private static let autoresizing = "NSAutoresizingMaskLayoutConstraint"

    /// Views with a frame and an autoresizing mask, each placed against by a view with
    /// constraints, so that UIKit turns its mask into constraints.
    private struct Scene {
        let root: UIView
        let framed: [UIView]
    }

    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let masks: [UIView.AutoresizingMask] = [
            [],
            .flexibleLeftMargin,
            .flexibleWidth,
            [.flexibleRightMargin, .flexibleBottomMargin],
            // None of the four above gives `maxY`.
            .flexibleHeight
        ]
        var framed: [UIView] = []
        for (index, mask) in masks.enumerated() {
            let view = UIView(frame: CGRect(x: 10 + CGFloat(index) * 50, y: 100, width: 40, height: 40))
            view.autoresizingMask = mask
            root.addSubview(view)
            let follower = UIView()
            follower.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(follower)
            NSLayoutConstraint.activate([
                follower.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                follower.topAnchor.constraint(equalTo: view.bottomAnchor, constant: 5),
                follower.widthAnchor.constraint(equalToConstant: 10),
                follower.heightAnchor.constraint(equalToConstant: 10)
            ])
            framed.append(view)
        }
        window.layoutIfNeeded()
        return Scene(root: root, framed: framed)
    }

    /// The autoresizing constraints of `view`, each with what is sent for it.
    private func autoresizingConstraints(
        of view: UIView,
        in root: UIView
    ) -> [(object: NSLayoutConstraint, wire: LayoutConstraint)] {
        let captured = ConstraintCapture.constraints(of: view, registry: registry)
        return root.constraints.filter {
            NSStringFromClass(type(of: $0)) == Self.autoresizing
                && ($0.firstItem === view || $0.secondItem === view)
        }.compactMap { object in
            captured.first { $0.id == registry.register(object) }.map { (object, $0) }
        }
    }

    private static let named: Set<UInt8> = [32, 33, 36, 37]

    func test_S_LAYOUT_05_autoresizingConstraintsKeepTheirAttributes() throws {
        let scene = try makeScene()
        var seen = Set<UInt8>()
        for view in scene.framed {
            let pairs = autoresizingConstraints(of: view, in: scene.root)
            XCTAssertEqual(pairs.count, 4, "\(view.autoresizingMask)")
            for (object, wire) in pairs {
                let name = "\(view.autoresizingMask): \(object)"
                XCTAssertEqual(wire.className, Self.autoresizing, name)
                XCTAssertEqual(Int(wire.firstAttribute.rawValue), object.firstAttribute.rawValue, name)
                if object.secondItem == nil {
                    XCTAssertEqual(wire.secondAttribute, .notAnAttribute, name)
                } else {
                    XCTAssertEqual(Int(wire.secondAttribute.rawValue), object.secondAttribute.rawValue, name)
                }
                seen.formUnion(
                    [wire.firstAttribute.rawValue, wire.secondAttribute.rawValue].filter(Self.named.contains)
                )
            }
            // Every constraint of the view, not only UIKit's: a first attribute, and a second one
            // exactly when there is a second item.
            for constraint in ConstraintCapture.constraints(of: view, registry: registry) {
                let name = "\(view.autoresizingMask): \(constraint.id)"
                XCTAssertNotEqual(constraint.firstAttribute, .notAnAttribute, name)
                XCTAssertEqual(constraint.secondItem == nil, constraint.secondAttribute == .notAnAttribute, name)
            }
        }
        XCTAssertEqual(seen, Self.named)
        // The flexible left margin is written from the superview's side.
        let fromSuperview = try XCTUnwrap(
            autoresizingConstraints(of: scene.framed[1], in: scene.root).first {
                $0.wire.secondAttribute == .maxX
            }
        )
        XCTAssertEqual(fromSuperview.wire.firstItem?.layerID, registry.register(scene.root.layer))
        XCTAssertEqual(fromSuperview.wire.firstAttribute, .width)
        XCTAssertEqual(fromSuperview.wire.secondItem?.layerID, registry.register(scene.framed[1].layer))
    }

    func test_S_LAYOUT_05_constraintsOnTheseAttributesAreUnknown() throws {
        let scene = try makeScene()
        for view in scene.framed {
            for (object, wire) in autoresizingConstraints(of: view, in: scene.root) {
                let name = "\(view.autoresizingMask): \(object)"
                if Self.named.contains(wire.firstAttribute.rawValue)
                    || Self.named.contains(wire.secondAttribute.rawValue) {
                    XCTAssertEqual(wire.status, .unknown, name)
                } else {
                    // A width or a height of its own is still judged (S-LAYOUT-04).
                    XCTAssertEqual(wire.secondItem, nil, name)
                    XCTAssertEqual(wire.status, .satisfied, name)
                }
            }
        }
    }

    func test_S_LAYOUT_05_unnamedRawValuesAreNotAnAttribute() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        window.addSubview(view)
        let constraint = UnnamedAttributeConstraint(
            item: view,
            attribute: .left,
            relatedBy: .greaterThanOrEqual,
            toItem: window,
            attribute: .left,
            multiplier: 2,
            constant: 7
        )
        constraint.priority = .defaultHigh
        XCTAssertEqual(constraint.firstAttribute.rawValue, 99)
        XCTAssertEqual(constraint.secondAttribute.rawValue, 34)

        let wire = ConstraintCapture.wireConstraint(constraint, registry: registry, screenScale: 2)
        XCTAssertEqual(
            wire,
            LayoutConstraint(
                id: registry.register(constraint),
                className: NSStringFromClass(UnnamedAttributeConstraint.self),
                firstItem: LayoutItem(kind: .view, layerID: registry.register(view.layer)),
                firstAttribute: .notAnAttribute,
                relation: .greaterThanOrEqual,
                secondItem: LayoutItem(kind: .view, layerID: registry.register(window.layer)),
                secondAttribute: .notAnAttribute,
                multiplier: 2,
                constant: 7,
                priority: 750,
                status: .unknown
            )
        )
    }
}
