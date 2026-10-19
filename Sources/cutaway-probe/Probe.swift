import CutawayWire
import Foundation

// The probe's flow: find a server, then check the handshake, the first app state event, the
// app icon, the layer hierarchy, the screenshots and attributes of every layer, and the
// environment.

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
    // The environment (protocol 1.2).
    static let environment: UInt32 = 16
    static let darkAppearance: UInt32 = 17
    static let removeOverrides: UInt32 = 18
    static let removeOverridesAfterFailure: UInt32 = 19
}

/// What `--expect-demo` checks: the demo app's main screen, or its Lists page when that is open.
enum DemoPage {
    case screen(DemoScene)
    case lists(DemoListsScene)
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

    let (hierarchy, page) = try checkHierarchy(on: server, options: options)
    try checkLayerDetails(of: hierarchy, page: page, on: server, options: options)

    let environment = try EnvironmentChecks.environment(
        try request(.getEnvironment, id: ProbeRequestID.environment, on: server.connection),
        answering: "GetEnvironment"
    )
    print(
        "environment: \(environment.overridable.count) kinds can be overridden; the appearance is "
            + "\(environment.current.userInterfaceStyle)"
    )
    if case .lists? = page { try checkDemoEnvironment(environment, on: server.connection) }
}

/// Asks for the hierarchy, prints what it holds, and checks the demo app's screen when asked to:
/// the page is what the later demo checks work on.
private func checkHierarchy(on server: FoundServer, options: Options) throws -> (Hierarchy, DemoPage?) {
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
    guard options.expectDemo else { return (hierarchy, nil) }
    if DemoListsScene.isShown(in: hierarchy) {
        let lists = try DemoListsScene(hierarchy)
        print("hierarchy: shows the demo app's Lists page; checking it instead of the main screen")
        return (hierarchy, .lists(lists))
    }
    let scene = try HierarchyChecks.demoScene(hierarchy)
    print("hierarchy: shows the demo app's screen")
    return (hierarchy, .screen(scene))
}

/// Streams the details of every layer of `hierarchy`, prints what they hold, and runs the
/// demo app's checks when `page` is given.
private func checkLayerDetails(
    of hierarchy: Hierarchy,
    page: DemoPage?,
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
    reportAttributeNotes(of: details)
    let constraints = ConstraintChecks.summary(of: details)
    print(
        "constraints: \(constraints.total) on \(constraints.layers) layers, \(constraints.distinct) distinct: "
            +
            "\(constraints.satisfied) satisfied, \(constraints.unsatisfied) unsatisfied, \(constraints.unknown) unknown"
    )
    switch page {
    case nil:
        return
    case .lists(let lists):
        try AttributeChecks.demoLists(details, hierarchy: hierarchy, scene: lists)
        print("layer details: show the demo app's Lists page and the attributes of protocol 1.2")
    case .screen(let scene):
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

/// What is only reported about attributes, not counted as a failure.
private func reportAttributeNotes(of details: [LayerDetail]) {
    // P-SET-07: the app may have set them itself, so they are only reported.
    let outside = details.flatMap {
        AttributeChecks.valuesOutsideLimits($0.attributeGroups, name: "layer \($0.layerID)")
    }
    if !outside.isEmpty {
        print(
            "attributes: \(outside.count) values outside their limits, set by the app: \(outside.prefix(3).joined(separator: "; "))"
        )
    }
}
