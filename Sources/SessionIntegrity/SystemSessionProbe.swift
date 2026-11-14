//
//  SystemSessionProbe.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 14.11.2026.
//

import CallKit
import CFNetwork
import Darwin
import Foundation
import JailbreakDetector
import MachO
import UIKit

/// Reads the real session through UIKit, CallKit, sysctl, CFNetwork and dyld.
///
/// None of these is a required-reason API. The call observer is only created when the active call signal is
/// evaluated, which the monitor never does in China.
@available(iOSApplicationExtension, unavailable)
@MainActor
final class SystemSessionProbe: SessionProbe {
    private static let tunnelInterfacePrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]
    private static let automationImageFragments = ["/XCTest.framework/", "/XCTAutomationSupport.framework/", "WebDriverAgentLib"]
    private static let automationEnvironmentVariables = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    private lazy var callObserver = CXCallObserver()
    private var callRelay: CallChangeRelay?
    private var notificationTokens: [any NSObjectProtocol] = []
    private var observedScenes: [ObjectIdentifier: () -> Void] = [:]

    var environment: JailbreakReport.Environment { .current }

    var regionCode: String? {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier
        }
        return Locale.current.regionCode
    }

    // MARK: - Signals

    func screenCapture() -> SignalState {
        if #available(iOS 17, *) {
            let captured = windowScenes.contains { $0.traitCollection.sceneCaptureState == .active }
            return captured ? .active(detail: nil) : .inactive
        }
        return UIScreen.main.isCaptured ? .active(detail: nil) : .inactive
    }

    func activeCall() -> SignalState {
        let calls = callObserver.calls.filter { !$0.hasEnded }
        if calls.contains(where: { $0.hasConnected && !$0.isOnHold }) { return .active(detail: "connected") }
        if calls.contains(where: { $0.isOnHold }) { return .active(detail: "on-hold") }
        if !calls.isEmpty { return .active(detail: "ringing-or-dialing") }
        return .inactive
    }

    func debugger() -> SignalState {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return .inactive }
        return info.kp_proc.p_flag & P_TRACED != 0 ? .active(detail: nil) : .inactive
    }

    func networkProxy() -> SignalState {
        let settings = proxySettings()
        if Self.isEnabled(settings[kCFNetworkProxiesHTTPEnable as String]) { return .active(detail: "http") }
        if Self.isEnabled(settings[kCFNetworkProxiesProxyAutoConfigEnable as String]) {
            return .active(detail: "auto-config")
        }
        return .inactive
    }

    func vpn() -> SignalState {
        let interfaces = (proxySettings()["__SCOPED__"] as? [String: Any])?.keys.sorted() ?? []
        for interface in interfaces {
            if let prefix = Self.tunnelInterfacePrefixes.first(where: { interface.hasPrefix($0) }) {
                return .active(detail: prefix)
            }
        }
        return .inactive
    }

    func automation() -> SignalState {
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index).map({ String(cString: $0) }) else { continue }
            if let fragment = Self.automationImageFragments.first(where: { name.contains($0) }) {
                return .active(detail: fragment.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            }
        }
        if let variable = Self.automationEnvironmentVariables.first(where: { getenv($0) != nil }) {
            return .active(detail: variable)
        }
        return .inactive
    }

    func assistiveInput() -> SignalState {
        var features: [String] = []
        if UIAccessibility.isSwitchControlRunning { features.append("switch-control") }
        if UIAccessibility.isAssistiveTouchRunning { features.append("assistive-touch") }
        return features.isEmpty ? .inactive : .active(detail: features.joined(separator: ","))
    }

    // MARK: - Changes

    func changes(observing signals: Set<SessionSignalID>) -> AsyncStream<Void> {
        stopObserving()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))

        var names: [Notification.Name] = [UIApplication.didBecomeActiveNotification]
        if signals.contains(.screenCapture) {
            if #available(iOS 17, *) {
                names.append(UIScene.willConnectNotification)
                windowScenes.forEach { observeCaptureState(of: $0, continuation: continuation) }
            } else {
                names.append(UIScreen.capturedDidChangeNotification)
            }
        }
        if signals.contains(.assistiveInput) {
            names += [
                UIAccessibility.switchControlStatusDidChangeNotification,
                UIAccessibility.assistiveTouchStatusDidChangeNotification,
            ]
        }
        if signals.contains(.activeCall) {
            let relay = CallChangeRelay(continuation: continuation)
            callObserver.setDelegate(relay, queue: .main)
            callRelay = relay
        }

        notificationTokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if #available(iOS 17, *), let scene = notification.object as? UIWindowScene {
                    MainActor.assumeIsolated { self?.observeCaptureState(of: scene, continuation: continuation) }
                }
                continuation.yield()
            }
        }

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stopObserving() }
        }
        return stream
    }

    private func stopObserving() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens = []
        observedScenes.values.forEach { $0() }
        observedScenes = [:]
        if callRelay != nil {
            callObserver.setDelegate(nil, queue: nil)
            callRelay = nil
        }
    }

    @available(iOS 17, *)
    private func observeCaptureState(of scene: UIWindowScene, continuation: AsyncStream<Void>.Continuation) {
        let key = ObjectIdentifier(scene)
        guard observedScenes[key] == nil else { return }
        let registration = scene.registerForTraitChanges([UITraitSceneCaptureState.self]) { (_: UIWindowScene, _) in
            continuation.yield()
        }
        observedScenes[key] = { [weak scene] in scene?.unregisterForTraitChanges(registration) }
    }

    // MARK: - Helpers

    private var windowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    private func proxySettings() -> [String: Any] {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }
}

/// Forwards call changes to the change stream. The call observer holds its delegate weakly.
private final class CallChangeRelay: NSObject, CXCallObserverDelegate {
    let continuation: AsyncStream<Void>.Continuation

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        continuation.yield()
    }
}
