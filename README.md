# Swift App Integrity

[![CI](https://github.com/ROMANiak45/Swift-App-Integrity/actions/workflows/ci.yml/badge.svg)](https://github.com/ROMANiak45/Swift-App-Integrity/actions/workflows/ci.yml)

A Swift package that gives an iPhone or iPad app two kinds of integrity signal:

- **Jailbreak detection** (`JailbreakDetector`, plus the opt-in `JailbreakDetectorHardening`) reports whether the device is jailbroken. It runs several independent checks and returns every finding, so an app or its backend can decide how to respond instead of trusting a single boolean.
- **Session integrity** (`SessionIntegrity`) reports which session risk signals are active, such as a shared screen or a phone call in progress, which often accompany scams where a fraudster coaches the user.

Jailbreaking is the iOS equivalent of rooting on Android. This package covers iOS and iPadOS only.

The repository was called `Swift-Jailbreak-Detector` until 0.3.0. See [Migrating from 0.2.0](#migrating-from-020).

## Requirements

- iOS 15 or iPadOS 15 and later
- Swift 6 toolchain (Xcode 16 or later)
- No third-party dependencies

## Installation

Add the package in Xcode with **File > Add Package Dependencies** and this URL:

```
https://github.com/ROMANiak45/Swift-App-Integrity.git
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ROMANiak45/Swift-App-Integrity.git", from: "0.3.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "JailbreakDetector", package: "Swift-App-Integrity"),
            // Optional:
            // .product(name: "JailbreakDetectorHardening", package: "Swift-App-Integrity"),
            // .product(name: "SessionIntegrity", package: "Swift-App-Integrity"),
        ]
    ),
]
```

Each product is linked only if the app lists it.

## Usage

The quickest check returns a boolean:

```swift
import JailbreakDetector

if JailbreakDetector.isJailbroken() {
    // Block sensitive features.
}
```

For anything beyond a yes or no, evaluate and read the report:

```swift
let report = await JailbreakDetector.evaluate()

switch report.verdict {
case .clean:
    break
case .suspicious:
    // Unusual, but not conclusive. Send the report to your backend for risk scoring.
    break
case .jailbroken:
    // At least one conclusive finding.
    break
}

for finding in report.findings {
    print(finding.check, finding.confidence, finding.detail)
}
```

`evaluate` has two overloads:

- **Synchronous** runs on any thread and does not touch UIKit. It skips the URL scheme check.
- **Asynchronous** also runs the URL scheme check on the main actor. It is unavailable in app extensions.

Inside an `async` function Swift always picks the asynchronous overload, so the call needs `await` there, even with a configuration such as `.hardened`.

`JailbreakReport` is `Codable`, so it can be sent to a backend as is:

```swift
let body = try JSONEncoder().encode(report)
```

### Verdicts

Each finding is either `definitive` or `suspicious`.

- `jailbroken` means at least one finding is definitive.
- `suspicious` means there are findings, but none is definitive.
- `clean` means there are no findings.

`isJailbroken()` returns `true` only for a `jailbroken` verdict.

### URL scheme check

The asynchronous evaluation asks the system whether a jailbreak app is installed. iOS only answers for schemes the host app declares, so add these to the app's `Info.plist`:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>cydia</string>
    <string>sileo</string>
    <string>zbra</string>
    <string>filza</string>
</array>
```

Schemes that are not declared are skipped. Nothing fails without them.

### Configuration

```swift
var configuration = JailbreakDetector.Configuration.default

// Run only some of the built-in checks.
configuration.checks = [.fileArtifacts, .loadedImages, .hookIntegrity]

// Report the Simulator as jailbroken to exercise the blocked-device flow during development.
configuration.simulatorPolicy = .reportJailbroken

let report = JailbreakDetector.evaluate(configuration)
```

To add a check of your own, conform a type to `JailbreakCheck` and append it to `configuration.additionalChecks`. Its `run(_:)` method receives a `JailbreakCheckContext` with the configured indicators.

## Private and remote indicators

The built-in paths, library names and schemes are public, so a bypass tweak can be written against them. `configuration.indicators` lets you change what the checks look for.

### Private indicators

Keep extra indicators in your own private repository and merge them with the built-in set. Merging only ever adds: a path in both sets keeps the stronger confidence.

```swift
let privateIndicators = IndicatorSet(
    files: [.init(path: "/var/some-new-jailbreak", confidence: .definitive)],
    imageNames: ["somebypass.dylib"]
)
configuration.indicators = IndicatorSet.builtIn.merging(privateIndicators)
```

Assigning a set without merging replaces the built-in one entirely, which is how you remove an indicator.

### Signed lists from your server

To cover a new jailbreak without an app release, deliver the indicators as JSON signed with a P-256 key. The app ships only the public key and rejects any list that is not signed with the matching private key, so whoever can tamper with the response still cannot empty the list.

The JSON has the same fields as `IndicatorSet`. Missing fields are empty, and `confidence` is `definitive` or `suspicious`:

```json
{
  "version": 12,
  "files": [{ "path": "/var/some-new-jailbreak", "confidence": "definitive" }],
  "symbolicLinks": [],
  "environmentVariables": ["SOME_NEW_JB"],
  "imageFragments": ["somehook"],
  "imageNames": ["somebypass.dylib"],
  "urlSchemes": [],
  "restrictedDirectories": []
}
```

Create the key pair once, keep `key.pem` on the server side, and sign each list:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out key.pem
openssl ec -in key.pem -pubout -out public.pem
openssl dgst -sha256 -sign key.pem -out indicators.sig indicators.json
```

In the app, fetch the JSON and the signature with your own URL session, then verify them. The package itself makes no network requests and stores nothing.

```swift
import CryptoKit

let publicKey = try P256.Signing.PublicKey(pemRepresentation: publicKeyPEM)
let delivered = try IndicatorSet.verified(
    payload: jsonData,
    signature: signatureData,
    publicKey: publicKey,
    minimumVersion: lastAcceptedVersion
)
lastAcceptedVersion = delivered.version
configuration.indicators = IndicatorSet.builtIn.merging(delivered)
```

`minimumVersion` rejects a list older than the newest one the app has accepted, so an attacker cannot replay an old, correctly signed list. Store `lastAcceptedVersion` wherever you keep similar app state. Verification throws `IndicatorSet.VerificationError` when the signature is malformed or wrong, the payload is not an indicator set, or the version is too old.

## Binding a report to your server

A report the app sends to your server could be one captured earlier on a clean device. To rule that out, have the server issue a single-use nonce, pass it to the evaluation, and sign the result with [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity):

```swift
import DeviceCheck

let report = await JailbreakDetector.evaluate(configuration, nonce: serverNonce)
let payload = try report.attestationPayload()
let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: payload.digest)
// Send payload.data and assertion to the server.
```

`attestationPayload()` throws `JailbreakReport.AttestationError.missingNonce` if the evaluation had no nonce. The report also records `indicatorVersion`, the version of the set the checks used.

On the server:

1. Verify the assertion against the App Attest key registered for this device, using the SHA-256 of the `data` bytes exactly as received as the client data hash.
2. Decode the JSON and check that `nonce` is the one you issued for this session and has not been used before.
3. Check that `indicatorVersion` is the current version of your signed list.
4. Score `findings` on the server, rather than trusting the app's `verdict` alone.

App Attest proves the request came from your genuine app on genuine Apple hardware. It does not detect a jailbreak, and a tweak injected into your app can still alter the report before it is signed.

## Checks

The core product, `JailbreakDetector`, uses public API only.

| Check | What it looks for |
| --- | --- |
| `fileArtifacts` | Files installed by rootful and rootless jailbreaks, their package managers and hooking frameworks |
| `symbolicLinks` | Symbolic links at paths such as `/var/jb` that are absent or real directories on a stock system |
| `sandboxEscape` | Being able to create a file in `/`, `/private/`, `/private/var/`, `/private/var/mobile/`, `/private/var/root/`, `/Applications/`, `/Library/`, `/usr/` or `/bin/`. The probe file is empty, uniquely named and removed at once |
| `restrictedDirectories` | Being able to list system directories the sandbox denies, such as `/private/var/root`, `/private/var/mobile`, `/private/var/db` and `/private/var/log`, and roothide's `.jbroot-*` directories |
| `loadedImages` | Substrate, Substitute, libhooker, ElleKit, Frida and known bypass tweaks loaded into the process, plus any library loaded from outside the system and the app bundle |
| `environmentVariables` | Variables set by jailbreaks, and foreign libraries in `DYLD_INSERT_LIBRARIES` |
| `hookIntegrity` | System functions and Objective-C methods the other checks use being redirected to foreign code |
| `urlSchemes` | Installed apps that handle `cydia://`, `sileo://`, `zbra://` or `filza://` |

### System folder access

Writing outside the container is a definitive finding, because the sandbox denies it on every stock device. Listing a restricted directory is only suspicious: stock iOS lets apps read some system locations, and which ones varies between iOS versions. For the same reason the package does not try to list `/` itself, and it never probes folders holding personal data such as messages, contacts or photos.

The restricted directories are part of `IndicatorSet`, so a directory that turns out to be readable on a new iOS version can be removed through your signed list without an app release. The list has not yet been confirmed on physical stock devices across iOS 15 to 27; until it is, treat these findings as a risk signal rather than a reason to block.

## Hardening product

`JailbreakDetectorHardening` is a separate, opt-in product with checks that are harder to bypass.

| Check | What it does |
| --- | --- |
| `directSyscalls` | Repeats the file, symbolic link and restricted directory lookups with system calls issued straight to the kernel, and reports anything libc or Foundation hides as definitive |
| `functionPrologues` | Reads the first instructions of libc functions to find inline hooks |
| `fork` | Tries to fork the process, which the sandbox denies on a stock system |
| `loopbackPorts` | Connects to local ports 22, 44 and 27042, used by SSH servers and Frida |

None of these use private API, but they are the kind of behaviour App Review may question. That is why they live in a separate product: an app that does not link it does not ship the code. Decide with your own review history in mind.

```swift
.product(name: "JailbreakDetectorHardening", package: "Swift-App-Integrity"),
```

```swift
import JailbreakDetector
import JailbreakDetectorHardening

let report = JailbreakDetector.evaluate(.hardened)
```

The loopback port check can block the calling thread for up to half a second, so call it off the main thread.

## Session integrity

`SessionIntegrity` answers a different question from jailbreak detection: is something happening right now that often accompanies a manipulated session? In a typical scam the fraudster phones the victim, asks them to share their screen or install a remote-control app, and talks them through a transfer. The device is not jailbroken, but the session is not the user's own.

```swift
.product(name: "SessionIntegrity", package: "Swift-App-Integrity"),
```

### Signals

| Signal | Active when | Detail | Innocent explanations |
| --- | --- | --- | --- |
| `screenCapture` | The screen is recorded, mirrored or remotely controlled | none | Recording a tutorial, AirPlay to a TV |
| `activeCall` | A phone or VoIP call is in progress | `connected`, `on-hold` or `ringing-or-dialing` | Very common |
| `debugger` | A debugger is attached to the process | none | Every run from Xcode |
| `networkProxy` | An HTTP proxy or a proxy auto-configuration script is set | `http` or `auto-config` | Corporate networks |
| `vpn` | A tunnel interface is active | `utun`, `ipsec`, `ppp`, `tun` or `tap` | Corporate and privacy VPNs |
| `automation` | UI test automation libraries are loaded into the process | The library or variable found | UI tests |
| `assistiveInput` | Switch Control or AssistiveTouch is running | `switch-control`, `assistive-touch` or both | People who rely on them |

The system does not say which kind of screen capture is active. The proxy address and VPN details are never read. `automation` only sees libraries loaded into the app itself; a bot that drives the app from another process or device is invisible to it.

### Usage

Evaluate once, just before a sensitive action:

```swift
import SessionIntegrity

let report = SessionIntegrity.evaluate(nonce: serverNonce)
if report.isActive(.screenCapture) && report.isActive(.activeCall) {
    // Pause and warn the user before confirming the payment.
}
```

Or observe changes for as long as a screen is visible:

```swift
.task {
    for await report in SessionIntegrity.reports() {
        sensitiveContentHidden = report.isActive(.screenCapture)
    }
}
```

The stream yields the current report at once and then a new one whenever it changes. Screen capture, calls and assistive input are observed as they change; the other signals are read again with every change and whenever the app becomes active. Observation stops when the consuming task is cancelled.

Both calls run on the main actor, and neither is available in app extensions. Signals are evaluated on a device and in the Simulator, so you can build your warning flow there, but not on a Mac.

### Choosing signals

The default configuration evaluates `screenCapture`, `activeCall` and `debugger`, the signals most specific to a manipulated session. Pick any combination:

```swift
// Every signal.
let everything = SessionIntegrity.evaluate(.all)

// Your own selection.
let configuration = SessionIntegrity.Configuration(signals: [.screenCapture, .activeCall, .vpn])
let report = SessionIntegrity.evaluate(configuration)
```

`report.evaluated` lists the signals that were checked, so the server can tell "not active" from "not checked".

### What to do with the report

The report has no verdict, on purpose: a call or a shared screen alone is normal. Combine the signals with what the user is doing, preferably on the server. A call plus a shared screen while adding a new payee and sending a large amount is a strong scam pattern; the same signals while reading a balance are not.

`SessionReport` is `Codable`, carries the nonce, and has `attestationPayload()` for App Attest, exactly like `JailbreakReport` (see [Binding a report to your server](#binding-a-report-to-your-server)).

Prefer friction to blocking: a warning, a delay, or a confirmation step. Use neutral language, such as "Your screen is being shared. Some details are hidden while it is."

### Phone calls in China

Apple does not approve apps with CallKit active in China. When the device region is China, `activeCall` is not evaluated, no call observer is created, and the signal is missing from `report.evaluated`. Mention this in your App Review notes if you ship there.

### Assistive input

Switch Control and AssistiveTouch can drive input, which is why remote-control scams sometimes rely on them, but most people who have them enabled depend on them. Do not block or penalise users because of this signal alone. It is not part of the default configuration.

### Custom keyboards

The package does not report custom keyboards. The only API for it is a required-reason API whose result may not leave the device. To keep third-party keyboards away from sensitive fields, refuse them in your app delegate instead:

```swift
func application(
    _ application: UIApplication,
    shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
) -> Bool {
    extensionPointIdentifier != .keyboard
}
```

## Simulator and Mac

No jailbreak checks run in the Simulator, in Mac Catalyst, or when an iOS app runs on an Apple silicon Mac, because a Mac's file system looks like a jailbreak. The report says where it ran in `report.environment` and has a `clean` verdict. If your app should not run on a Mac at all, treat `.mac` accordingly.

Session signals are evaluated in the Simulator, and nothing is evaluated on a Mac.

## Privacy

The package collects no data, stores nothing, and makes no network requests other than the local port connections in the hardening product. Fetching a signed indicator list is up to the app. Each product that ships code with system access has a privacy manifest, and none uses a required-reason API.

If your app sends a report to its server, that is your app's data collection: declare it in your own privacy details. A session report contains only which signals are active and short fixed details, never proxy addresses or call information beyond its state.

## Limitations

- **Detection on the device can still be bypassed.** Private and signed indicator lists mean a generic bypass tweak built from this repository no longer knows everything the app looks for, and a nonce stops a captured report from being replayed. An attacker who instruments your running app can still log the paths it checks, and a hook inside the genuine app can forge a clean report with a fresh nonce before App Attest signs it. Treat the report as one risk signal.
- **Keep the decision on the server.** Score the findings there, and keep transaction limits, step-up authentication and fraud monitoring in place, since they still work when the app lies.
- **It does not cover every attack.** Re-signed or modified builds are out of scope. Session integrity reports known signals; it is not behavioural biometrics, it cannot scan for malware, and it cannot see a bot driving the app from outside the process.
- **Session signals can be faked too.** On a jailbroken or instrumented device, an attacker can hide a shared screen or a call from the app, just as they can hide a jailbreak.
- **It has not been run on real devices.** It is tested in the iOS Simulator and against scripted clean, rootful, rootless, roothide, hooked and manipulated sessions. Before relying on it in production, run it on a range of stock devices to confirm there are no false positives, and on a jailbroken device to confirm detection. For session integrity in particular, confirm that `screenCapture` turns on during FaceTime screen sharing and remote control, and that `vpn` stays off on devices without a VPN, including with iCloud Private Relay.

## Migrating from 0.2.0

- **The repository is now `Swift-App-Integrity`.** GitHub redirects the old URL, so existing projects keep resolving. When you update, change the URL and the `package:` argument together:

  ```swift
  .package(url: "https://github.com/ROMANiak45/Swift-App-Integrity.git", from: "0.3.0"),
  .product(name: "JailbreakDetector", package: "Swift-App-Integrity"),
  ```

  Do not mix the old and new URLs in one dependency graph, because Swift Package Manager treats them as different packages.
- Product and module names are unchanged, so no `import` changes.
- `SessionIntegrity` is a new, opt-in product. Nothing in `JailbreakDetector` or `JailbreakDetectorHardening` changed.

## Migrating from 0.1.0

- `JailbreakCheck.run()` is now `run(_ context: JailbreakCheckContext)`. Custom checks gain the parameter and can read `context.indicators`.
- `JailbreakReport` has two new fields, `indicatorVersion` and `nonce`. A server that decodes reports should accept them.
- The sandbox escape and restricted directory checks probe more locations, so a device may report findings it did not report before.

## License

MIT. See [LICENSE](LICENSE).
