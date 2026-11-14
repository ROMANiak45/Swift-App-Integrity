//
//  FakeSessionProbe.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import JailbreakDetector
@testable import SessionIntegrity

/// The first report the stream yields, or `nil` if it ends first.
func firstReport(of reports: AsyncStream<SessionReport>) async -> SessionReport? {
    for await report in reports {
        return report
    }
    return nil
}

/// A scripted session. The default value is a device with no signal active.
@MainActor
final class FakeSessionProbe: SessionProbe {
    var environment: JailbreakReport.Environment = .device
    var regionCode: String? = "GB"
    var states: [SessionSignalID: SignalState] = [:]
    private(set) var observedSignals: Set<SessionSignalID>?
    private(set) var readSignals: [SessionSignalID] = []
    private var continuation: AsyncStream<Void>.Continuation?

    init(_ states: [SessionSignalID: SignalState] = [:]) {
        self.states = states
    }

    /// Reports that something may have changed, as a system notification would.
    func fire() {
        continuation?.yield()
    }

    /// Ends the change stream, as cancelling the consumer would.
    func finish() {
        continuation?.finish()
    }

    private func read(_ id: SessionSignalID) -> SignalState {
        readSignals.append(id)
        return states[id] ?? .inactive
    }

    func screenCapture() -> SignalState { read(.screenCapture) }
    func activeCall() -> SignalState { read(.activeCall) }
    func debugger() -> SignalState { read(.debugger) }
    func networkProxy() -> SignalState { read(.networkProxy) }
    func vpn() -> SignalState { read(.vpn) }
    func automation() -> SignalState { read(.automation) }
    func assistiveInput() -> SignalState { read(.assistiveInput) }

    func changes(observing signals: Set<SessionSignalID>) -> AsyncStream<Void> {
        observedSignals = signals
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self.continuation = continuation
        return stream
    }
}
