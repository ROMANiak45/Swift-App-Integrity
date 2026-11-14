//
//  Configuration.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

@available(iOSApplicationExtension, unavailable)
extension SessionIntegrity {
    /// Selects which signals are evaluated.
    public struct Configuration: Sendable {
        /// The signals to evaluate. Defaults to ``SessionSignalID/recommended``.
        public var signals: Set<SessionSignalID>

        public init(signals: Set<SessionSignalID> = SessionSignalID.recommended) {
            self.signals = signals
        }

        /// The recommended signals: screen capture, an active call and an attached debugger.
        public static let `default` = Configuration()

        /// Every signal, including the noisier network signals and assistive input.
        public static let all = Configuration(signals: SessionSignalID.all)
    }
}
