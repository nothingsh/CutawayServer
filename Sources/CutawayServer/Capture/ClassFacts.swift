#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation
import ObjectiveC

/// Where a class comes from (PROTOCOL.md, P-HIER-16): the app's when the image that defines it
/// lies in the `.app` bundle that contains the host process, the system's otherwise. Judged by
/// the image, not by the name.
@MainActor
enum ClassOrigin {
    /// The `.app` bundle of the host process, symbolic links resolved, with a trailing `/`.
    static let appBundlePrefix = prefix(of: appBundle(containing: Bundle.main.bundleURL))

    /// The nearest directory named `*.app` at or above `url`: the main bundle itself in an
    /// app, the app that contains it in an extension (`X.app/PlugIns/Y.appex`). `url` itself
    /// when there is none.
    nonisolated static func appBundle(containing url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "app" { return candidate }
            candidate.deleteLastPathComponent()
        }
        return url
    }

    nonisolated static func prefix(of directory: URL) -> String {
        directory.resolvingSymlinksInPath().path + "/"
    }

    /// The origin of each image met so far: there are few images, and resolving a path is not
    /// free.
    private static var originsByImage: [String: Origin] = [:]

    /// A class made at runtime has no image of its own (a KVO subclass, for one): it takes the
    /// origin of the nearest superclass that has one.
    static func origin(of type: AnyClass, appBundlePrefix: String = appBundlePrefix) -> Origin {
        var current: AnyClass? = type
        while let candidate = current {
            if let name = class_getImageName(candidate) {
                return origin(ofImage: String(cString: name), appBundlePrefix: appBundlePrefix)
            }
            current = class_getSuperclass(candidate)
        }
        return .system
    }

    private static func origin(ofImage path: String, appBundlePrefix: String) -> Origin {
        let key = appBundlePrefix + "\u{0}" + path
        if let known = originsByImage[key] { return known }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let found: Origin = resolved.hasPrefix(appBundlePrefix) ? .app : .system
        originsByImage[key] = found
        return found
    }
}

/// The nearest class of the protocol's tables (PROTOCOL.md, P-HIER-17), among the entries
/// that a peer working at a given version knows.
@MainActor
struct KnownBaseClasses {
    private let views: [ObjectIdentifier: String]
    private let layers: [ObjectIdentifier: String]
    private let knowsHostingView: Bool

    init(version: ProtocolVersion) {
        func classes(_ entries: [KnownClasses.Entry]) -> [ObjectIdentifier: String] {
            // A class of a framework the app does not link is not there, and matches nothing.
            var found: [ObjectIdentifier: String] = [:]
            for name in KnownClasses.names(of: entries, at: version) {
                if let type = NSClassFromString(name) { found[ObjectIdentifier(type)] = name }
            }
            return found
        }
        views = classes(KnownClasses.views)
        layers = classes(KnownClasses.layers)
        knowsHostingView = KnownClasses.names(of: KnownClasses.views, at: version).contains(KnownClasses.hostingView)
    }

    /// Walking up from `type`, the first class of the view table, or a view SwiftUI hosts its
    /// content in.
    func viewName(of type: AnyClass) -> String? {
        firstMatch(from: type) { candidate in
            views[ObjectIdentifier(candidate)]
                ?? (knowsHostingView && Self.isHostingView(candidate) ? KnownClasses.hostingView : nil)
        }
    }

    /// Walking up from `type`, the first class of the layer table.
    func layerName(of type: AnyClass) -> String? {
        firstMatch(from: type) { layers[ObjectIdentifier($0)] }
    }

    private func firstMatch(from type: AnyClass, _ match: (AnyClass) -> String?) -> String? {
        var current: AnyClass? = type
        while let candidate = current {
            if let name = match(candidate) { return name }
            current = class_getSuperclass(candidate)
        }
        return nil
    }

    /// SwiftUI's generic `_UIHostingView<Content>`, which the root view of a
    /// `UIHostingController` is, and the content view of a `UIHostingConfiguration` inherits
    /// from. A private class: matched by its mangled name, which holds the module.
    static func isHostingView(_ type: AnyClass) -> Bool {
        NSStringFromClass(type).hasPrefix("_TtGC7SwiftUI14_UIHostingView")
    }
}

/// The origins and nearest known classes of the classes met in one capture, each worked out
/// once: a hierarchy has many layers of few classes.
@MainActor
struct ClassFactsCache {
    private let bases: KnownBaseClasses
    private var origins: [ObjectIdentifier: Origin] = [:]
    private var viewBases: [ObjectIdentifier: String?] = [:]
    private var layerBases: [ObjectIdentifier: String?] = [:]

    init(version: ProtocolVersion) {
        bases = KnownBaseClasses(version: version)
    }

    mutating func origin(of type: AnyClass) -> Origin {
        let key = ObjectIdentifier(type)
        if let known = origins[key] { return known }
        let found = ClassOrigin.origin(of: type)
        origins[key] = found
        return found
    }

    mutating func viewBaseName(of type: AnyClass) -> String? {
        let key = ObjectIdentifier(type)
        if let known = viewBases[key] { return known }
        let found = bases.viewName(of: type)
        viewBases[key] = found
        return found
    }

    mutating func layerBaseName(of type: AnyClass) -> String? {
        let key = ObjectIdentifier(type)
        if let known = layerBases[key] { return known }
        let found = bases.layerName(of: type)
        layerBases[key] = found
        return found
    }
}
#endif
