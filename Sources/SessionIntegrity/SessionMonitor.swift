//
//  SessionMonitor.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import Foundation

/// Evaluates the configured signals and assembles reports.
@available(iOSApplicationExtension, unavailable)
@MainActor
struct SessionMonitor {
    /// Apple does not approve apps with CallKit active in China, so the call signal is skipped there.
    static let callKitRestrictedRegions: Set<String> = ["CN"]

    let probe: any SessionProbe

    func report(_ configuration: SessionIntegrity.Configuration, nonce: Data? = nil) -> SessionReport {
        let evaluated = evaluatedSignals(configuration)
        let active = evaluated.compactMap { id -> SessionReport.Signal? in
            guard case .active(let detail) = state(of: id) else { return nil }
            return SessionReport.Signal(id: id, detail: detail)
        }
        return SessionReport(environment: probe.environment, evaluated: evaluated, active: active, nonce: nonce)
    }

    /// Yields the current report at once, then a new report whenever it changes.
    func reports(_ configuration: SessionIntegrity.Configuration) -> AsyncStream<SessionReport> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionReport.self)
        var last = report(configuration)
        continuation.yield(last)

        let changes = probe.changes(observing: Set(evaluatedSignals(configuration)))
        let task = Task {
            for await _ in changes {
                let next = report(configuration)
                if next != last {
                    continuation.yield(next)
                    last = next
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// The selected signals that can be evaluated here, in evaluation order.
    private func evaluatedSignals(_ configuration: SessionIntegrity.Configuration) -> [SessionSignalID] {
        guard probe.environment != .mac else { return [] }
        let callKitRestricted = probe.regionCode.map(Self.callKitRestrictedRegions.contains) ?? false
        return SessionSignalID.evaluationOrder.filter { id in
            configuration.signals.contains(id) && !(id == .activeCall && callKitRestricted)
        }
    }

    private func state(of id: SessionSignalID) -> SignalState {
        switch id {
        case .screenCapture: probe.screenCapture()
        case .activeCall: probe.activeCall()
        case .debugger: probe.debugger()
        case .networkProxy: probe.networkProxy()
        case .vpn: probe.vpn()
        case .automation: probe.automation()
        case .assistiveInput: probe.assistiveInput()
        default: .inactive
        }
    }
}
