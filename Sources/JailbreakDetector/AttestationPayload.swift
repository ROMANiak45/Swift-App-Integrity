//
//  AttestationPayload.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 13.11.2026.
//

import CryptoKit
import Foundation

/// A report encoded for the server, with the digest to have App Attest sign.
///
/// Send ``data`` to the server unchanged. Pass ``digest`` as the `clientDataHash` of
/// `DCAppAttestService.generateAssertion(_:clientDataHash:)`; the server recomputes the SHA-256 of the
/// bytes it received, so no canonical encoding is needed.
public struct AttestationPayload: Sendable, Hashable {
    /// The JSON-encoded report.
    public let data: Data
    /// The SHA-256 digest of ``data``.
    public let digest: Data

    /// Encodes the value as JSON with sorted keys, so the same value always gives the same bytes.
    package init(encoding value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        data = try encoder.encode(value)
        digest = Data(SHA256.hash(data: data))
    }
}

extension JailbreakReport {
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
