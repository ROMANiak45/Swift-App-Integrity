//
//  SessionMonitorTests.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import Foundation
import JailbreakDetector
import Testing
@testable import SessionIntegrity

@MainActor
@Suite struct SessionSignalTests {
    private func report(_ probe: FakeSessionProbe) -> SessionReport {
        SessionMonitor(probe: probe).report(.all)
    }

    @Test func quietSessionHasNoActiveSignals() {
        let report = report(FakeSessionProbe())
        #expect(report.active.isEmpty)
        #expect(report.evaluated == SessionSignalID.evaluationOrder)
        #expect(report.environment == .device)
    }

    @Test(arguments: [
        (SessionSignalID.screenCapture, nil),
        (.activeCall, "connected"),
        (.debugger, nil),
        (.networkProxy, "http"),
        (.vpn, "utun"),
        (.automation, "XCTest.framework"),
        (.assistiveInput, "switch-control"),
    ] as [(SessionSignalID, String?)])
    func activeSignalIsReportedWithItsDetail(id: SessionSignalID, detail: String?) {
        let report = report(FakeSessionProbe([id: .active(detail: detail)]))
        #expect(report.active == [SessionReport.Signal(id: id, detail: detail)])
        #expect(report.isActive(id))
    }

    @Test func activeSignalsFollowTheEvaluationOrder() {
        let probe = FakeSessionProbe([
            .assistiveInput: .active(detail: "assistive-touch"),
            .screenCapture: .active(detail: nil),
            .activeCall: .active(detail: "on-hold"),
        ])
        #expect(report(probe).active.map(\.id) == [.screenCapture, .activeCall, .assistiveInput])
    }
}

@MainActor
@Suite struct SessionConfigurationTests {
    @Test func defaultConfigurationEvaluatesTheRecommendedSignals() {
        let probe = FakeSessionProbe([.vpn: .active(detail: "utun")])
        let report = SessionMonitor(probe: probe).report(.default)
        #expect(report.evaluated == [.screenCapture, .activeCall, .debugger])
        #expect(report.active.isEmpty)
        #expect(probe.readSignals == [.screenCapture, .activeCall, .debugger])
    }

    @Test func onlySelectedSignalsAreRead() {
        let probe = FakeSessionProbe()
        let report = SessionMonitor(probe: probe).report(.init(signals: [.vpn, .debugger]))
        #expect(report.evaluated == [.debugger, .vpn])
        #expect(probe.readSignals == [.debugger, .vpn])
    }

    @Test func noSignalsEvaluateNothing() {
        let probe = FakeSessionProbe([.debugger: .active(detail: nil)])
        let report = SessionMonitor(probe: probe).report(.init(signals: []))
        #expect(report.evaluated.isEmpty)
        #expect(report.active.isEmpty)
    }

    @Test func unknownSignalIsNotEvaluated() {
        let probe = FakeSessionProbe()
        let report = SessionMonitor(probe: probe).report(.init(signals: [SessionSignalID(rawValue: "custom")]))
        #expect(report.evaluated.isEmpty)
    }

    @Test func callIsNotEvaluatedInChina() {
        let probe = FakeSessionProbe([.activeCall: .active(detail: "connected")])
        probe.regionCode = "CN"
        let report = SessionMonitor(probe: probe).report(.all)
        #expect(!report.evaluated.contains(.activeCall))
        #expect(!report.isActive(.activeCall))
        #expect(!probe.readSignals.contains(.activeCall))
        #expect(report.evaluated.count == SessionSignalID.all.count - 1)
    }

    @Test func callIsEvaluatedWithoutARegion() {
        let probe = FakeSessionProbe([.activeCall: .active(detail: "connected")])
        probe.regionCode = nil
        #expect(SessionMonitor(probe: probe).report(.all).isActive(.activeCall))
    }

    @Test func nothingIsEvaluatedOnAMac() {
        let probe = FakeSessionProbe([.screenCapture: .active(detail: nil)])
        probe.environment = .mac
        let report = SessionMonitor(probe: probe).report(.all)
        #expect(report.environment == .mac)
        #expect(report.evaluated.isEmpty)
        #expect(probe.readSignals.isEmpty)
    }

    @Test func signalsAreEvaluatedInTheSimulator() {
        let probe = FakeSessionProbe([.screenCapture: .active(detail: nil)])
        probe.environment = .simulator
        #expect(SessionMonitor(probe: probe).report(.all).isActive(.screenCapture))
    }

    @Test func presetsCoverTheExpectedSignals() {
        #expect(SessionIntegrity.Configuration.default.signals == [.screenCapture, .activeCall, .debugger])
        #expect(SessionIntegrity.Configuration.all.signals.count == 7)
        #expect(SessionSignalID.all == Set(SessionSignalID.evaluationOrder))
    }
}

@MainActor
@Suite struct SessionStreamTests {
    @Test func firstReportArrivesAtOnce() async {
        let probe = FakeSessionProbe([.debugger: .active(detail: nil)])
        let reports = SessionMonitor(probe: probe).reports(.default)
        let first = await firstReport(of: reports)
        #expect(first?.isActive(.debugger) == true)
    }

    @Test func changeProducesANewReport() async {
        let probe = FakeSessionProbe()
        let reports = SessionMonitor(probe: probe).reports(.default)
        probe.states[.activeCall] = .active(detail: "connected")
        probe.fire()
        let collected = await Self.collect(2, from: reports)
        #expect(collected.map { $0.isActive(.activeCall) } == [false, true])
    }

    @Test func unchangedStateProducesNoReport() async {
        let probe = FakeSessionProbe()
        let reports = SessionMonitor(probe: probe).reports(.default)
        probe.fire()
        probe.fire()
        probe.states[.screenCapture] = .active(detail: nil)
        probe.fire()
        probe.finish()
        let collected = await Self.collect(10, from: reports)
        #expect(collected.map { $0.isActive(.screenCapture) } == [false, true])
    }

    @Test func streamObservesOnlyTheEvaluatedSignals() {
        let probe = FakeSessionProbe()
        probe.regionCode = "CN"
        _ = SessionMonitor(probe: probe).reports(.init(signals: [.activeCall, .assistiveInput]))
        #expect(probe.observedSignals == [.assistiveInput])
    }

    @Test func streamReportsHaveNoNonce() async {
        let reports = SessionMonitor(probe: FakeSessionProbe()).reports(.default)
        #expect(await firstReport(of: reports)?.nonce == nil)
    }

    /// The first `count` reports, or fewer if the stream ends.
    private static func collect(_ count: Int, from reports: AsyncStream<SessionReport>) async -> [SessionReport] {
        var collected: [SessionReport] = []
        for await report in reports {
            collected.append(report)
            if collected.count == count { break }
        }
        return collected
    }
}
