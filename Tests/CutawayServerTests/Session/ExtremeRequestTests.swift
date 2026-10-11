import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Requests that pass verification but carry extreme values get answers the
/// protocol allows, and the session goes on (S-CONN-15). The capture, the registry and the
/// changes are real; only the connection is fake.
final class ExtremeRequestTests: CaptureTestCase {
    private var harness: LiveSessionHarness!
    private var view: UIView!
    private var label: UILabel!
    /// A layer of its own, a sublayer of the view's.
    private var layer: CALayer!
    /// The requests sent so far, without the cancels, in order.
    private var asked: [Frame] = []
    private var nextSentinelID: UInt32 = 1_000_000

    /// An ID the registry never gave out.
    private static let unassignedID: UInt64 = 10_000_000

    override func setUp() async throws {
        try await super.setUp()
        let window = try makeWindow()
        view = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        view.backgroundColor = .red
        layer = CALayer()
        layer.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        layer.backgroundColor = UIColor.blue.cgColor
        view.layer.addSublayer(layer)
        label = UILabel(frame: CGRect(x: 10, y: 120, width: 200, height: 20))
        label.text = "Label"
        window.addSubview(view)
        window.addSubview(label)
        window.layoutIfNeeded()
        harness = LiveSessionHarness()
        try await harness.handshake()
        asked = []
    }

    override func tearDown() async throws {
        harness = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func id(of layer: CALayer) -> UInt64 {
        harness.registry.register(layer)
    }

    private func details(
        _ requestID: UInt32,
        _ layerIDs: [UInt64],
        images: Bool = false,
        attributes: Bool = false,
        maxTextureDimension: UInt32 = 0
    ) -> Frame {
        Frame(
            requestID: requestID,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: layerIDs.map {
                        LayerDetailRequest(
                            layerID: $0,
                            wantSolo: images,
                            wantGroup: images,
                            wantAttributes: attributes,
                            wantConstraints: attributes
                        )
                    },
                    maxTextureDimension: maxTextureDimension
                )
            )
        )
    }

    private func set(_ requestID: UInt32, _ layerID: UInt64, _ attributeID: String, _ value: AttributeValue?) -> Frame {
        Frame(
            requestID: requestID,
            body: .setAttribute(SetAttribute(layerID: layerID, attributeID: attributeID, value: value))
        )
    }

    /// Sends the frames and a `GetAppIcon` after them, waits for its answer, and returns the
    /// answers to the frames that are not cancels. Answers come in the order of the requests
    /// (P-REQ-06), so once the icon is there, everything before it is too.
    private func exchange(
        _ frames: [Frame],
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [ResponseCheck.Response] {
        nextSentinelID += 1
        let sentinel = nextSentinelID
        let all = frames + [Frame(requestID: sentinel, body: .getAppIcon)]
        harness.receive(all)
        let transport = harness.transport
        try await waitUntil("the answer to request \(sentinel)", timeout: timeout) {
            transport.sent.last?.requestID == sentinel
        }
        await harness.settle()
        let requests = all.filter { frame in
            if case .cancel? = frame.body { return false }
            return true
        }
        asked += requests
        let responses = ResponseCheck.responses(to: asked, in: transport.sent, file: file, line: line)
        let mine = Array(responses.suffix(requests.count))
        if case .appIcon? = mine.last?.frame?.body {
        } else {
            XCTFail("the last answer is not the icon: \(String(describing: mine.last))", file: file, line: line)
        }
        return Array(mine.dropLast())
    }

    /// The connection still works: a detail with an image and attributes comes back, and the
    /// session neither ended nor closed the connection.
    private func assertStillUsable(file: StaticString = #filePath, line: UInt = #line) async throws {
        nextSentinelID += 1
        let responses = try await exchange(
            [details(nextSentinelID, [id(of: view.layer)], images: true, attributes: true)],
            file: file,
            line: line
        )
        let detail = responses.first?.details.first
        XCTAssertEqual(responses.first?.end?.status, .completed, file: file, line: line)
        XCTAssertEqual(detail?.status, .ok, file: file, line: line)
        XCTAssertNotNil(detail?.group, file: file, line: line)
        XCTAssertFalse(detail?.attributeGroups.isEmpty ?? true, file: file, line: line)
        XCTAssertEqual(harness.endedCount, 0, "the session ended", file: file, line: line)
        XCTAssertFalse(harness.transport.isClosed, "the connection was closed", file: file, line: line)
    }

    private func assertError(
        _ response: ResponseCheck.Response?,
        _ code: ErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .error(let error)? = response?.frame?.body else {
            return XCTFail("expected an Error, got \(String(describing: response))", file: file, line: line)
        }
        XCTAssertEqual(error.code, code, error.message, file: file, line: line)
    }

    /// The value of an attribute in a `SetAttributeResult` or a detail.
    private func value(of attributeID: String, in groups: [AttributeGroup]) -> AttributeValue? {
        groups.lazy.flatMap(\.attributes).first { $0.id == attributeID }?.value
    }

    // MARK: - GetLayerDetails

    func test_S_CONN_15_aDetailsRequestWithAHundredThousandLayers() async throws {
        // Known layers again and again, 0, IDs never given out, the largest ID; nothing wanted
        // but the status.
        let known = [id(of: view.layer), id(of: label.layer), id(of: layer)]
        let cycle = known + [0, Self.unassignedID, .max]
        let layerIDs = (0..<100_000).map { cycle[$0 % cycle.count] }
        let start = Date()
        let responses = try await exchange([details(1, layerIDs)], timeout: 120)
        print("MEASURE 100000 details in \(Date().timeIntervalSince(start)) seconds")

        let stream = try XCTUnwrap(responses.first)
        XCTAssertEqual(stream.end, StreamEnd(status: .completed, chunkCount: 100_000))
        let statuses = stream.details.map(\.status)
        let expected = layerIDs.map { known.contains($0) ? DetailStatus.ok : .layerNotFound }
        XCTAssertTrue(statuses == expected, "the statuses do not follow the request")
        try await assertStillUsable()
    }

    func test_S_CONN_15_theSameLayerManyTimesInOneRequest() async throws {
        let viewID = id(of: view.layer)
        let responses = try await exchange([
            details(1, Array(repeating: viewID, count: 5), images: true, attributes: true)
        ])
        let reported = try XCTUnwrap(responses.first).details
        XCTAssertEqual(reported.count, 5)
        XCTAssertEqual(reported.first?.status, .ok)
        XCTAssertNotNil(reported.first?.group)
        for detail in reported {
            XCTAssertEqual(detail, reported.first)
        }
        try await assertStillUsable()
    }

    func test_S_CONN_15_extremeMaxTextureDimensions() async throws {
        // The view is 100 points square and has a sublayer, so both images come.
        let viewID = id(of: view.layer)
        let screenScale = Float(UIScreen.main.scale)
        let fullSide = UInt32((100 * screenScale).rounded(.up))
        let responses = try await exchange([
            details(1, [viewID], images: true, maxTextureDimension: 0),
            details(2, [viewID], images: true, maxTextureDimension: .max),
            details(3, [viewID], images: true, maxTextureDimension: 1)
        ])
        XCTAssertEqual(responses.count, 3)
        for response in responses.prefix(2) {
            // P-DET-05: 0 is no limit, and no layer reaches UInt32.max.
            let detail = try XCTUnwrap(response.details.first)
            XCTAssertEqual(detail.status, .ok)
            for image in [detail.solo, detail.group] {
                XCTAssertEqual(image?.pixelWidth, fullSide)
                XCTAssertEqual(image?.pixelHeight, fullSide)
                XCTAssertEqual(image?.scale, screenScale)
            }
        }
        // P-DET-05: no side longer than 1, the scale smaller by as much.
        let tiny = try XCTUnwrap(responses[2].details.first)
        XCTAssertEqual(tiny.status, .ok)
        for image in [tiny.solo, tiny.group] {
            let image = try XCTUnwrap(image)
            XCTAssertLessThanOrEqual(image.pixelWidth, 1)
            XCTAssertLessThanOrEqual(image.pixelHeight, 1)
            XCTAssertLessThan(image.scale, screenScale)
        }
        try await assertStillUsable()
    }

    // MARK: - SetAttribute

    func test_S_CONN_15_nonFiniteValuesAreRejected() async throws {
        let viewID = id(of: view.layer)
        let layerID = id(of: layer)
        let bounds = layer.bounds
        let margins = view.layoutMargins
        let responses = try await exchange([
            set(1, viewID, "layer.opacity", .double(.nan)),
            set(2, viewID, "layer.opacity", .double(.infinity)),
            set(3, viewID, "layer.opacity", .double(-.infinity)),
            set(4, layerID, "layer.bounds", .rect(WireRect(x: 0, y: 0, width: .nan, height: 10))),
            set(5, layerID, "layer.bounds", .rect(WireRect(x: -.infinity, y: 0, width: 10, height: 10))),
            set(6, viewID, "view.layoutMargins", .insets(WireInsets(top: .infinity, left: 0, bottom: 0, right: 0)))
        ])
        XCTAssertEqual(responses.count, 6)
        for response in responses {
            assertError(response, .invalidAttributeValue)
        }
        // P-SET-03: nothing changed.
        XCTAssertEqual(view.layer.opacity, 1)
        XCTAssertEqual(layer.bounds, bounds)
        XCTAssertEqual(view.layoutMargins, margins)
        try await assertStillUsable()
    }

    func test_S_CONN_15_longStrings() async throws {
        let labelID = id(of: label.layer)
        // A mebibyte of text, with characters outside ASCII in it.
        let piece = "Cutaway ✓ 🔍 é "
        let text = String(repeating: piece, count: 1_048_576 / piece.utf8.count + 1)
        XCTAssertGreaterThanOrEqual(text.utf8.count, 1_048_576)
        let start = Date()
        let responses = try await exchange([
            set(1, labelID, "label.text", .string(text)),
            set(2, labelID, "label.fontName", .string(text))
        ])
        print("MEASURE \(text.utf8.count) bytes of text set in \(Date().timeIntervalSince(start)) seconds")
        guard case .setAttributeResult(let result)? = responses.first?.frame?.body else {
            return XCTFail("expected a SetAttributeResult, got \(String(describing: responses.first))")
        }
        XCTAssertEqual(value(of: "label.text", in: result.attributeGroups), .string(text))
        XCTAssertEqual(label.text, text)
        // No font has that name (P-SET-03).
        assertError(responses.last, .invalidAttributeValue)
        try await assertStillUsable()
    }

    func test_S_CONN_15_valuesOfTheWrongKindAreRejected() async throws {
        let viewID = id(of: view.layer)
        let responses = try await exchange([
            set(1, viewID, "layer.opacity", .string("1")),
            set(2, viewID, "view.tag", .double(1)),
            set(3, viewID, "layer.opacity", nil),
            set(4, viewID, "view.contentMode", .enumeration(value: 1_000_000, cases: [], caseName: "", caseValues: []))
        ])
        XCTAssertEqual(responses.count, 4)
        for response in responses {
            assertError(response, .invalidAttributeValue)
        }
        XCTAssertEqual(view.layer.opacity, 1)
        XCTAssertEqual(view.tag, 0)
        try await assertStillUsable()
    }

    func test_S_CONN_15_attributesAndLayersThatDoNotExist() async throws {
        let viewID = id(of: view.layer)
        let responses = try await exchange([
            set(1, viewID, "no.such.attribute", .double(1)),
            set(2, viewID, "", .double(1)),
            set(3, viewID, "layer.frame", .rect(WireRect(x: 0, y: 0, width: 1, height: 1))),
            set(4, 0, "layer.opacity", .double(0.5)),
            set(5, Self.unassignedID, "layer.opacity", .double(0.5))
        ])
        XCTAssertEqual(responses.count, 5)
        for response in responses.prefix(3) {
            assertError(response, .attributeNotEditable)
        }
        for response in responses.suffix(2) {
            assertError(response, .layerNotFound)
        }
        try await assertStillUsable()
    }

    func test_S_CONN_15_extremeFiniteValues() async throws {
        // Not in the requirement's list: the largest finite numbers and the ends of Int64. Each
        // change may be made or refused; either way the answers follow the protocol, and the
        // layers can still be read.
        let viewID = id(of: view.layer)
        let layerID = id(of: layer)
        let huge = Double.greatestFiniteMagnitude
        let changes = [
            set(1, layerID, "layer.bounds", .rect(WireRect(x: huge, y: -huge, width: huge, height: huge))),
            set(2, layerID, "layer.position", .point(WirePoint(x: -huge, y: huge))),
            set(3, layerID, "layer.zPosition", .double(-huge)),
            set(4, viewID, "layer.cornerRadius", .double(huge)),
            set(5, viewID, "layer.borderWidth", .double(huge)),
            set(6, viewID, "layer.shadowRadius", .double(huge)),
            set(7, viewID, "view.tag", .int(.min)),
            set(8, viewID, "view.tag", .int(.max)),
            set(9, viewID, "view.layoutMargins", .insets(WireInsets(top: huge, left: -huge, bottom: huge, right: 0)))
        ]
        let reads = [
            details(10, [viewID, layerID], images: true, attributes: true),
            Frame(requestID: 11, body: .getHierarchy),
            Frame(requestID: 12, body: .getSubtree(rootID: viewID))
        ]
        let responses = try await exchange(changes + reads, timeout: 60)
        XCTAssertEqual(responses.count, changes.count + reads.count)
        for (change, response) in zip(changes, responses) {
            switch response.frame?.body {
            case .setAttributeResult: break
            case .error(let error):
                XCTAssertEqual(error.code, .invalidAttributeValue, "\(change): \(error.message)")
            default:
                XCTFail("\(change) got \(String(describing: response))")
            }
        }
        XCTAssertEqual(view.tag, Int(Int64.max))
        let stream = responses[changes.count]
        XCTAssertEqual(stream.end?.status, .completed)
        for detail in stream.details {
            XCTAssertTrue([.ok, .captureFailed].contains(detail.status), "\(detail.layerID): \(detail.status)")
        }
        for response in responses.suffix(2) {
            guard case .hierarchy? = response.frame?.body else {
                return XCTFail("expected a Hierarchy, got \(response)")
            }
        }
        try await assertStillUsable()
    }

    // MARK: - GetSubtree

    func test_S_CONN_15_subtreesOfLayersThatDoNotExist() async throws {
        let responses = try await exchange([
            Frame(requestID: 1, body: .getSubtree(rootID: 0)),
            Frame(requestID: 2, body: .getSubtree(rootID: Self.unassignedID)),
            Frame(requestID: 3, body: .getSubtree(rootID: .max))
        ])
        XCTAssertEqual(responses.count, 3)
        for response in responses {
            assertError(response, .layerNotFound)
        }
        try await assertStillUsable()
    }

    // MARK: - Cancel and request IDs

    func test_S_CONN_15_cancelsThatNameNothingAreIgnored() async throws {
        let viewID = id(of: view.layer)
        // Request 1 is an ordinary request, request 2 a stream that is over by the time the
        // cancels arrive.
        _ = try await exchange([Frame(requestID: 1, body: .getHierarchy), details(2, [viewID])])
        let responses = try await exchange([
            Frame(requestID: 3, body: .cancel(targetRequestID: 424_242)),
            Frame(requestID: 4, body: .cancel(targetRequestID: 0)),
            Frame(requestID: 5, body: .cancel(targetRequestID: 1)),
            Frame(requestID: 6, body: .cancel(targetRequestID: 2)),
            Frame(requestID: 7, body: .cancel(targetRequestID: .max)),
            details(8, [viewID, viewID])
        ])
        // P-REQ-04: no answers to the cancels; the stream after them is untouched.
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.end, StreamEnd(status: .completed, chunkCount: 2))
        try await assertStillUsable()
    }

    func test_S_CONN_15_requestIDZeroAndRepeatedIDs() async throws {
        let viewID = id(of: view.layer)
        // P-REQ-01: the server does not check request IDs and answers with the one it got.
        let requests = [
            Frame(requestID: 0, body: .getHierarchy),
            details(0, [viewID]),
            Frame(requestID: 5, body: .getHierarchy),
            details(5, [viewID]),
            set(5, viewID, "view.tag", .int(3)),
            Frame(requestID: 0, body: .getSubtree(rootID: viewID))
        ]
        let responses = try await exchange(requests)
        XCTAssertEqual(responses.count, requests.count)
        guard case .hierarchy? = responses[0].frame?.body else { return XCTFail("\(responses[0])") }
        XCTAssertEqual(responses[1].end?.status, .completed)
        guard case .hierarchy? = responses[2].frame?.body else { return XCTFail("\(responses[2])") }
        XCTAssertEqual(responses[3].end?.status, .completed)
        guard case .setAttributeResult? = responses[4].frame?.body else { return XCTFail("\(responses[4])") }
        guard case .hierarchy? = responses[5].frame?.body else { return XCTFail("\(responses[5])") }
        XCTAssertEqual(view.tag, 3)
        try await assertStillUsable()
    }

    func test_S_CONN_15_cancelWithRepeatedIDs() async throws {
        let viewID = id(of: view.layer)
        let many = Array(repeating: viewID, count: 2_000)
        // Two streams with the ID 7. The cancel arrives while the first is in hand: it ends that
        // one, and the second runs to its end (P-REQ-04).
        let first = try await exchange([
            details(7, many),
            details(7, [viewID, viewID, viewID]),
            Frame(requestID: 8, body: .cancel(targetRequestID: 7))
        ])
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first[0].end?.status, .cancelled)
        XCTAssertEqual(first[1].end, StreamEnd(status: .completed, chunkCount: 3))

        // Two cancels for two streams with the same ID: both end as cancelled.
        let second = try await exchange([
            details(7, many),
            details(7, [viewID, viewID, viewID]),
            Frame(requestID: 8, body: .cancel(targetRequestID: 7)),
            Frame(requestID: 9, body: .cancel(targetRequestID: 7))
        ])
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(second[0].end?.status, .cancelled)
        XCTAssertEqual(second[1].end?.status, .cancelled)
        try await assertStillUsable()
    }
}
