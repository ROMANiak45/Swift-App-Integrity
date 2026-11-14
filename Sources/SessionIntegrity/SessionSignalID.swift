//
//  SessionSignalID.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

/// Identifies a session risk signal.
public struct SessionSignalID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

extension SessionSignalID {
    /// The screen is being recorded, mirrored or remotely controlled. The system does not say which.
    public static let screenCapture = SessionSignalID(rawValue: "screen-capture")
    /// A phone or VoIP call is in progress. Never evaluated when the device region is China.
    public static let activeCall = SessionSignalID(rawValue: "active-call")
    /// A debugger is attached to the process. Always active when the app is run from Xcode.
    public static let debugger = SessionSignalID(rawValue: "debugger")
    /// An HTTP proxy or a proxy auto-configuration script is set.
    public static let networkProxy = SessionSignalID(rawValue: "network-proxy")
    /// A VPN tunnel is active.
    public static let vpn = SessionSignalID(rawValue: "vpn")
    /// UI test automation libraries are loaded into the process.
    public static let automation = SessionSignalID(rawValue: "automation")
    /// Switch Control or AssistiveTouch, the accessibility features that can drive input, is running.
    public static let assistiveInput = SessionSignalID(rawValue: "assistive-input")

    /// Screen capture, an active call and an attached debugger: the signals most specific to a manipulated
    /// session.
    public static let recommended: Set<SessionSignalID> = [.screenCapture, .activeCall, .debugger]

    /// Every signal the package can evaluate.
    public static let all = Set(evaluationOrder)

    /// The order in which signals are evaluated and reported.
    static let evaluationOrder: [SessionSignalID] = [
        .screenCapture,
        .activeCall,
        .debugger,
        .networkProxy,
        .vpn,
        .automation,
        .assistiveInput,
    ]
}
