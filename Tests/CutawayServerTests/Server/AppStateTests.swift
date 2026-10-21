import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// The app state event after the handshake and on every change.
final class AppStateTests: ServerTestCase {
    func test_S_CONN_06_sendsTheCurrentStateAfterTheHandshake() async throws {
        let server = makeServer()
        let port = try await server.start()

        let active = try await connect(to: port)
        try await active.send(Fixtures.data("handshake/c2s.stream"))
        _ = try await active.nextFrame()  // Hello
        // The same frame as the fixture's.
        let state = try await active.nextFrame()
        XCTAssertEqual(state, try Fixtures.frame("handshake/03-s2c-app-state.bin"))
        active.close()

        // The state at the time of the handshake, not the one at launch.
        try await server.post(UIApplication.willResignActiveNotification, expecting: .inactive)
        try await server.post(UIApplication.didEnterBackgroundNotification, expecting: .background)
        let (_, later) = try await connectAndHandshake(port: port)
        XCTAssertEqual(later, .background)
    }

    func test_S_CONN_06_sendsAnEventOnEveryChange() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        let changes: [(Notification.Name, AppState)] = [
            (UIApplication.willResignActiveNotification, .inactive),
            (UIApplication.didEnterBackgroundNotification, .background),
            (UIApplication.willEnterForegroundNotification, .inactive),
            (UIApplication.didBecomeActiveNotification, .active)
        ]
        for (name, state) in changes {
            server.center.post(name: name, object: nil)
            let event = try await client.nextFrame()
            XCTAssertEqual(event, Frame(requestID: 0, body: .appStateChanged(state)), "\(name.rawValue)")
        }

        // A notification that changes nothing is not an event: the next frame is the answer
        // to the request sent after it.
        server.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        try await client.send(Frame(requestID: 1, body: .getAppIcon))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, 1)
    }
}
