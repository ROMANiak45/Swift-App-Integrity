//
//  SessionProbe.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import JailbreakDetector

/// Whether a signal is active, and what was observed if it is.
enum SignalState: Sendable, Hashable {
    case inactive
    case active(detail: String?)
}

/// The view of the session that the monitor reads. Tests substitute a fake.
@MainActor
protocol SessionProbe {
    /// Where the process is running.
    var environment: JailbreakReport.Environment { get }
    /// The device's region, such as `CN`, or `nil` if it is not set.
    var regionCode: String? { get }

    func screenCapture() -> SignalState
    func activeCall() -> SignalState
    func debugger() -> SignalState
    func networkProxy() -> SignalState
    func vpn() -> SignalState
    func automation() -> SignalState
    func assistiveInput() -> SignalState

    /// Yields whenever one of the signals may have changed. Only the given signals need to be observed.
    func changes(observing signals: Set<SessionSignalID>) -> AsyncStream<Void>
}
