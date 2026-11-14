// swift-tools-version: 6.0
//
//  Package.swift
//  JailbreakDetector
//
//  Created by Roman Croitor on 12.11.2026.
//

import PackageDescription

let package = Package(
    name: "JailbreakDetector",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "JailbreakDetector", targets: ["JailbreakDetector"]),
        .library(name: "JailbreakDetectorHardening", targets: ["JailbreakDetectorHardening"]),
        .library(name: "SessionIntegrity", targets: ["SessionIntegrity"]),
    ],
    targets: [
        .target(
            name: "JailbreakDetector",
            resources: [.process("Resources/PrivacyInfo.xcprivacy")]
        ),
        .target(name: "CJailbreakProbes"),
        .target(
            name: "JailbreakDetectorHardening",
            dependencies: ["JailbreakDetector", "CJailbreakProbes"]
        ),
        .target(
            name: "SessionIntegrity",
            dependencies: ["JailbreakDetector"],
            resources: [.process("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "JailbreakDetectorTests",
            dependencies: ["JailbreakDetector"]
        ),
        .testTarget(
            name: "JailbreakDetectorHardeningTests",
            dependencies: ["JailbreakDetector", "JailbreakDetectorHardening", "CJailbreakProbes"]
        ),
        .testTarget(
            name: "SessionIntegrityTests",
            dependencies: ["JailbreakDetector", "SessionIntegrity"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
