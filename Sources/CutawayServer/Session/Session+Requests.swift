#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

// What the session does with each request once its turn comes: which part of the host answers
// it and what is sent back.

extension Session {
    func handle(_ request: RequestQueue.Request) {
        let requestID = request.frame.requestID
        switch request.frame.body {
        case .getAppIcon:
            answer(requestID, requiresActiveApp: false, perform: host.loadAppIcon(then:)) { _, image in
                .appIcon(AppIcon(image: image))
            }
        case .getHierarchy:
            // P-APP-01: no hierarchy unless the app is active.
            answer(
                requestID,
                requiresActiveApp: true,
                onMain: { app, context in app.captureHierarchy(in: context) },
                reply: { session, hierarchy in
                    // The app may have left the active state while the layers were being read. The
                    // client has been told by now, and must not get a hierarchy after that event.
                    session.appState == .active
                        ? .hierarchy(hierarchy) : .error(.appNotActive)
                }
            )
        case .getSubtree(let rootID):
            // P-APP-01: no subtree unless the app is active.
            answer(
                requestID,
                requiresActiveApp: true,
                onMain: { app, context in app.captureSubtree(of: rootID, in: context) },
                reply: { session, hierarchy in
                    // As for the whole hierarchy: nothing read after the client was told the app
                    // left the active state.
                    if session.appState != .active {
                        return .error(.appNotActive)
                    } else if let hierarchy {
                        return .hierarchy(hierarchy)
                    } else {
                        return .error(.layerNotFound(rootID))
                    }
                }
            )
        case .setAttribute(let change):
            // P-APP-01: nothing is changed unless the app is active, here and again on the main
            // thread.
            answer(
                requestID,
                requiresActiveApp: true,
                perform: { [host, version] in
                    host.performChange(
                        version: version,
                        { app, context in app.setAttribute(change, in: context) },
                        then: $0
                    )
                },
                reply: { session, result in
                    // Unlike a hierarchy, the answer is sent whatever the state is now: the change
                    // may have been made, and the main thread checked the state before making it.
                    switch result {
                    // P-ATTR-08: only the sections the negotiated version has.
                    case .success(let answer): return .setAttributeResult(answer.adapted(to: session.version))
                    case .failure(let error): return .error(error)
                    }
                }
            )
        case .getEnvironment:
            // P-APP-01: answered whatever the app's state.
            answer(
                requestID,
                requiresActiveApp: false,
                perform: { [host] in host.perform({ _, connection in connection.environment.read() }, then: $0) },
                reply: { _, environment in .environment(environment) }
            )
        case .setEnvironment(let overrides):
            // P-APP-01, here and again on the main thread, then P-ENV-04, then the app's response
            // (P-ENV-02).
            answer(
                requestID,
                requiresActiveApp: true,
                perform: { [host] in host.setEnvironment(overrides ?? .none, then: $0) },
                reply: { _, result in
                    // As for `SetAttribute`: the overrides may have been applied, so the answer
                    // goes out whatever the state is now.
                    switch result {
                    case .success(let environment): return .environment(environment)
                    case .failure(let error): return .error(error)
                    }
                }
            )
        case .getLayerDetails(let details):
            beginStream(details, requestID: requestID, isCancelled: request.isCancelled)
        case .cancel:
            // Never queued: `accept(_:)` handles it on arrival.
            break
        case nil, .hello, .appIcon, .hierarchy, .layerDetailsChunk, .streamEnd, .error,
             .appStateChanged, .setAttributeResult, .environment:
            // P-REQ-08: answer and keep the connection.
            transport.send(Frame(requestID: requestID, body: .error(.unexpectedMessage)))
        }
    }

    /// A request with one answer. When it needs the app active and the app is not, it is
    /// refused at once (P-APP-01). Otherwise nothing else is handled until `perform` completes
    /// and the answer that `reply` makes on the server queue is sent.
    private func answer<Value>(
        _ requestID: UInt32,
        requiresActiveApp: Bool,
        perform: (@escaping @Sendable (Value) -> Void) -> Void,
        reply: @escaping @Sendable (Session, Value) -> Message
    ) {
        if requiresActiveApp, appState != .active {
            transport.send(Frame(requestID: requestID, body: .error(.appNotActive)))
            return
        }
        beginRequest()
        perform { [weak self] value in
            guard let self, self.state == .ready else { return }
            self.transport.send(Frame(requestID: requestID, body: reply(self, value)))
            self.endRequest()
        }
    }

    /// A request answered by what the host app says on the main thread, with the request's
    /// context (`HostAccess.perform(version:_:then:)`).
    private func answer<Value: Sendable>(
        _ requestID: UInt32,
        requiresActiveApp: Bool,
        onMain work: @escaping @MainActor @Sendable (any HostApp, RequestContext) -> Value,
        reply: @escaping @Sendable (Session, Value) -> Message
    ) {
        answer(
            requestID,
            requiresActiveApp: requiresActiveApp,
            perform: { [host, version] in host.perform(version: version, work, then: $0) },
            reply: reply
        )
    }
}
#endif
