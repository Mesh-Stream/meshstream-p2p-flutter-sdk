# MeshStream Flutter SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish `meshstream_p2p` 1.0.0, a Flutter Android/iOS P2P playback-url binding whose public contract matches the MeshStream React Native 1.0 SDK.

**Architecture:** A single Flutter plugin exposes a Dart facade around typed Pigeon request/response calls and an EventChannel broadcast stream. Kotlin and Swift implementations own isolated native client/session maps and adapt MeshStream Android SDK and MeshStreamKit respectively; the Dart layer owns validation, lifecycle guards, model conversion, exception mapping, and event filtering.

**Tech Stack:** Flutter 3.22+, Dart 3.4+, Pigeon, EventChannel, Kotlin, Swift, Gradle, CocoaPods/XCTest, `io.meshstream:meshstream-android-sdk:1.0.2`, `MeshStreamKit = 1.0.2`, `video_player` example.

**Spec:** `docs/superpowers/specs/2026-10-21-flutter-sdk-design.md`

## Global Constraints

- Publish exactly one package named `meshstream_p2p`, with no federated subpackages in 1.0.0.
- Require Flutter 3.22+ and Dart 3.4+; support Android API 24+ and iOS 13+ only.
- Keep the Android and iOS dependency versions fixed at `io.meshstream:meshstream-android-sdk:1.0.2` and `MeshStreamKit = 1.0.2`.
- Match the approved React Native 1.0 public models, operations, unavailable reasons, event names, and client/session isolation semantics.
- Do not embed a player, private SDK binary, Key, credential, or private media URL.
- Pigeon is used for finite request/response operations; EventChannel is used for asynchronous native events.
- Event buffering is capped at eight events per native session and 64 pending native sessions; closed-session events are discarded.
- Every close operation is idempotent; closing a client closes its sessions and never closes another client's resources.

---

## File Structure

| Path | Responsibility |
|---|---|
| `pubspec.yaml` | Package metadata, SDK floors, plugin declaration, runtime/dev dependencies. |
| `analysis_options.yaml` | Flutter lints and generated-code exclusions. |
| `pigeons/meshstream_api.dart` | The source contract for generated Pigeon messages and host API calls. |
| `tool/generate_pigeon.dart` | Reproducible generation entry point for Dart/Kotlin/Swift bridge files. |
| `lib/meshstream_p2p.dart` | Supported library exports only. |
| `lib/src/models.dart` | Immutable public models, enums, and typed event payloads. |
| `lib/src/meshstream_exception.dart` | Stable Dart exception type and error-code conversion. |
| `lib/src/platform/meshstream_platform.dart` | Internal platform interface and test injection seam. |
| `lib/src/platform/pigeon_meshstream_platform.dart` | Pigeon/EventChannel adapter and raw-message conversion. |
| `lib/src/meshstream.dart` | `MeshStream.create`, global event stream, and test reset hook. |
| `lib/src/meshstream_client.dart` | Client lifecycle and session creation. |
| `lib/src/meshstream_playback_session.dart` | Session lifecycle and playback operations. |
| `test/models_test.dart` | Public model and validation tests. |
| `test/meshstream_client_test.dart` | Client/session lifecycle tests using a fake platform. |
| `test/events_test.dart` | Event conversion and filtering tests. |
| `test/support/fake_meshstream_platform.dart` | Deterministic platform fake shared by Dart tests. |
| `android/build.gradle` | Android plugin configuration, MeshStream repository/dependency, API 24 floor. |
| `android/src/main/kotlin/net/meshstream/flutter/MeshStreamP2PPlugin.kt` | Flutter engine attachment, Pigeon registration, EventChannel wiring, resource cleanup. |
| `android/src/main/kotlin/net/meshstream/flutter/MeshStreamHostApi.kt` | Kotlin client/session map and MeshStream Android SDK adapter. |
| `android/src/test/.../MeshStreamHostApiTest.kt` | Kotlin conversion, isolation, cleanup, and buffered-event tests. |
| `ios/meshstream_p2p.podspec` | iOS 13 deployment target and MeshStreamKit CocoaPods dependency. |
| `ios/Classes/MeshStreamP2PPlugin.swift` | Flutter plugin registration, Pigeon/EventChannel wiring, engine detach cleanup. |
| `ios/Classes/MeshStreamHostApi.swift` | Swift client/session map and MeshStreamKit adapter. |
| `ios/Tests/MeshStreamHostApiTests.swift` | XCTest conversion, isolation, cleanup, and buffered-event tests. |
| `example/` | Executable Flutter app using `video_player` and displaying SDK telemetry. |
| `README.md`, `README.zh-CN.md` | Installation and integration documentation. |
| `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md` | Release and contribution artifacts. |
| `.github/workflows/ci.yml` | Formatting, analysis, Dart tests, Android build, and iOS pod/build validation. |

### Task 1: Bootstrap a reproducible Flutter plugin repository

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `lib/meshstream_p2p.dart`, `android/`, `ios/`, `example/`, `.gitignore`
- Create: `tool/generate_pigeon.dart`
- Test: `test/plugin_bootstrap_test.dart`

**Interfaces:**
- Produces the `meshstream_p2p` package root consumed by every later task.
- Produces `tool/generate_pigeon.dart`, invoked by later Pigeon-bridge tasks as `dart run tool/generate_pigeon.dart`.

- [ ] **Step 1: Verify the Flutter toolchain meets the package floor**

Run: `flutter --version && dart --version`

Expected: Flutter is at least 3.22 and the bundled Dart is at least 3.4. At planning time the local shell did not have a `flutter` executable, so install/select an eligible Flutter SDK before continuing rather than lowering the stated compatibility floor.

- [ ] **Step 2: Generate the initial plugin skeleton with Android and iOS only**

Run from the repository root:

```bash
flutter create --template=plugin --platforms=android,ios --org net.meshstream --project-name meshstream_p2p .
```

Expected: Flutter creates Dart, Android, iOS, example, and test roots without deleting `docs/superpowers/`.

- [ ] **Step 3: Write the package metadata and dependency policy**

Set the relevant `pubspec.yaml` values to:

```yaml
name: meshstream_p2p
description: MeshStream P2P playback acceleration for Flutter.
version: 1.0.0
environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'
dependencies:
  flutter:
    sdk: flutter
  plugin_platform_interface: ^2.1.8
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  pigeon: ^22.7.2
flutter:
  plugin:
    platforms:
      android:
        package: net.meshstream.flutter
        pluginClass: MeshStreamP2PPlugin
      ios:
        pluginClass: MeshStreamP2PPlugin
```

Pin only the native MeshStream SDK versions in platform build metadata; do not add Keys or media URLs to any manifest or configuration file.

- [ ] **Step 4: Add a generation script that fails on stale bridge output**

Create `tool/generate_pigeon.dart` with a `main()` that calls `PigeonOptions` for `pigeons/meshstream_api.dart`, writes Dart output to `lib/src/pigeon/generated/meshstream_api.g.dart`, Kotlin output to `android/src/main/kotlin/net/meshstream/flutter/generated/MeshStreamApi.g.kt`, and Swift output to `ios/Classes/Generated/MeshStreamApi.g.swift`. Use Pigeon package `net.meshstream.flutter`, Dart package `meshstream_p2p`, and copyright header `// Generated file. Do not edit by hand.`.

- [ ] **Step 5: Add a failing package identity test**

Create `test/plugin_bootstrap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';

void main() {
  test('exports the MeshStream facade', () {
    expect(MeshStream, isNotNull);
  });
}
```

- [ ] **Step 6: Run the bootstrap test to confirm the initial public export is missing**

Run: `flutter test test/plugin_bootstrap_test.dart`

Expected: FAIL because `MeshStream` is not exported yet.

- [ ] **Step 7: Add a temporary public facade declaration sufficient for the bootstrap test**

Create `lib/meshstream_p2p.dart`:

```dart
library meshstream_p2p;

export 'src/meshstream.dart';
```

Create `lib/src/meshstream.dart`:

```dart
abstract final class MeshStream {
  const MeshStream._();
}
```

- [ ] **Step 8: Format and run the bootstrap test**

Run: `dart format . && flutter test test/plugin_bootstrap_test.dart`

Expected: PASS.

- [ ] **Step 9: Commit the bootstrap deliverable**

```bash
git add .gitignore analysis_options.yaml pubspec.yaml lib android ios example test tool
git commit -m "chore: bootstrap Flutter plugin package"
```

### Task 2: Define and test the public Dart contract

**Files:**
- Create: `lib/src/models.dart`, `lib/src/meshstream_exception.dart`
- Modify: `lib/meshstream_p2p.dart`, `lib/src/meshstream.dart`
- Test: `test/models_test.dart`

**Interfaces:**
- Consumes: the package root from Task 1.
- Produces: `MeshStreamConfig`, `PlaybackSessionOptions`, `MeshStreamStatus`, `MeshStreamStats`, `MeshStreamDiagnostics`, `MeshStreamSessionInfo`, `MeshStreamEvent`, `MeshStreamException`, `MeshStreamMimeType`, `MeshStreamPlaybackMode`, `MeshStreamUnavailableReason`, and `MeshStreamEventName`.

- [ ] **Step 1: Write model/validation tests before the models**

Create tests for these exact expectations:

```dart
test('a config key must contain non-whitespace text', () {
  expect(() => MeshStreamConfig(key: '  '), throwsArgumentError);
});

test('session URL must contain non-whitespace text', () {
  expect(() => PlaybackSessionOptions(url: ''), throwsArgumentError);
});

test('event payload preserves client and session identity', () {
  final event = MeshStreamEvent.p2pReady(clientId: 'client-a', sessionId: 'session-a');
  expect((event.clientId, event.sessionId, event.type), ('client-a', 'session-a', MeshStreamEventName.p2pReady));
});

test('exception retains a stable code and native details', () {
  final error = MeshStreamException('UNKNOWN_SESSION', 'not found', {'sessionId': 's'});
  expect(error.code, 'UNKNOWN_SESSION');
  expect(error.details!['sessionId'], 's');
});
```

- [ ] **Step 2: Run the model tests to verify they fail**

Run: `flutter test test/models_test.dart`

Expected: FAIL because the public types do not yet exist.

- [ ] **Step 3: Implement immutable public types and complete enums**

In `lib/src/models.dart`, define `MeshStreamMimeType { m3u8, mpd, mp4, mp3 }`, `MeshStreamPlaybackMode { nativeP2p, nativeCdn }`, all 22 unavailable reasons listed in the spec, and all eight event names. Use `const` constructors and unmodifiable header maps. Make `MeshStreamConfig` and `PlaybackSessionOptions` validate trimmed required strings in their constructors. Define non-null numeric stats/diagnostics fields with zero values allowed and optional telemetry only where the spec marks it optional.

Give `MeshStreamEvent` a private const base constructor plus named constructors `peerCountChanged`, `playbackPrepared`, `p2pReady`, `p2pUnavailable`, `statistics`, `cdnFallback`, `trackerError`, and `peerConnectError`; each named constructor sets the matching `MeshStreamEventName` and only its legal optional payload fields.

In `lib/src/meshstream_exception.dart`, implement:

```dart
final class MeshStreamException implements Exception {
  const MeshStreamException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Map<String, Object?>? details;
  @override
  String toString() => 'MeshStreamException($code): $message';
}
```

- [ ] **Step 4: Export only the supported contract**

Add model and exception exports to `lib/meshstream_p2p.dart`; do not export Pigeon-generated files or platform adapters.

- [ ] **Step 5: Run model tests and static analysis**

Run: `dart format lib test && flutter test test/models_test.dart && flutter analyze`

Expected: PASS with no analyzer findings.

- [ ] **Step 6: Commit the public contract**

```bash
git add lib/meshstream_p2p.dart lib/src/models.dart lib/src/meshstream_exception.dart test/models_test.dart
git commit -m "feat: define Flutter SDK public contract"
```

### Task 3: Generate a typed native bridge and add a mockable platform seam

**Files:**
- Create: `pigeons/meshstream_api.dart`, `lib/src/platform/meshstream_platform.dart`, `lib/src/platform/pigeon_meshstream_platform.dart`
- Create: `lib/src/pigeon/generated/meshstream_api.g.dart`, `android/src/main/kotlin/net/meshstream/flutter/generated/MeshStreamApi.g.kt`, `ios/Classes/Generated/MeshStreamApi.g.swift`
- Create: `test/support/fake_meshstream_platform.dart`, `test/platform_adapter_test.dart`

**Interfaces:**
- Consumes: models and exception type from Task 2.
- Produces: internal `MeshStreamPlatform`, `PigeonMeshStreamPlatform`, `MeshStreamPlatform.instance`, and typed Pigeon messages for every native operation.

- [ ] **Step 1: Write a failing fake-platform mapping test**

Create a test proving the adapter exposes these operations:

```dart
expect(await platform.createClient(const MeshStreamConfig(key: 'key')), isA<NativeClientReply>());
expect(await platform.createPlaybackSession('c1', const PlaybackSessionOptions(url: 'https://cdn.example/video.m3u8')), isA<NativeSessionReply>());
await expectLater(platform.closeSession('c1', 's1'), completes);
```

- [ ] **Step 2: Run the adapter test to confirm the seam is absent**

Run: `flutter test test/platform_adapter_test.dart`

Expected: FAIL because `MeshStreamPlatform`, `NativeClientReply`, and `NativeSessionReply` are undefined.

- [ ] **Step 3: Define the Pigeon source contract**

In `pigeons/meshstream_api.dart`, use `@ConfigurePigeon(PigeonOptions(...))`, `@HostApi() abstract class MeshStreamHostApi`, and serializable API data classes. Define these host methods with async return values:

```dart
@async ApiClientReply createClient(ApiClientConfig config);
@async ApiSessionReply createPlaybackSession(String clientId, ApiPlaybackSessionOptions options);
@async bool preload(String clientId, String sessionId);
@async void setP2pEnabled(String clientId, String sessionId, bool enabled);
@async void updateBufferedDurationMs(String clientId, String sessionId, int durationMs);
@async void updateCurrentPositionMs(String clientId, String sessionId, int positionMs);
@async ApiStatus getStatus(String clientId);
@async ApiStats getStats(String clientId, String sessionId);
@async ApiDiagnostics getDiagnostics(String clientId, String sessionId);
@async void closeSession(String clientId, String sessionId);
@async void closeClient(String clientId);
```

Use primitive fields, nullable optional fields, `Map<String, String>` only for headers, and String wire values for enums so generated APIs stay stable across languages.

- [ ] **Step 4: Generate and check in all Pigeon output**

Run: `dart run tool/generate_pigeon.dart && git diff --check`

Expected: Dart, Kotlin, and Swift generated sources exist at the three paths declared in Task 1 with no whitespace errors.

- [ ] **Step 5: Implement the internal platform interface and Pigeon adapter**

Define `MeshStreamPlatform` as an abstract class with static `instance` initialized to `PigeonMeshStreamPlatform()`. It exposes typed model methods matching the host operations and a broadcast `Stream<MeshStreamEvent> get events`.

`PigeonMeshStreamPlatform` owns `MeshStreamHostApi()` and `const EventChannel('net.meshstream/meshstream_p2p/events')`. Convert raw Pigeon replies to Task 2 models. Catch `PlatformException` and throw `MeshStreamException(error.code, error.message ?? 'Native MeshStream operation failed.', error.details as Map<String, Object?>?)`.

- [ ] **Step 6: Implement the fake platform used by all Dart tests**

`FakeMeshStreamPlatform` stores calls, has a `StreamController<MeshStreamEvent>.broadcast()`, returns configured client/session replies, and exposes `emit(MeshStreamEvent event)`. It must not import Flutter services or generated bridge code.

- [ ] **Step 7: Run bridge-seam tests and analysis**

Run: `dart format pigeons tool lib test android ios && flutter test test/platform_adapter_test.dart && flutter analyze`

Expected: PASS.

- [ ] **Step 8: Commit the generated bridge and adapter seam**

```bash
git add pigeons tool lib/src/platform lib/src/pigeon android/src/main/kotlin/net/meshstream/flutter/generated ios/Classes/Generated test/support test/platform_adapter_test.dart
git commit -m "feat: add typed Flutter native bridge"
```

### Task 4: Implement the Dart facade, lifecycle protections, and filtered events

**Files:**
- Modify: `lib/src/meshstream.dart`, `lib/src/meshstream_client.dart`, `lib/src/meshstream_playback_session.dart`, `lib/meshstream_p2p.dart`
- Test: `test/meshstream_client_test.dart`, `test/events_test.dart`

**Interfaces:**
- Consumes: `MeshStreamPlatform`, models, and exceptions from Tasks 2-3.
- Produces: `MeshStream.create`, `MeshStream.events`, `MeshStream.eventsFor`, `MeshStreamClient`, and `MeshStreamPlaybackSession`.

- [ ] **Step 1: Write failing client/session lifecycle tests**

Cover these exact cases:

```dart
test('client creates an independent playback session', () async {
  final client = await MeshStream.create(const MeshStreamConfig(key: 'key'));
  final session = await client.createPlaybackSession(const PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'));
  expect((session.clientId, session.sessionId, session.playbackUrl), ('c1', 's1', 'http://127.0.0.1:9000/a.m3u8'));
});

test('closing a client closes its sessions once and rejects later use', () async {
  final client = await createClientWithOneSession();
  await client.close();
  await client.close();
  await expectLater(client.getStatus(), throwsA(isA<MeshStreamException>()));
});

test('session update values reject negative durations before native dispatch', () async {
  final session = await createSession();
  expect(() => session.updateBufferedDurationMs(-1), throwsArgumentError);
});
```

- [ ] **Step 2: Write failing event filtering tests**

Create events for two client/session pairs, subscribe with `MeshStream.eventsFor(clientId: 'c1', sessionId: 's1', type: MeshStreamEventName.p2pReady)`, and assert only that matching event arrives. Also assert `MeshStream.events.isBroadcast` is true.

- [ ] **Step 3: Run facade tests to verify they fail**

Run: `flutter test test/meshstream_client_test.dart test/events_test.dart`

Expected: FAIL because the client/session facade does not yet exist.

- [ ] **Step 4: Implement the facade and lifecycle state machine**

Implement `MeshStream.create` to validate through `MeshStreamConfig`, await `MeshStreamPlatform.instance.createClient`, and return `MeshStreamClient`.

Implement `MeshStreamClient` with `_closed` and `_closing` fields. Every operation calls a private `_withOpen<T>(Future<T> Function() operation)`, which throws `const MeshStreamException('CLIENT_CLOSED', 'MeshStream client is closed.')` when closed or closing. `close()` memoizes the native future so concurrent/double close calls share one native close operation.

Implement `MeshStreamPlaybackSession` identically with error code `SESSION_CLOSED`, delegation to the platform interface, and a synchronous `ArgumentError.value` check for negative position/buffer durations. `preload()` returns `Future<bool>`.

- [ ] **Step 5: Implement global and filtered event streams**

Expose:

```dart
static Stream<MeshStreamEvent> get events => MeshStreamPlatform.instance.events;

static Stream<MeshStreamEvent> eventsFor({
  String? clientId,
  String? sessionId,
  MeshStreamEventName? type,
}) => events.where((event) =>
    (clientId == null || event.clientId == clientId) &&
    (sessionId == null || event.sessionId == sessionId) &&
    (type == null || event.type == type));
```

- [ ] **Step 6: Run the full Dart test suite**

Run: `dart format lib test && flutter test && flutter analyze`

Expected: PASS with no static-analysis findings.

- [ ] **Step 7: Commit the usable Dart API**

```bash
git add lib test/meshstream_client_test.dart test/events_test.dart
git commit -m "feat: add MeshStream Dart client and sessions"
```

### Task 5: Implement and test the Android native adapter

**Files:**
- Modify: `android/build.gradle`, `android/src/main/AndroidManifest.xml`
- Create: `android/src/main/kotlin/net/meshstream/flutter/MeshStreamP2PPlugin.kt`, `android/src/main/kotlin/net/meshstream/flutter/MeshStreamHostApi.kt`
- Test: `android/src/test/kotlin/net/meshstream/flutter/MeshStreamHostApiTest.kt`

**Interfaces:**
- Consumes: generated Kotlin `MeshStreamHostApi`, Pigeon API types, and the MeshStream Android SDK.
- Produces: Pigeon callbacks and EventChannel events matching the Task 2 Dart contract.

- [ ] **Step 1: Write Android mapper/lifecycle tests with fake native client/session interfaces**

Test that a fake native session produces `ApiSessionReply` with `NATIVE_P2P`, that a native CDN session includes the wire fallback reason, that closing `c1` closes only sessions belonging to `c1`, and that nine pre-registration events retain only the first eight for that native session.

- [ ] **Step 2: Run Android unit tests to verify they fail before the host API exists**

Run: `cd android && ./gradlew testDebugUnitTest --tests net.meshstream.flutter.MeshStreamHostApiTest`

Expected: FAIL because `MeshStreamHostApi` is undefined.

- [ ] **Step 3: Configure the Android plugin and MeshStream dependency**

Set namespace `net.meshstream.flutter`, `minSdk 24`, and add:

```gradle
repositories {
  mavenCentral()
  maven {
    url 'https://pub-61830e1369904d19af505ff74fd55ba4.r2.dev/maven'
    content { includeGroup('io.meshstream') }
  }
}

dependencies {
  implementation 'io.meshstream:meshstream-android-sdk:1.0.2'
}
```

Declare internet permission only if the underlying SDK documentation requires the host manifest declaration; otherwise document the host app requirement rather than adding a redundant permission.

- [ ] **Step 4: Implement Kotlin resource ownership and native-method mapping**

In `MeshStreamHostApi.kt`, store `ConcurrentHashMap<String, BridgeClient>`, where `BridgeClient` contains a `P2pClient`, `ConcurrentHashMap<String, PlaybackSession>`, and bounded pending-event map. Generate UUIDs for Flutter-visible client/session IDs. Map each Pigeon operation directly to the similarly named native SDK method. Use the same field mapping and ratio formulas as the verified RN Android bridge:

```kotlin
downloadOffloadRatio = if (httpDownloaded + p2pDownloaded == 0L) 0.0
  else p2pDownloaded.toDouble() / (httpDownloaded + p2pDownloaded)
```

Map every native `P2pUnavailableReason.name` to its identical Dart wire string. Report unknown/closed resources using `FlutterError("UNKNOWN_CLIENT", ...)` or `FlutterError("UNKNOWN_SESSION", ...)`; wrap native creation failures as `CREATE_CLIENT_FAILED` and `CREATE_SESSION_FAILED`.

- [ ] **Step 5: Implement Android EventChannel delivery and bounded buffering**

In `MeshStreamP2PPlugin.kt`, create `EventChannel(binding.binaryMessenger, "net.meshstream/meshstream_p2p/events")`. Retain the active sink only while Dart listens. Emit maps with `type`, `clientId`, `sessionId`, and the event's legal payload field. Deliver sink calls on `Handler(Looper.getMainLooper())`. Buffer unknown native-session events exactly as the global constraints require and flush in order immediately after the Flutter session map entry is created.

- [ ] **Step 6: Make plugin detach safe**

On `onDetachedFromEngine`, detach the Pigeon host API, clear the EventChannel handler and sink, close all native sessions, close all clients, and clear pending events. Every individual close must tolerate a concurrently closed resource.

- [ ] **Step 7: Run Android tests and plugin build**

Run: `cd android && ./gradlew testDebugUnitTest assembleDebug`

Expected: all JVM tests PASS and the plugin AAR compiles against API 24+.

- [ ] **Step 8: Commit Android support**

```bash
git add android
git commit -m "feat(android): bridge MeshStream native SDK"
```

### Task 6: Implement and test the iOS native adapter

**Files:**
- Modify: `ios/meshstream_p2p.podspec`
- Create: `ios/Classes/MeshStreamP2PPlugin.swift`, `ios/Classes/MeshStreamHostApi.swift`
- Test: `ios/Tests/MeshStreamHostApiTests.swift`

**Interfaces:**
- Consumes: generated Swift Pigeon types, Flutter plugin APIs, and MeshStreamKit.
- Produces: the same Pigeon replies and EventChannel payloads as the Android adapter.

- [ ] **Step 1: Write failing XCTest coverage for platform parity**

Using protocol-backed fake native client/session types, assert status/stats/diagnostics wire conversions match Android values, an unavailable native reason maps to its exact wire name, client `c1` cleanup does not close `c2`, and early events are bounded to eight then flushed FIFO once the Flutter session ID exists.

- [ ] **Step 2: Run XCTest to verify the host API is absent**

Run from `example/ios`: `pod install && xcodebuild -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test`

Expected: FAIL until the plugin bridge/test target is implemented. If the named simulator is unavailable, select an installed iOS simulator but retain the same iOS 13+ deployment baseline.

- [ ] **Step 3: Declare the exact CocoaPods dependency and iOS floor**

Set in `ios/meshstream_p2p.podspec`:

```ruby
s.platform = :ios, '13.0'
s.dependency 'Flutter'
s.dependency 'MeshStreamKit', '= 1.0.2'
s.swift_version = '5.0'
```

Keep the Flutter SDK's default pod helper and do not add an XCFramework path or private spec repository.

- [ ] **Step 4: Implement Swift client/session ownership and Pigeon host API**

`MeshStreamHostApi.swift` uses a serial dispatch queue for maps from Flutter UUID strings to `P2PClient` and from session UUID strings to `PlaybackSession`. Translate `P2PConfig`, `P2PPlaybackOptions`, status, statistics, diagnostics, modes, and all unavailable reasons to generated Pigeon classes using the same field semantics as Android. Create client/session IDs with `UUID().uuidString`.

For failures, return Pigeon `FlutterError` values with the same four resource/creation codes as Android. Treat CDN fallback as a successful `ApiSessionReply` containing `NATIVE_CDN` and optional fallback reason.

- [ ] **Step 5: Implement main-queue EventChannel and event buffering**

`MeshStreamP2PPlugin.swift` registers `FlutterEventChannel(name: "net.meshstream/meshstream_p2p/events", binaryMessenger: registrar.messenger())`. Retain the event sink in `onListen`, clear it in `onCancel`, and send event dictionaries via `DispatchQueue.main.async`. Buffer/flush/discard events according to the same eight-per-session/64-session rule used by Android.

- [ ] **Step 6: Implement engine-detach cleanup**

When `detachFromEngine` executes, unregister generated Pigeon APIs and event handler, close sessions before clients, clear maps and buffers, and release listeners. Ensure repeated `closeClient` or `closeSession` success paths are no-ops after the first close.

- [ ] **Step 7: Run iOS tests and compile validation**

Run: `cd example/ios && pod install && xcodebuild -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: CocoaPods resolves public `MeshStreamKit` 1.0.2 and the example/plugin compiles. Then run the XCTest command from Step 2 and expect PASS.

- [ ] **Step 8: Commit iOS support**

```bash
git add ios
git commit -m "feat(ios): bridge MeshStreamKit"
```

### Task 7: Build the example app and integration documentation

**Files:**
- Modify: `example/pubspec.yaml`, `example/lib/main.dart`, `example/android/settings.gradle`, `example/ios/Podfile`
- Create: `README.md`, `README.zh-CN.md`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`
- Test: `example/test/widget_test.dart`

**Interfaces:**
- Consumes: complete Dart API and both native bridges from Tasks 1-6.
- Produces: a reproducible integration reference that demonstrates correct session lifecycle and telemetry.

- [ ] **Step 1: Write a failing example widget test**

Test that the initial screen renders Key and source URL fields, a `Create session` button, and no player until a session has been created. Inject a fake facade/controller so the test has no real Key or network dependency.

- [ ] **Step 2: Run the widget test to verify it fails**

Run: `cd example && flutter test test/widget_test.dart`

Expected: FAIL because the example controller/UI does not yet exist.

- [ ] **Step 3: Implement the example lifecycle flow**

Use `video_player` and the local path dependency on `../`. The screen must:

1. accept a user-entered Key, source URL, optional content ID, and mime type;
2. call `MeshStream.create`, then `createPlaybackSession`;
3. pass `session.playbackUrl` into `VideoPlayerController.networkUrl`;
4. subscribe with `MeshStream.eventsFor(sessionId: session.sessionId)`;
5. display playback mode, peer count, P2P/CDN byte counts, fallback reason, and last diagnostics;
6. call `updateCurrentPositionMs`/`updateBufferedDurationMs` at a low rate from player state; and
7. dispose subscriptions, player controller, session, and client in that order.

Never prefill a production Key or a private URL. A placeholder must be a non-working instructional value such as `key_your_meshstream_key`.

- [ ] **Step 4: Document host integration precisely**

In both READMEs, include a compact snippet:

```dart
final client = await MeshStream.create(const MeshStreamConfig(key: 'key_your_meshstream_key'));
final session = await client.createPlaybackSession(
  const PlaybackSessionOptions(url: 'https://cdn.example.com/live/playlist.m3u8', contentId: 'live-channel-42'),
);
final controller = VideoPlayerController.networkUrl(Uri.parse(session.playbackUrl));
```

Document Android's Maven repository URL, iOS `pod install`, supported media types, session/client ownership, event names, CDN fallback behavior, and the fact that the package does not provide a player. Keep the Chinese README semantically equivalent to the English one.

- [ ] **Step 5: Add release artifacts**

Set `CHANGELOG.md` first entry to `## 1.0.0` and list Android/iOS support, typed Dart API, P2P/CDN fallback, events, diagnostics, and example app. Add the Apache-2.0 license text and a contribution guide requiring format/analyze/test/Android/iOS checks before PRs.

- [ ] **Step 6: Run example checks**

Run: `cd example && flutter pub get && flutter test && flutter analyze && flutter build apk --debug`

Expected: widget test PASS, analyzer clean, and Android debug APK builds. Run the iOS build command from Task 6 when on macOS with Xcode.

- [ ] **Step 7: Commit the example and documentation**

```bash
git add example README.md README.zh-CN.md CHANGELOG.md LICENSE CONTRIBUTING.md
git commit -m "docs: add Flutter integration guide and example"
```

### Task 8: Add CI and prove the package is publishable

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`, `README.zh-CN.md` only if publish dry-run reports package metadata/documentation faults

**Interfaces:**
- Consumes: all package/test/build artifacts from Tasks 1-7.
- Produces: repeatable CI validation and a verified pub.dev publication candidate.

- [ ] **Step 1: Write CI workflow assertions before configuring the workflow**

Add workflow checks that must be present: Dart/Flutter setup at 3.22+, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `cd android && ./gradlew testDebugUnitTest assembleDebug`, and macOS `cd example/ios && pod install && xcodebuild ... build`.

- [ ] **Step 2: Add `.github/workflows/ci.yml`**

Use two jobs: `dart-and-android` on `ubuntu-latest` and `ios` on `macos-latest`. Cache pub/Gradle/CocoaPods directories through setup actions. Generate Pigeon output in both jobs and fail when `git diff --exit-code` detects stale generated sources. The iOS job uses the project's deployment target and an installed simulator destination discovered by `xcrun simctl list devices available`.

- [ ] **Step 3: Execute all local release gates**

Run:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
cd android && ./gradlew testDebugUnitTest assembleDebug
cd ../example/ios && pod install
flutter pub publish --dry-run
```

Expected: every command exits zero. Treat `flutter pub publish --dry-run` warnings that affect score, license, README, CHANGELOG, or package files as release blockers and correct them before proceeding.

- [ ] **Step 4: Run real-device smoke tests**

On Android API 24+ and iOS 13+ devices with a valid platform Key and permitted public test stream, create two clients with one session each, start playback, verify one `playbackPrepared` event per session, close the first client, verify the second keeps playing, then close the second. Record OS/device/SDK version and result in the release checklist without committing the Key or stream URL.

- [ ] **Step 5: Commit CI and release readiness**

```bash
git add .github README.md README.zh-CN.md
git commit -m "ci: validate Flutter SDK release"
```

- [ ] **Step 6: Publish the approved release**

Run: `flutter pub publish`

Expected: pub.dev accepts `meshstream_p2p` version 1.0.0. Create a GitHub tag `v1.0.0` and release after the publish succeeds; do not tag or publish if dry-run/build/device gates fail.

## Plan Self-Review

- Spec coverage: Tasks 1-4 implement the single package, Dart contract, Pigeon/EventChannel split, lifecycle, error behavior, filtering, and no-player requirement. Tasks 5-6 implement Android/iOS dependencies, mapping, main-thread events, bounded event buffering, and cleanup. Task 7 covers example/documentation. Task 8 covers CI, pub dry-run, real devices, and release.
- Placeholder scan: no deferred implementation markers are present; the only future-looking statements are explicit ordered execution steps.
- Type consistency: public operation names and return types match the plan's Task 2 models, Task 3 platform interface, Task 4 facade, and Android/iOS host methods.
