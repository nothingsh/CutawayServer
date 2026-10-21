import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The base class of the tests that read the value of one attribute of a view as the catalog
/// gives it. No server, no connection.
class AttributeValueTestCase: CaptureTestCase {
    var registry = LayerRegistry()
    /// Data sources and delegates are held weakly.
    var retained: [AnyObject] = []

    func reading(_ windows: [UIWindow]) -> AttributeReading {
        AttributeReading(registry: registry, windows: windows)
    }

    func value(
        _ id: String,
        of view: UIView,
        in windows: [UIWindow]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AttributeValue? {
        let groupID = String(id.prefix { $0 != "." })
        let groups = AttributeCatalog.standard.read(view.layer, reading: reading(windows ?? HostWindows.all()))
        let group = try XCTUnwrap(groups.first { $0.id == groupID }, "no group \(groupID)", file: file, line: line)
        let attribute = try XCTUnwrap(
            group.attributes.first { $0.id == id },
            "no attribute \(id)",
            file: file,
            line: line
        )
        return attribute.value
    }

    func string(_ id: String, of view: UIView, file: StaticString = #filePath, line: UInt = #line) throws
        -> String? {
        switch try value(id, of: view, file: file, line: line) {
        case nil: return nil
        case .string(let text): return text
        case let other?:
            XCTFail("\(id) is \(other), not a string", file: file, line: line)
            return nil
        }
    }

    func int(_ id: String, of view: UIView, file: StaticString = #filePath, line: UInt = #line) throws
        -> Int64? {
        switch try value(id, of: view, file: file, line: line) {
        case nil: return nil
        case .int(let number): return number
        case let other?:
            XCTFail("\(id) is \(other), not an integer", file: file, line: line)
            return nil
        }
    }

    func bool(_ id: String, of view: UIView, file: StaticString = #filePath, line: UInt = #line) throws
        -> Bool? {
        switch try value(id, of: view, file: file, line: line) {
        case nil: return nil
        case .bool(let flag): return flag
        case let other?:
            XCTFail("\(id) is \(other), not a Boolean", file: file, line: line)
            return nil
        }
    }

    func references(
        _ id: String,
        of view: UIView,
        in windows: [UIWindow]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [ObjectReference]? {
        switch try value(id, of: view, in: windows, file: file, line: line) {
        case nil: return nil
        case .layerReference(let references): return references
        case let other?:
            XCTFail("\(id) is \(other), not references", file: file, line: line)
            return nil
        }
    }
}
