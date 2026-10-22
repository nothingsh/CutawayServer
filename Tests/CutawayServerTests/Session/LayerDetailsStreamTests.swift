import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// What a stream reported. Filled on the stream's queue, read by the test.
private final class StreamLog: @unchecked Sendable {
    private let lock = NSLock()
    private var reported: [LayerDetail] = []
    private var completions = 0

    func add(_ detail: LayerDetail) {
        lock.lock()
        reported.append(detail)
        lock.unlock()
    }

    func complete() {
        lock.lock()
        completions += 1
        lock.unlock()
    }

    var details: [LayerDetail] {
        lock.lock()
        defer { lock.unlock() }
        return reported
    }

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions
    }
}

/// What happened on the main thread while a stream ran. Written there, read by the test.
private final class MainThreadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedIDs: [UInt64] = []
    private var turnsAtCaptures: [Int] = []
    private var loggedEvents: [String] = []
    private var turnCount = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Notes that a layer is being captured; returns how many were captured before it.
    @discardableResult
    func noteCapture(of layerID: UInt64) -> Int {
        locked {
            capturedIDs.append(layerID)
            turnsAtCaptures.append(turnCount)
            loggedEvents.append("capture \(capturedIDs.count - 1)")
            return capturedIDs.count - 1
        }
    }

    func noteTurn() {
        locked { turnCount += 1 }
    }

    func note(_ event: String) {
        locked { loggedEvents.append(event) }
    }

    /// Which layers were captured, in order.
    var captured: [UInt64] { locked { capturedIDs } }
    /// How many turns the main run loop had begun at each capture.
    var turnsAtCapture: [Int] { locked { turnsAtCaptures } }
    /// Captures and the other work on the main queue, in the order they ran.
    var events: [String] { locked { loggedEvents } }
}

/// A pipeline whose compressions are noted in `main` once they are done.
private struct NotingPipeline: DetailPipeline {
    let base: HostAccess
    let main: MainThreadLog

    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        version: ProtocolVersion,
        memo: RequestMemo,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (CapturedDetail?) -> Void
    ) {
        base.captureDetail(
            request,
            maxTextureDimension: maxTextureDimension,
            version: version,
            memo: memo,
            stopFlag: stopFlag,
            then: answer
        )
    }

    func encodeDetail(
        _ detail: CapturedDetail,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (LayerDetail) -> Void
    ) {
        let main = self.main
        base.encodeDetail(detail, stopFlag: stopFlag) { encoded in
            main.note("compress")
            answer(encoded)
        }
    }
}

/// One stream of layer details with the real capture and the real compressor,
/// on queues of its own. No server, no connection.
final class LayerDetailsStreamTests: CaptureTestCase {
    private let queue = DispatchQueue(label: "dev.cutaway.tests.stream")
    private let encodeQueue = DispatchQueue(label: "dev.cutaway.tests.stream.encode")
    private let registry = LayerRegistry()
    /// A stream lives as long as its owner keeps it: in the server that is the session.
    private var streams: [LayerDetailsStream] = []
    /// The delegates of the streams, kept alive for them: a stream holds its delegate weakly.
    private var observers: [StreamObserver] = []

    /// A window with `count` views of 20 x 20 points; returns their layers' IDs.
    private func makeLayers(_ count: Int) throws -> [UInt64] {
        let window = try makeWindow()
        return (0..<count).map { index in
            let view = colorView(
                CGRect(x: index * 20, y: 0, width: 20, height: 20),
                red: 1,
                green: 0,
                blue: 0
            )
            window.addSubview(view)
            return registry.register(view.layer)
        }
    }

    private func request(_ layerIDs: [UInt64]) -> GetLayerDetails {
        GetLayerDetails(
            requests: layerIDs.map {
                LayerDetailRequest(layerID: $0, wantSolo: false, wantGroup: true, wantAttributes: false)
            },
            maxTextureDimension: 0
        )
    }

    /// The host a real session gets, on this test's queues, with the host app's work replaced
    /// as `configure` says.
    private func liveHost(_ configure: (inout TestHostApp) -> Void = { _ in }) -> HostAccess {
        var app = TestHostApp()
        configure(&app)
        return HostAccess(app: app, registry: registry, queue: queue, encodeQueue: encodeQueue)
    }

    /// Creates a stream that reports into `log`, and starts it on its queue. The limit is a real
    /// session's unless the test gives one.
    @discardableResult
    private func start(
        _ request: GetLayerDetails,
        host: any DetailPipeline,
        outstandingByteLimit: Int = ServerConfiguration().outstandingByteLimit,
        log: StreamLog,
        unsent: UnsentBytes? = nil
    ) -> LayerDetailsStream {
        let observer = StreamObserver(log: log, unsent: unsent)
        let stream = LayerDetailsStream(
            request: request,
            version: .current,
            pipeline: host,
            outstandingByteLimit: outstandingByteLimit,
            delegate: observer
        )
        observers.append(observer)
        streams.append(stream)
        queue.async { stream.start() }
        return stream
    }

    /// Keeps the compressor busy until the returned semaphore is signalled.
    private func holdCompressor() -> DispatchSemaphore {
        let gate = DispatchSemaphore(value: 0)
        encodeQueue.async { gate.wait() }
        return gate
    }

    /// Lets everything under way come to rest: a capture, its compression and the report
    /// each take a turn of one of the three queues. Leave the compressor out while it is held.
    private func settle(compressor: Bool = true) async {
        for _ in 0..<4 {
            await drain(queue)
            await drain(.main)
            await drain(queue)
            if compressor { await drain(encodeQueue) }
            await drain(queue)
        }
    }

    // MARK: - S-SHOT-06

    func test_S_SHOT_06_everyRequestIsReportedOnceInOrder() async throws {
        let ids = try makeLayers(4)
        let window = try makeWindow()
        let empty = UIView(frame: .zero)
        window.addSubview(empty)
        let emptyID = registry.register(empty.layer)
        // Known layers, one that does not exist, one that cannot be captured, one asked twice.
        let wanted = [ids[2], 9999, ids[0], emptyID, ids[2], ids[3], ids[1]]
        let log = StreamLog()

        start(request(wanted), host: liveHost(), log: log)
        try await waitUntil("the stream to complete") { log.completedCount == 1 }
        await settle()

        XCTAssertEqual(log.details.map(\.layerID), wanted)
        XCTAssertEqual(
            log.details.map(\.status),
            [.ok, .layerNotFound, .ok, .captureFailed, .ok, .ok, .ok]
        )
        XCTAssertEqual(log.completedCount, 1)
        for detail in log.details where detail.status == .ok {
            let image = try XCTUnwrap(detail.group)
            // 20 points at the screen's scale.
            XCTAssertEqual(Double(image.pixelWidth), 20 * Double(image.scale), accuracy: 1)
            XCTAssertNil(detail.solo)
        }
        XCTAssertEqual(log.details[0], log.details[4], "the same layer asked twice gives the same detail")
    }

    // MARK: - S-SHOT-07

    func test_S_SHOT_07_noCaptureStartsAfterStop() async throws {
        let ids = try makeLayers(6)
        let log = StreamLog()
        let main = MainThreadLog()
        let queue = self.queue
        // The compressor is held, so that the stream's state at the stop is known: two layers
        // captured, none reported.
        let gate = holdCompressor()
        defer { gate.signal() }
        let box = StreamBox()
        let host = liveHost { app in
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                let detail = capture(request, limit, context, stopFlag)
                if detail != nil { main.noteCapture(of: request.layerID) }
                // The cancel arrives while the second layer is on the main thread.
                if main.captured.count == 2 { queue.sync { box.stream?.stop() } }
                return detail
            }
        }

        let stream = start(request(ids), host: host, log: log)
        queue.sync { box.stream = stream }
        try await waitUntil("two captures") { main.captured.count >= 2 }
        gate.signal()
        await settle()

        XCTAssertEqual(main.captured, Array(ids[0..<2]), "a layer was captured after the stream was stopped")
        XCTAssertEqual(log.details, [], "a detail was reported after the stream was stopped")
        XCTAssertEqual(log.completedCount, 0)
    }

    // MARK: - S-SHOT-09

    func test_S_SHOT_09_theMainThreadNeverWaitsForTheCompressor() async throws {
        let ids = try makeLayers(5)
        let log = StreamLog()
        let main = MainThreadLog()
        // Nothing is compressed for now. If the images were compressed on the main thread or
        // on the stream's queue, details would be reported all the same.
        let gate = holdCompressor()
        defer { gate.signal() }
        let host = liveHost { app in
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                main.noteCapture(of: request.layerID)
                return capture(request, limit, context, stopFlag)
            }
        }

        start(request(ids), host: host, log: log)
        // All five layers are rendered although not one image has been compressed.
        try await waitUntil("all layers to be captured") { main.captured.count == 5 }
        await settle(compressor: false)
        XCTAssertEqual(log.details, [], "an image was compressed somewhere else than on the encode queue")

        gate.signal()
        try await waitUntil("the stream to complete") { log.completedCount == 1 }
        XCTAssertEqual(log.details.map(\.layerID), ids)
        XCTAssertEqual(main.captured, ids)
    }

    func test_S_SHOT_09_renderingWaitsForCompression() async throws {
        let ids = try makeLayers(5)
        let log = StreamLog()
        let main = MainThreadLog()
        let gate = holdCompressor()
        defer { gate.signal() }
        let host = liveHost { app in
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                main.noteCapture(of: request.layerID)
                return capture(request, limit, context, stopFlag)
            }
        }

        // One image of 20 x 20 points is more than this limit allows to wait.
        start(request(ids), host: host, outstandingByteLimit: 100, log: log)
        try await waitUntil("the first capture") { main.captured.count >= 1 }
        await settle(compressor: false)
        // The compressor is behind: no second layer is rendered on top of the waiting one.
        XCTAssertEqual(main.captured, [ids[0]])

        gate.signal()
        try await waitUntil("the stream to complete") { log.completedCount == 1 }
        XCTAssertEqual(log.details.map(\.layerID), ids)
        XCTAssertEqual(main.captured, ids)
    }

    // MARK: - S-CONN-13

    /// The host of a real session, with every capture noted in `main`.
    private func notingHost(
        _ main: MainThreadLog,
        _ configure: @escaping (inout TestHostApp) -> Void = { _ in }
    ) -> HostAccess {
        liveHost { app in
            configure(&app)
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                main.noteCapture(of: request.layerID)
                return capture(request, limit, context, stopFlag)
            }
        }
    }

    func test_S_CONN_13_streamWaitsWhileTooMuchIsUnsent() async throws {
        let ids = try makeLayers(4)
        let log = StreamLog()
        let main = MainThreadLog()
        let unsent = UnsentBytes()
        unsent.value = 1_000_001
        let host = notingHost(main)

        let stream = start(
            request(ids),
            host: host,
            outstandingByteLimit: 1_000_000,
            log: log,
            unsent: unsent
        )
        await settle()
        XCTAssertEqual(main.captured, [], "a layer was rendered although the connection was behind")

        // The connection sent some, but not enough.
        unsent.value = 1_000_000
        queue.async { stream.resume() }
        try await waitUntil("the stream to complete") { log.completedCount == 1 }
        XCTAssertEqual(log.details.map(\.layerID), ids, "the stream did not go on where it stopped")
        XCTAssertEqual(main.captured, ids)
    }

    func test_S_CONN_13_budgetCountsUnsentAndUncompressedTogether() async throws {
        // A 20-point view at scale 2 or 3 counts as 72,336 or 80,386 bytes while it waits to
        // be compressed (its pixels, a thirty-second more, and 64 KiB).
        let ids = try makeLayers(4)
        for unsentBytes in [0, 30_000] {
            let log = StreamLog()
            let main = MainThreadLog()
            let unsent = UnsentBytes()
            unsent.value = unsentBytes
            let gate = holdCompressor()
            let host = notingHost(main)

            start(request(ids), host: host, outstandingByteLimit: 100_000, log: log, unsent: unsent)
            try await waitUntil("the first capture") { main.captured.count >= 1 }
            await settle(compressor: false)
            // Alone, one waiting detail leaves room for a second; with 30,000 unsent bytes, it
            // does not.
            XCTAssertEqual(main.captured.count, unsentBytes == 0 ? 2 : 1, "unsent: \(unsentBytes)")

            gate.signal()
            try await waitUntil("the stream to complete") { log.completedCount == 1 }
            XCTAssertEqual(log.details.map(\.layerID), ids)
        }
    }

    func test_S_CONN_13_stoppedStreamDoesNotCompressWhatIsLeft() async throws {
        let ids = try makeLayers(3)
        let log = StreamLog()
        let main = MainThreadLog()
        let gate = holdCompressor()
        defer { gate.signal() }
        let host = NotingPipeline(base: notingHost(main), main: main)

        let stream = start(request(ids), host: host, log: log)
        try await waitUntil("all layers to be captured") { main.captured.count == 3 }
        await settle(compressor: false)
        // The client went away: three details wait for the compressor.
        queue.sync { stream.stop() }
        gate.signal()
        await settle()

        XCTAssertFalse(main.events.contains("compress"), "a stopped stream's details were compressed")
        XCTAssertEqual(log.details, [])
    }

    func test_S_SHOT_09_theMainThreadTurnsBetweenLayers() async throws {
        let ids = try makeLayers(12)
        let log = StreamLog()
        let main = MainThreadLog()
        // Counts the turns of the main run loop.
        let observer = try XCTUnwrap(
            CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault,
                CFRunLoopActivity.beforeTimers.rawValue,
                true,
                0
            ) { _, _ in
                main.noteTurn()
            }
        )
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }

        let host = liveHost { app in
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                let index = main.noteCapture(of: request.layerID)
                // Work of the host app that comes up while a layer is being captured.
                DispatchQueue.main.async { main.note("other \(index)") }
                return capture(request, limit, context, stopFlag)
            }
        }

        start(request(ids), host: host, log: log)
        try await waitUntil("the stream to complete") { log.completedCount == 1 }
        await drain(.main)

        XCTAssertEqual(main.captured, ids)
        // The host's work runs before the next layer is captured, every time.
        XCTAssertEqual(
            main.events,
            (0..<12).flatMap { ["capture \($0)", "other \($0)"] },
            "two layers were captured without the main queue's other work in between"
        )
        // And the run loop begins a new turn between any two layers: it gets to its timers,
        // its sources and the screen update.
        let turns = main.turnsAtCapture
        for (earlier, later) in zip(turns, turns.dropFirst()) {
            XCTAssertGreaterThan(later, earlier, "two layers were captured in one turn of the run loop: \(turns)")
        }
    }

    // MARK: - A stream is one request (S-API-04)

    /// The host of a real session whose host app registered into `store`.
    private func host(registeredIn store: ExtensionStore) -> HostAccess {
        HostAccess(app: LiveHostApp(extensions: store), registry: registry, queue: queue, encodeQueue: encodeQueue)
    }

    /// Runs one stream to its end and returns what it reported.
    private func details(_ request: GetLayerDetails, host: HostAccess) async throws -> [LayerDetail] {
        let log = StreamLog()
        start(request, host: host, log: log)
        try await waitUntil("the stream to complete") { log.completedCount == 1 }
        await settle()
        return log.details
    }

    func test_S_HIER_17_aStreamAsksForALayersVirtualChildrenOnce() async throws {
        let window = try makeWindow()
        let chart = BarChartView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        chart.bars = [
            BarChartView.Bar(id: "march", value: 40, parts: ["low", "high"]),
            BarChartView.Bar(id: "april", value: 60)
        ]
        window.addSubview(chart)
        let calls = CallCount()
        let store = ExtensionStore()
        store.describe(
            BarChartView.self,
            CutawayServer.Description(virtualChildren: { chart in
                calls.value += 1
                return BarChartView.description.virtualChildren?(chart) ?? []
            }),
            isView: true
        )
        // The IDs of the virtual nodes are given out by a hierarchy.
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let virtual = hierarchy.nodes.filter { $0.nodeKind == .virtual }.map(\.id)
        XCTAssertEqual(virtual.count, 4)
        let host = host(registeredIn: store)
        let before = calls.value

        // Every node of the chart, twice: the chart's tree is asked for once.
        let first = try await details(request(virtual + virtual), host: host)
        XCTAssertEqual(first.map(\.layerID), virtual + virtual)
        XCTAssertEqual(first.map(\.status), Array(repeating: .ok, count: 8))
        XCTAssertEqual(calls.value - before, 1)

        // The next request asks again, and finds that April is gone.
        chart.bars.removeLast()
        let second = try await details(request(virtual), host: host)
        XCTAssertEqual(second.map(\.status), [.ok, .ok, .ok, .layerNotFound])
        XCTAssertEqual(calls.value - before, 2)
    }

    func test_S_ATTR_25_eachStreamNamesTheRegisteredColorsAnew() async throws {
        let window = try makeWindow()
        window.overrideUserInterfaceStyle = .light
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        view.backgroundColor = .blue
        window.addSubview(view)
        let id = registry.register(view.layer)
        // A color that follows the app's own theme rather than the traits.
        let theme = Theme()
        let store = ExtensionStore()
        store.registerColor(UIColor { _ in theme.isWarm ? .orange : .blue }, named: "accent")
        let host = host(registeredIn: store)
        let attributes = GetLayerDetails(
            requests: [LayerDetailRequest(layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true)],
            maxTextureDimension: 0
        )
        func backgroundColorName() async throws -> String? {
            let groups = try await details(attributes, host: host).first?.attributeGroups ?? []
            let value = groups.flatMap(\.attributes).first { $0.id == "view.backgroundColor" }?.value
            guard case .color(_, _, _, _, let name)? = value else {
                XCTFail("no background color in \(groups.map(\.id))")
                return nil
            }
            return name
        }

        let named = try await backgroundColorName()
        XCTAssertEqual(named, "accent")
        // The traits are the same, the color is not: the next request no longer names it.
        theme.isWarm = true
        let renamed = try await backgroundColorName()
        XCTAssertNil(renamed)
    }

    func test_S_API_04_whatAStreamKeptIsDroppedOnTheMainThreadWhenItEnds() async throws {
        let ids = try makeLayers(3)
        let releases = Releases()
        let host = liveHost { app in
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                _ = context.memo.entry { Kept(releases: releases) }
                return capture(request, limit, context, stopFlag)
            }
        }
        let reported = try await details(request(ids), host: host)
        XCTAssertEqual(reported.count, 3)
        await drain(.main)
        // One entry for the three layers, dropped on the main thread once the stream completed,
        // though the stream is still held.
        XCTAssertEqual(releases.onMainThread, [true])
    }
}

/// What the stream reads as the connection's unsent bytes. Set by the test.
private final class UnsentBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0

    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return bytes
        }
        set {
            lock.lock()
            bytes = newValue
            lock.unlock()
        }
    }
}

/// Passes what a stream tells its delegate on to the test's log.
private final class StreamObserver: LayerDetailsStreamDelegate, @unchecked Sendable {
    private let log: StreamLog
    private let unsent: UnsentBytes?

    init(log: StreamLog, unsent: UnsentBytes?) {
        self.log = log
        self.unsent = unsent
    }

    var unsentByteCount: Int { unsent?.value ?? 0 }

    func streamDidProduce(_ detail: LayerDetail, for _: LayerDetailRequest) {
        log.add(detail)
    }

    func streamDidComplete() {
        log.complete()
    }
}

/// Lets a capture closure reach the stream that is created after it.
private final class StreamBox: @unchecked Sendable {
    // Touched on the stream's queue only.
    var stream: LayerDetailsStream?
}

/// How often a closure of the host app was called. Main thread only.
@MainActor
private final class CallCount {
    var value = 0
}

/// The app's own theme, which a registered color may follow. UIKit may resolve a color on any
/// thread.
private final class Theme: @unchecked Sendable {
    private let lock = NSLock()
    private var warm = false

    var isWarm: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return warm
        }
        set {
            lock.lock()
            warm = newValue
            lock.unlock()
        }
    }
}

/// Whether each `Kept` was released on the main thread, in order.
private final class Releases: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [Bool] = []

    var onMainThread: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return threads
    }

    func note() {
        lock.lock()
        threads.append(Thread.isMainThread)
        lock.unlock()
    }
}

/// An entry of a request's memo that notes where it was released.
private final class Kept {
    let releases: Releases

    init(releases: Releases) {
        self.releases = releases
    }

    deinit {
        releases.note()
    }
}
