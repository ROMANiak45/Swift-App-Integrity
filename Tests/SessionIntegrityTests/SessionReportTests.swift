//
//  SessionReportTests.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import CryptoKit
import Foundation
import JailbreakDetector
import Testing
@testable import SessionIntegrity

@MainActor
@Suite struct SessionReportTests {
    private let nonce = Data("server-issued-nonce".utf8)

    private func report(nonce: Data?) -> SessionReport {
        let probe = FakeSessionProbe([.activeCall: .active(detail: "connected"), .screenCapture: .active(detail: nil)])
        return SessionMonitor(probe: probe).report(.default, nonce: nonce)
    }

    @Test func nonceIsCarriedIntoTheReport() {
        #expect(report(nonce: nonce).nonce == nonce)
        #expect(report(nonce: nil).nonce == nil)
    }

    @Test func survivesAnEncodingRoundTrip() throws {
        let original = report(nonce: nonce)
        let decoded = try JSONDecoder().decode(SessionReport.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func encodesSignalIdentifiersAsStrings() throws {
        let payload = try report(nonce: nonce).attestationPayload()
        let json = String(decoding: payload.data, as: UTF8.self)
        #expect(json.contains(#""id":"active-call""#))
        #expect(json.contains(#""evaluated":["screen-capture","active-call","debugger"]"#))
    }

    @Test func digestIsTheSHA256OfThePayloadBytes() throws {
        let payload = try report(nonce: nonce).attestationPayload()
        #expect(payload.digest == Data(SHA256.hash(data: payload.data)))
        #expect(payload.digest.count == 32)
    }

    @Test func sameReportGivesTheSameBytes() throws {
        let report = report(nonce: nonce)
        #expect(try report.attestationPayload() == report.attestationPayload())
    }

    @Test func differentNoncesGiveDifferentDigests() throws {
        let first = try report(nonce: Data("a".utf8)).attestationPayload()
        let second = try report(nonce: Data("b".utf8)).attestationPayload()
        #expect(first.digest != second.digest)
    }

    @Test func reportWithoutANonceIsRejected() {
        #expect(throws: SessionReport.AttestationError.missingNonce) {
            try report(nonce: nil).attestationPayload()
        }
    }
}
