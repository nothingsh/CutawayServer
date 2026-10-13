import CutawayWire
import Foundation

// The probe's flow: find a server, then check the handshake, the first app state event, the
// app icon, the layer hierarchy, and the screenshots and attributes of every layer.

/// The request IDs of the probe's steps, each used once on its connection (P-REQ-02).
enum ProbeRequestID {
    static let appIcon: UInt32 = 1
    static let hierarchy: UInt32 = 2
    static let layerDetails: UInt32 = 3
    // GetSubtree and SetAttribute on the demo app's screen.
    static let cardSubtree: UInt32 = 4
    static let lengthenText: UInt32 = 5
    static let stackAfterLengthening: UInt32 = 6
    static let restoreText: UInt32 = 7
    static let stackAfterRestoring: UInt32 = 8
    static let setReadOnlyFrame: UInt32 = 9
    static let restoreTextAfterFailure: UInt32 = 10
    // The demo's constraints.
    static let lowerResistance: UInt32 = 11
    static let constraintsLowered: UInt32 = 12
    static let restoreResistance: UInt32 = 13
    static let constraintsRestored: UInt32 = 14
    static let restoreResistanceAfterFailure: UInt32 = 15
}

func check(_ options: Options) throws {
    let server = try findServer(options)
    let app = server.app
    print("connected to \(options.host):\(server.port)")
    print(
        "handshake: \(app.name) (\(app.bundleID)) \(app.appVersion) on \(app.deviceName), "
            + "\(app.osName) \(app.osVersion), server \(app.serverVersion)"
    )

    let state = try Checks.initialState(try server.connection.nextFrame())
    print("app state: \(state)")

    let icon = try request(.getAppIcon, id: ProbeRequestID.appIcon, on: server.connection)
    if let image = try Checks.appIcon(icon, requiresIcon: options.requiresIcon) {
        print("app icon: \(image.pixelWidth)x\(image.pixelHeight) pixels, scale \(image.scale)")
    } else {
        print("app icon: the app has none")
    }

    let (hierarchy, scene) = try checkHierarchy(on: server, options: options)
    try checkLayerDetails(of: hierarchy, scene: scene, on: server, options: options)
}

/// Asks for the hierarchy, prints what it holds, and checks the demo app's screen when asked to:
/// the scene is what the later demo checks work on.
private func checkHierarchy(on server: FoundServer, options: Options) throws -> (Hierarchy, DemoScene?) {
    let hierarchy = try HierarchyChecks.hierarchy(
        try request(.getHierarchy, id: ProbeRequestID.hierarchy, on: server.connection),
        version: server.version
    )
    let windows = hierarchy.nodes.filter { $0.parentID == 0 }.count
    let controllers = hierarchy.nodes.filter { $0.viewControllerClassName != nil }.count
    let references = hierarchy.nodes.reduce(0) { $0 + $1.memberReferences.count }
    print(
        "hierarchy: \(hierarchy.nodes.count) nodes, \(windows) windows, key window \(hierarchy.keyWindowID), "
            + "\(controllers) view controllers, \(references) member references"
    )
    var scene: DemoScene?
    if options.expectDemo {
        scene = try HierarchyChecks.demoScene(hierarchy)
        print("hierarchy: shows the demo app's screen")
    }
    return (hierarchy, scene)
}

/// Streams the details of every layer of `hierarchy`, prints what they hold, and runs the
/// demo app's checks when `scene` is given.
private func checkLayerDetails(
    of hierarchy: Hierarchy,
    scene: DemoScene?,
    on server: FoundServer,
    options: Options
) throws {
    // Both images, the attributes and the constraints of every layer, in the order of the
    // hierarchy.
    let wanted = GetLayerDetails(
        requests: hierarchy.nodes.map {
            LayerDetailRequest(
                layerID: $0.id,
                wantSolo: true,
                wantGroup: true,
                wantAttributes: true,
                wantConstraints: true
            )
        },
        maxTextureDimension: 16384
    )
    let started = Date()
    let frames = try stream(
        .getLayerDetails(wanted),
        id: ProbeRequestID.layerDetails,
        on: server.connection,
        pause: options.slowRead ?? 0
    )
    if let slowRead = options.slowRead {
        print(
            "layer details: read slowly (\(Int(slowRead * 1000)) ms after each chunk) in "
                + String(format: "%.1f s", Date().timeIntervalSince(started))
        )
    }
    let details = try DetailChecks.stream(
        frames,
        answering: ProbeRequestID.layerDetails,
        request: wanted,
        hierarchy: hierarchy,
        version: server.version
    )
    let summary = DetailChecks.summary(of: details, chunks: frames.count - 1)
    print(
        "layer details: \(summary.layers) layers in \(summary.chunks) chunks, \(summary.images) images, "
            + "\(summary.attributeGroups) attribute groups with \(summary.attributes) attributes, "
            + "\(summary.captureFailed) capture failed, \(summary.notFound) not found"
    )
    // P-SET-07: the app may have set them itself, so they are only reported.
    let outside = details.flatMap {
        AttributeChecks.valuesOutsideLimits($0.attributeGroups, name: "layer \($0.layerID)")
    }
    if !outside.isEmpty {
        print(
            "attributes: \(outside.count) values outside their limits, set by the app: \(outside.prefix(3).joined(separator: "; "))"
        )
    }
    let constraints = ConstraintChecks.summary(of: details)
    print(
        "constraints: \(constraints.total) on \(constraints.layers) layers, \(constraints.distinct) distinct: "
            +
            "\(constraints.satisfied) satisfied, \(constraints.unsatisfied) unsatisfied, \(constraints.unknown) unknown"
    )
    if let scene {
        try DetailChecks.demoPixels(
            details,
            hierarchy: hierarchy,
            layers: DetailChecks.DemoLayers(
                card: scene.card,
                shape: scene.badge,
                screen: scene.screen,
                scrollView: scene.scrollView,
                bareLayer: scene.bareLayer
            )
        )
        try AttributeChecks.demo(details, hierarchy: hierarchy, scene: scene)
        print("layer details: show the demo app's screen and its attributes")
        let demo = try ConstraintChecks.demo(
            details,
            screen: scene.screen,
            layoutLabel: scene.layoutLabel,
            box: scene.autoresizingBox
        )
        print(
            "constraints: the label's constraints to the safe area hold, its width == 30 @500 lost, "
                + "and the autoresizing mask's constraints use UIKit's attributes"
        )
        try checkDemoEditing(scene: scene, hierarchy: hierarchy, on: server.connection)
        try checkDemoConstraints(demo, hierarchy: hierarchy, on: server.connection)
    }
}

/// The probe's exit code: 0 when every check passed, 1 when one failed, 2 when the
/// arguments are wrong. `arguments` leave out the program's name.
func run(arguments: [String]) -> Int32 {
    let options: Options
    do {
        options = try Options(arguments: arguments)
    } catch {
        FileHandle.standardError.write(Data("cutaway-probe: \(error)\n\(Options.usage)\n".utf8))
        return 2
    }
    do {
        try check(options)
    } catch {
        FileHandle.standardError.write(Data("cutaway-probe: FAILED: \(error)\n".utf8))
        return 1
    }
    print("cutaway-probe: OK")
    return 0
}
