import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's `--watch` (S-PROBE-10): its checks accept the fixtures of `watch-hierarchy` and
/// name what is wrong with anything else; the option; reading with a time limit.
final class WatchChecksTests: XCTestCase {
    func test_S_PROBE_10_watchChecksAcceptTheFixtures() throws {
        try WatchChecks.answer(
            Fixtures.frame("watch-hierarchy/04-s2c-watch-hierarchy-result.bin"),
            to: 2,
            enabled: true
        )
        try WatchChecks.answer(
            Fixtures.frame("watch-hierarchy/16-s2c-watch-hierarchy-result.bin"),
            to: 6,
            enabled: false
        )
        let roots = try WatchChecks.event(
            Fixtures.frame("watch-hierarchy/05-s2c-hierarchy-changed.bin"),
            at: 1,
            previous: nil
        )
        XCTAssertEqual(roots, HierarchyChanged(roots: [3, 4], whole: false))
        let whole = try WatchChecks.event(
            Fixtures.frame("watch-hierarchy/12-s2c-hierarchy-changed.bin"),
            at: 2.5,
            previous: 1
        )
        XCTAssertEqual(whole, .everything)
        XCTAssertEqual(WatchChecks.describe(roots, at: 1), "watch: +1.00 s: roots 3, 4")
        XCTAssertEqual(WatchChecks.describe(whole, at: 2.5), "watch: +2.50 s: the whole hierarchy")
    }

    func test_S_PROBE_10_watchChecksRejectBrokenFrames() throws {
        func rejects(_ message: String, _ check: () throws -> Void) {
            XCTAssertThrowsError(try check()) { error in
                XCTAssertTrue("\(error)".contains(message), "\(error)")
            }
        }
        let event = { (changed: HierarchyChanged) in Frame(requestID: 0, body: .hierarchyChanged(changed)) }
        rejects("is whole, but has roots [3]") {
            _ = try WatchChecks.event(event(HierarchyChanged(roots: [3], whole: true)), at: 1, previous: nil)
        }
        rejects("has no roots and is not whole") {
            _ = try WatchChecks.event(event(HierarchyChanged(roots: [], whole: false)), at: 1, previous: nil)
        }
        rejects("0.50 s apart, less than 1 s (P-WATCH-08)") {
            _ = try WatchChecks.event(event(.everything), at: 1.5, previous: 1)
        }
        rejects("expected HierarchyChanged with request_id 0") {
            _ = try WatchChecks.event(Frame(requestID: 4, body: .hierarchyChanged(.everything)), at: 1, previous: nil)
        }
        rejects("says false, but the request turned notifications on") {
            try WatchChecks.answer(
                Frame(requestID: 2, body: .watchHierarchyResult(enabled: false)),
                to: 2,
                enabled: true
            )
        }
        rejects("expected WatchHierarchyResult for request 2") {
            try WatchChecks.answer(
                Frame(requestID: 2, body: .error(WireError(code: .unexpectedMessage, message: "no"))),
                to: 2,
                enabled: true
            )
        }
    }

    func test_S_PROBE_10_watchTakesSeconds() throws {
        XCTAssertEqual(try Options(arguments: ["--watch", "30"]).watch, 30)
        XCTAssertNil(try Options(arguments: []).watch)
        for wrong in [["--watch"], ["--watch", "0"], ["--watch", "soon"]] {
            XCTAssertThrowsError(try Options(arguments: wrong), "\(wrong)")
        }
    }

    /// A frame within the limit; none when nothing comes in time; a failure once the server closes.
    func test_S_PROBE_10_readsWithATimeLimit() throws {
        let port = try holdingServer(sending: Fixtures.data("watch-hierarchy/05-s2c-hierarchy-changed.bin"), for: 1.5)
        let connection = try XCTUnwrap(ProbeConnection(host: "127.0.0.1", port: port, timeout: 5))
        try connection.send(Frame(requestID: 0, body: .getHierarchy))
        XCTAssertEqual(
            try connection.nextFrame(within: 1)?.body,
            .hierarchyChanged(HierarchyChanged(roots: [3, 4], whole: false))
        )
        let start = Date()
        XCTAssertNil(try connection.nextFrame(within: 0.3))
        XCTAssertEqual(Date().timeIntervalSince(start), 0.3, accuracy: 0.2)
        XCTAssertThrowsError(try connection.nextFrame(within: 3)) { error in
            XCTAssertTrue("\(error)".contains("closed the connection"), "\(error)")
        }
    }

    /// A server that accepts one client, sends it `payload` framed once it has read something,
    /// keeps the connection for `seconds`, then closes.
    private func holdingServer(sending payload: Data, for seconds: TimeInterval) throws -> UInt16 {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, length) == 0 && listen(listener, 1) == 0 && getsockname(
                    listener,
                    $0,
                    &length
                ) == 0
            }
        }
        guard bound else { throw ProbeFailure("could not listen on 127.0.0.1") }
        let framed = FrameCodec.framed(payload)
        Thread.detachNewThread {
            defer { close(listener) }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = recv(client, &buffer, buffer.count, 0)
            _ = framed.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
            Thread.sleep(forTimeInterval: seconds)
            close(client)
        }
        return UInt16(bigEndian: address.sin_port)
    }
}
