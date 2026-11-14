//
//  SessionIntegrity.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import Foundation

/// Reports which session risk signals are active, such as a shared screen or a phone call in progress.
///
/// Each signal has innocent explanations, so the report has no verdict. Send it to your backend and weigh it
/// together with what the user is doing. Signals are evaluated on a device and in the Simulator, never on a
/// Mac.
@available(iOSApplicationExtension, unavailable)
public enum SessionIntegrity {
    /// Evaluates the configured signals once, for example just before the user confirms a payment.
    ///
    /// - Parameter nonce: A value issued by your server for this evaluation, carried into the report so the
    ///   server can reject a replayed report. Required by ``SessionReport/attestationPayload()``.
    @MainActor
    public static func evaluate(_ configuration: Configuration = .default, nonce: Data? = nil) -> SessionReport {
        SessionMonitor(probe: SystemSessionProbe()).report(configuration, nonce: nonce)
    }

    /// Yields the current report at once, then a new report whenever one of the configured signals changes.
    ///
    /// Screen capture, calls and assistive input are observed as they change. The other signals are read
    /// again with every change and whenever the app becomes active. Observation stops when the stream's
    /// consumer is cancelled.
    @MainActor
    public static func reports(_ configuration: Configuration = .default) -> AsyncStream<SessionReport> {
        SessionMonitor(probe: SystemSessionProbe()).reports(configuration)
    }
}
