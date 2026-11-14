//
//  SessionReport.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import Foundation
import JailbreakDetector

/// The session risk signals observed at one moment.
///
/// The report has no verdict. None of the signals is conclusive on its own, so a backend should weigh them
/// together with what the user is doing, such as adding a payee or sending a large amount.
public struct SessionReport: Sendable, Hashable, Codable {
    /// A signal that is active.
    public struct Signal: Sendable, Hashable, Codable {
        /// The signal.
        public let id: SessionSignalID
        /// What was observed, such as `connected` for a call, or `nil` when there is nothing to add.
        public let detail: String?

        public init(id: SessionSignalID, detail: String? = nil) {
            self.id = id
            self.detail = detail
        }
    }

    /// Where the evaluation ran. Nothing is evaluated on a Mac.
    public let environment: JailbreakReport.Environment
    /// The signals that were checked, in evaluation order. A signal missing here was not checked, which is
    /// different from being checked and found inactive.
    public let evaluated: [SessionSignalID]
    /// The signals that are active, in evaluation order.
    public let active: [Signal]
    /// The value the server issued for this evaluation, which lets it reject a replayed report.
    public let nonce: Data?

    public init(
        environment: JailbreakReport.Environment,
        evaluated: [SessionSignalID],
        active: [Signal],
        nonce: Data? = nil
    ) {
        self.environment = environment
        self.evaluated = evaluated
        self.active = active
        self.nonce = nonce
    }

    /// Whether the signal is active.
    public func isActive(_ id: SessionSignalID) -> Bool {
        active.contains { $0.id == id }
    }
}

extension SessionReport {
    /// Why a report could not be encoded for attestation.
    public enum AttestationError: Error, Hashable, Sendable {
        /// The report was evaluated without a nonce, so the server could not tell it from a replay.
        case missingNonce
    }

    /// Encodes the report for the server and computes the digest to have App Attest sign.
    ///
    /// Throws ``AttestationError/missingNonce`` if the evaluation was not given a nonce.
    public func attestationPayload() throws -> AttestationPayload {
        guard nonce != nil else { throw AttestationError.missingNonce }
        return try AttestationPayload(encoding: self)
    }
}
