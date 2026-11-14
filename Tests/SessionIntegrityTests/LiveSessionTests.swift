//
//  LiveSessionTests.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import Foundation
import JailbreakDetector
import Testing
@testable import SessionIntegrity

/// Runs the real probe and the public API in the Simulator.
@MainActor
@Suite struct LiveSessionTests {
    private var expectedSignals: [SessionSignalID] {
        let region = SystemSessionProbe().regionCode
        return SessionSignalID.evaluationOrder.filter { !($0 == .activeCall && region == "CN") }
    }

    @Test func everySignalIsEvaluatedInTheSimulator() {
        let report = SessionIntegrity.evaluate(.all)
        #expect(report.environment == .simulator)
        #expect(report.evaluated == expectedSignals)
    }

    @Test func automationIsActiveUnderXCTest() {
        let report = SessionIntegrity.evaluate(.init(signals: [.automation]))
        #expect(report.isActive(.automation))
    }

    @Test func noCallIsInProgress() {
        #expect(!SessionIntegrity.evaluate(.init(signals: [.activeCall])).isActive(.activeCall))
    }

    @Test func publicAPICarriesTheNonce() {
        let nonce = Data("server-issued-nonce".utf8)
        #expect(SessionIntegrity.evaluate(nonce: nonce).nonce == nonce)
    }

    @Test func streamYieldsTheCurrentReport() async {
        let first = await firstReport(of: SessionIntegrity.reports(.all))
        #expect(first?.evaluated == expectedSignals)
        #expect(first?.isActive(.automation) == true)
    }
}
