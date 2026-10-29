import Flutter
import MeshStreamKit
import UIKit
import XCTest
@testable import meshstream_p2p

final class MeshStreamHostApiTests: XCTestCase {
  private func result<T>(_ call: (@escaping (Result<T, Error>) -> Void) -> Void) throws -> T {
    let ready = expectation(description: "Pigeon completion")
    var value: Result<T, Error>?
    call { value = $0; ready.fulfill() }
    wait(for: [ready], timeout: 3)
    return try XCTUnwrap(value).get()
  }
  private func client(_ api: MeshStreamHostApiImpl) throws -> String {
    try result { api.createClient(config: ApiClientConfig(key: "test-key"), completion: $0) }.clientId
  }
  private func session(_ api: MeshStreamHostApiImpl, _ clientId: String) throws -> ApiSessionReply {
    try result { api.createPlaybackSession(clientId: clientId,
      options: ApiPlaybackSessionOptions(url: "https://media.example/video.m3u8"), completion: $0) }
  }

  func testRealSdkClientCanInitializeAndReadStatusWithoutCreatingPlayback() throws {
    // SDK documentation guarantees client creation is local; bootstrap/network
    // begins only with playback. Exercise the real public binary's Swift ABI.
    let native = try MeshStreamSdkClient.create(ApiClientConfig(key: "flutter-adapter-test", p2pEnabled: false))
    XCTAssertFalse(native.status.effectiveP2PEnabled)
    native.eventHandler = { _, _ in XCTFail("A client without playback cannot emit session events") }
    native.eventHandler = nil
    native.close()
  }

  func testRegistrationAndEngineDetachRemoveAllChannelsAndOwnedResources() throws {
    let registrar = FakeRegistrar()
    MeshStreamP2PPlugin.register(with: registrar)
    let registered = try XCTUnwrap(registrar.published as? MeshStreamP2PPlugin)
    XCTAssertEqual(registrar.binaryMessenger.handlers.count, 12)
    XCTAssertNotNil(registrar.binaryMessenger.handlers["net.meshstream/meshstream_p2p/events"])
    XCTAssertNotNil(registrar.binaryMessenger.handlers["dev.flutter.pigeon.meshstream_p2p.MeshStreamHostApi.createClient"])
    registered.detachFromEngine(for: registrar)
    registered.detachFromEngine(for: registrar)
    XCTAssertTrue(registrar.binaryMessenger.handlers.isEmpty)

    let native = FakeClient()
    var order: [String] = []
    native.nextSession.onClose = { order.append("session") }
    native.onClose = { order.append("client") }
    let plugin = MeshStreamP2PPlugin(createNativeClient: { _ in native })
    let id = try client(plugin.hostApi)
    _ = try session(plugin.hostApi, id)
    plugin.detachFromEngine(for: registrar)
    plugin.detachFromEngine(for: registrar)
    XCTAssertEqual(order, ["session", "client"])
    XCTAssertNil(native.eventHandler)
    XCTAssertThrowsError(try result { plugin.hostApi.getStatus(clientId: id, completion: $0) }) {
      XCTAssertEqual(($0 as? PigeonError)?.code, "UNKNOWN_CLIENT")
    }
  }

  func testStatusReasonsAndOptionalFieldsUseExactWireValues() throws {
    let expected = ["OK", "NO_PEERS", "TRACKER_ERROR", "AUTH_FAILED", "ACCOUNT_DISABLED",
      "APP_DISABLED", "APP_NOT_FOUND", "KEY_DISABLED", "PLATFORM_DISABLED", "ORIGIN_DENIED",
      "PACKAGE_DENIED", "BUNDLE_DENIED", "SIGNING_CERT_DENIED", "TEAM_DENIED", "CONFIG_UNAVAILABLE",
      "INITIALIZATION_FAILED", "UNSUPPORTED", "DISABLED", "KEY_P2P_DISABLED", "QUOTA_EXHAUSTED", "QUOTA_DISABLED"]
    for (raw, wire) in expected.enumerated() {
      let status = MeshStreamStatusSnapshot(accountEnabled: true, applicationEnabled: false, keyEnabled: true,
        platformEnabled: true, effectiveP2PEnabled: false, reason: P2PUnavailableReason(rawValue: raw)!,
        configVersion: "v7", edgeRegion: "ap-east", quotaStatus: "exhausted")
      let native = FakeClient(status: status)
      let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { _ in })
      let id = try client(api)
      let actual = try result { api.getStatus(clientId: id, completion: $0) }
      XCTAssertEqual(actual.reason, wire)
      XCTAssertTrue(actual.accountEnabled)
      XCTAssertFalse(actual.applicationEnabled)
      XCTAssertTrue(actual.keyEnabled)
      XCTAssertTrue(actual.platformEnabled)
      XCTAssertFalse(actual.effectiveP2pEnabled)
      XCTAssertEqual(actual.configVersion, "v7")
      XCTAssertEqual(actual.edgeRegion, "ap-east")
      XCTAssertEqual(actual.quotaStatus, "exhausted")
      XCTAssertNil(actual.trackerPoolReady)
      api.close()
    }
    XCTAssertEqual(MeshStreamWire.reason(P2PUnavailableReason(rawValue: 999)!), "INITIALIZATION_FAILED")
  }

  func testStatsPreserveInt64CountersAndCalculateRatiosWithoutOverflow() throws {
    let native = FakeClient()
    native.nextSession.stats.setValuesForKeys(["httpDownloaded": Int64.max, "p2pDownloaded": Int64.max,
      "p2pUploaded": 9_007_199_254_740_993, "httpSegmentDownloadSuccesses": 11,
      "httpSegmentDownloadFailures": 12, "p2pSegmentDownloadSuccesses": 3,
      "p2pSegmentDownloadFailures": 1, "p2pSegmentUploadSuccesses": 1,
      "p2pSegmentUploadFailures": 3, "connectedPeers": 4, "peerConnectErrors": 13, "trackerErrors": 14])
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { _ in })
    let id = try client(api), reply = try session(api, id)
    let stats = try result { api.getStats(clientId: id, sessionId: reply.sessionId, completion: $0) }
    XCTAssertEqual(stats.httpDownloaded, Int64.max)
    XCTAssertEqual(stats.p2pDownloaded, Int64.max)
    XCTAssertEqual(stats.p2pUploaded, 9_007_199_254_740_993)
    XCTAssertEqual(stats.httpSegmentDownloadSuccesses, 11)
    XCTAssertEqual(stats.httpSegmentDownloadFailures, 12)
    XCTAssertEqual(stats.p2pSegmentDownloadSuccesses, 3)
    XCTAssertEqual(stats.p2pSegmentDownloadFailures, 1)
    XCTAssertEqual(stats.p2pSegmentUploadSuccesses, 1)
    XCTAssertEqual(stats.p2pSegmentUploadFailures, 3)
    XCTAssertEqual(stats.connectedPeers, 4)
    XCTAssertEqual(stats.peerConnectErrors, 13)
    XCTAssertEqual(stats.trackerErrors, 14)
    XCTAssertEqual(stats.downloadOffloadRatio, 0.5)
    XCTAssertEqual(stats.p2pSegmentDownloadSuccessRatio, 0.75)
    XCTAssertEqual(stats.p2pSegmentUploadSuccessRatio, 0.25)
    let empty = MeshStreamWire.stats(P2PStats())
    XCTAssertEqual(empty.downloadOffloadRatio, 0)
    XCTAssertEqual(empty.p2pSegmentDownloadSuccessRatio, 0)
    XCTAssertEqual(empty.p2pSegmentUploadSuccessRatio, 0)
    api.close()
  }

  func testDiagnosticsMapAbsentAndPresentSnapshots() throws {
    let empty = MeshStreamWire.diagnostics(MeshStreamDiagnosticsSnapshot())
    XCTAssertNil(empty.firstPeerConnectMs)
    XCTAssertNil(empty.coldStart)
    XCTAssertNil(empty.lastErrorAtMs)
    let source = MeshStreamDiagnosticsSnapshot(fallbackCount: 2, firstPeerConnectMs: 31, coldStartP2PDownloaded: 42,
      coldStartHTTPDownloaded: 43, lastTrackerError: "tracker", lastPeerError: "peer",
      lastErrorAtMs: 1234, iceAttempts: 7, iceSuccesses: 5, iceFailures: 2, iceDurationMs: 81)
    let native = FakeClient()
    native.nextSession.diagnosticsSnapshot = source
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { _ in })
    let id = try client(api), reply = try session(api, id)
    let value = try result { api.getDiagnostics(clientId: id, sessionId: reply.sessionId, completion: $0) }
    XCTAssertEqual(value.fallbackCount, 2)
    XCTAssertEqual(value.firstPeerConnectMs, 31)
    XCTAssertEqual(value.coldStart?.p2pDownloaded, 42)
    XCTAssertEqual(value.coldStart?.httpDownloaded, 43)
    XCTAssertEqual(value.lastTrackerError, "tracker")
    XCTAssertEqual(value.lastPeerError, "peer")
    XCTAssertEqual(value.lastErrorAtMs, 1234)
    XCTAssertEqual(value.iceAttempts, 7)
    XCTAssertEqual(value.iceSuccesses, 5)
    XCTAssertEqual(value.iceFailures, 2)
    XCTAssertEqual(value.iceDurationMs, 81)
    api.close()
  }

  func testColdStartSnapshotPreservesZeroTrafficAfterFirstPeerConnection() throws {
    let native = FakeClient()
    native.nextSession.diagnosticsSnapshot = MeshStreamDiagnosticsSnapshot(firstPeerConnectMs: 31)
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { _ in })
    defer { api.close() }
    let id = try client(api), reply = try session(api, id)
    let value = try result { api.getDiagnostics(clientId: id, sessionId: reply.sessionId, completion: $0) }
    XCTAssertEqual(value.firstPeerConnectMs, 31)
    let coldStart = try XCTUnwrap(value.coldStart)
    XCTAssertEqual(coldStart.p2pDownloaded, 0)
    XCTAssertEqual(coldStart.httpDownloaded, 0)
  }

  func testColdStartSnapshotIsAbsentWithoutFirstPeerConnection() {
    let value = MeshStreamWire.diagnostics(MeshStreamDiagnosticsSnapshot(
      coldStartP2PDownloaded: 42, coldStartHTTPDownloaded: 43))
    XCTAssertNil(value.firstPeerConnectMs)
    XCTAssertNil(value.coldStart)
  }

  func testClosingOneClientPreservesOtherClientAndClosesOwnedSessionsFirst() throws {
    var order: [String] = []
    let first = FakeClient(), second = FakeClient()
    first.nextSession.onClose = { order.append("session") }
    first.onClose = { order.append("client") }
    var next = [first, second]
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in next.removeFirst() }, emitEvent: { _ in })
    let c1 = try client(api), c2 = try client(api)
    _ = try session(api, c1)
    let s2 = try session(api, c2)
    try result { api.closeClient(clientId: c1, completion: $0) }
    try result { api.closeClient(clientId: c1, completion: $0) }
    XCTAssertEqual(order, ["session", "client"])
    XCTAssertNil(first.eventHandler)
    XCTAssertEqual(first.closeCount, 1)
    XCTAssertTrue(try result { api.preload(clientId: c2, sessionId: s2.sessionId, completion: $0) })
    XCTAssertEqual(second.closeCount, 0)
    api.close(); api.close()
    XCTAssertEqual(second.closeCount, 1)
    XCTAssertEqual(second.nextSession.closeCount, 1)
  }

  func testEarlyEventsKeepFirstEightAndFlushFIFOWithFlutterIdentity() throws {
    let native = FakeClient()
    var events: [[String: Any]] = []
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { events.append($0) })
    native.onCreate = {
      for count in 0..<10 { native.eventHandler?("native-1", ["type": "peerCountChanged", "peerCount": count]) }
    }
    let id = try client(api), reply = try session(api, id)
    XCTAssertEqual(events.compactMap { $0["peerCount"] as? Int }, Array(0..<8))
    XCTAssertTrue(events.allSatisfy { $0["clientId"] as? String == id && $0["sessionId"] as? String == reply.sessionId })
    XCTAssertNotEqual(reply.sessionId, "native-1")
    XCTAssertEqual(reply.playbackMode, "NATIVE_CDN")
    XCTAssertEqual(reply.fallbackReason, "CONFIG_UNAVAILABLE")
    api.close()
  }

  func testPendingEventsHave64SessionBoundAndClosedSessionsNeverRevive() throws {
    let native = FakeClient()
    var events: [[String: Any]] = []
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { events.append($0) })
    let id = try client(api)
    native.onCreate = {
      for number in 0..<65 { native.eventHandler?("pending-\(number)", ["type": "p2pReady"]) }
    }
    native.nextSession.nativeSessionId = "pending-64"
    _ = try session(api, id)
    XCTAssertTrue(events.isEmpty)
    native.onCreate = nil
    native.nextSession = FakeSession("pending-0")
    let reply = try session(api, id)
    XCTAssertEqual(events.count, 1)
    XCTAssertTrue(api.isSessionActive(events[0]))
    try result { api.closeSession(clientId: id, sessionId: reply.sessionId, completion: $0) }
    try result { api.closeSession(clientId: id, sessionId: reply.sessionId, completion: $0) }
    XCTAssertEqual(native.nextSession.closeCount, 1)
    XCTAssertFalse(api.isSessionActive(events[0]))
    native.eventHandler?("pending-0", ["type": "p2pReady"])
    _ = try result { api.getStatus(clientId: id, completion: $0) }
    XCTAssertEqual(events.count, 1)
    api.close()
  }

  func testOptionsAndSessionCommandsForwardAndClampNegativeTime() throws {
    let native = FakeClient()
    var seenConfig: ApiClientConfig?
    let api = MeshStreamHostApiImpl(createNativeClient: { seenConfig = $0; return native }, emitEvent: { _ in })
    let id = try result { api.createClient(config: ApiClientConfig(key: "k", p2pEnabled: false), completion: $0) }.clientId
    let reply = try result { api.createPlaybackSession(clientId: id, options: ApiPlaybackSessionOptions(
      url: "https://media.example/v.mpd", contentId: "asset", mimeType: "mpd", originHeaders: ["Authorization": "secret"]), completion: $0) }
    XCTAssertEqual(seenConfig?.key, "k")
    XCTAssertEqual(seenConfig?.p2pEnabled, false)
    XCTAssertEqual(native.seenURL?.absoluteString, "https://media.example/v.mpd")
    XCTAssertEqual(native.seenOptions?.contentId, "asset")
    XCTAssertEqual(native.seenOptions?.mimeType, "mpd")
    XCTAssertEqual(native.seenOptions?.originHeaders, ["Authorization": "secret"])
    try result { api.setP2pEnabled(clientId: id, sessionId: reply.sessionId, enabled: false, completion: $0) }
    try result { api.updateBufferedDurationMs(clientId: id, sessionId: reply.sessionId, durationMs: -1, completion: $0) }
    try result { api.updateCurrentPositionMs(clientId: id, sessionId: reply.sessionId, positionMs: Int64.max, completion: $0) }
    XCTAssertEqual(native.nextSession.enabled, false)
    XCTAssertEqual(native.nextSession.buffered, 0)
    XCTAssertEqual(native.nextSession.position, Int64.max)
    api.close()
  }

  func testMissingResourcesAndCreationFailuresUsePigeonErrorCodes() throws {
    let native = FakeClient()
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in native }, emitEvent: { _ in })
    let id = try client(api)
    func code<T>(_ expected: String, _ call: (@escaping (Result<T, Error>) -> Void) -> Void) {
      XCTAssertThrowsError(try result(call)) { XCTAssertEqual(($0 as? PigeonError)?.code, expected) }
    }
    code("UNKNOWN_CLIENT") { api.getStatus(clientId: "missing", completion: $0) }
    code("UNKNOWN_SESSION") { api.preload(clientId: id, sessionId: "missing", completion: $0) }
    code("CREATE_SESSION_FAILED") { api.createPlaybackSession(clientId: id, options: ApiPlaybackSessionOptions(url: "file:///tmp/movie"), completion: $0) }
    native.creationError = NSError(domain: "test", code: 1)
    code("CREATE_SESSION_FAILED") { api.createPlaybackSession(clientId: id, options: ApiPlaybackSessionOptions(url: "https://example.com/v"), completion: $0) }
    api.close()
    code("CREATE_CLIENT_FAILED") { api.createClient(config: ApiClientConfig(key: "k"), completion: $0) }
    let failing = MeshStreamHostApiImpl(createNativeClient: { _ in throw NSError(domain: "test", code: 2) }, emitEvent: { _ in })
    code("CREATE_CLIENT_FAILED") { failing.createClient(config: ApiClientConfig(key: "k"), completion: $0) }
  }

  func testPluginDeliversOnMainAndDropsQueuedEventsAfterCancelOrClose() throws {
    let native = FakeClient()
    let plugin = MeshStreamP2PPlugin(createNativeClient: { _ in native })
    let id = try client(plugin.hostApi), reply = try session(plugin.hostApi, id)
    let delivered = expectation(description: "main queue event")
    _ = plugin.onListen(withArguments: nil) { event in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual((event as? [String: Any])?["type"] as? String, "p2pReady")
      delivered.fulfill()
    }
    DispatchQueue.global().async { native.eventHandler?("native-1", ["type": "p2pReady"]) }
    wait(for: [delivered], timeout: 3)
    let unwanted = expectation(description: "cancelled/closed event")
    unwanted.isInverted = true
    _ = plugin.onListen(withArguments: nil) { _ in unwanted.fulfill() }
    native.eventHandler?("native-1", ["type": "p2pReady"])
    _ = plugin.onCancel(withArguments: nil)
    _ = plugin.onListen(withArguments: nil) { _ in unwanted.fulfill() }
    wait(for: [unwanted], timeout: 0.1)
    let closed = expectation(description: "closed session event")
    closed.isInverted = true
    _ = plugin.onListen(withArguments: nil) { _ in closed.fulfill() }
    native.eventHandler?("native-1", ["type": "p2pReady"])
    plugin.hostApi.close()
    wait(for: [closed], timeout: 0.1)
    XCTAssertFalse(plugin.hostApi.isSessionActive(["clientId": id, "sessionId": reply.sessionId]))
  }

  func testNativeListenerImplementsEverySessionSelectorAndEmitsStandardMaps() throws {
    let listener = MeshStreamSdkListener()
    let callbacks: P2PEventListener = listener
    var events: [[String: Any]] = []
    listener.handler = { id, event in
      XCTAssertEqual(id, "native")
      events.append(event)
    }
    let selectors = ["onPlaybackPreparedWithSessionId:playbackUrl:", "onStatisticsWithSessionId:stats:",
      "onPeerCountChangedWithSessionId:peerCount:", "onP2PReadyWithSessionId:",
      "onP2PUnavailableWithSessionId:reason:", "onCdnFallbackWithSessionId:bytes:",
      "onTrackerErrorWithSessionId:totalErrors:", "onPeerConnectErrorWithSessionId:totalErrors:"]
    for name in selectors { XCTAssertTrue(listener.responds(to: NSSelectorFromString(name)), name) }
    callbacks.onPlaybackPrepared?(withSessionId: "native", playbackUrl: URL(string: "http://127.0.0.1/video")!)
    callbacks.onStatistics?(withSessionId: "native", stats: P2PStats())
    callbacks.onPeerCountChanged?(withSessionId: "native", peerCount: 7)
    callbacks.onP2PReady?(withSessionId: "native")
    callbacks.onP2PUnavailable?(withSessionId: "native", reason: .quotaDisabled)
    callbacks.onCdnFallback?(withSessionId: "native", bytes: 9_007_199_254_740_993)
    callbacks.onTrackerError?(withSessionId: "native", totalErrors: 8)
    callbacks.onPeerConnectError?(withSessionId: "native", totalErrors: 9)
    XCTAssertEqual(events.compactMap { $0["type"] as? String }, ["playbackPrepared", "statistics",
      "peerCountChanged", "p2pReady", "p2pUnavailable", "cdnFallback", "trackerError", "peerConnectError"])
    XCTAssertEqual(events[0]["playbackUrl"] as? String, "http://127.0.0.1/video")
    XCTAssertEqual((events[1]["statistics"] as? [String: Any])?.count, 15)
    XCTAssertEqual(events[2]["peerCount"] as? Int, 7)
    XCTAssertEqual(events[4]["reason"] as? String, "QUOTA_DISABLED")
    XCTAssertEqual(events[5]["bytes"] as? Int64, 9_007_199_254_740_993)
    XCTAssertEqual(events[6]["totalErrors"] as? Int64, 8)
    XCTAssertEqual(events[7]["totalErrors"] as? Int64, 9)
    for event in events {
      XCTAssertNotNil(FlutterStandardMessageCodec.sharedInstance().encode(event))
    }
    listener.handler = nil
    callbacks.onP2PReady?(withSessionId: "native")
    XCTAssertEqual(events.count, 8)
  }

  func testP2PSessionHasNoFallbackAndOwnerMustMatch() throws {
    let native = FakeClient()
    native.nextSession.playbackMode = .nativeP2P
    native.nextSession.fallbackReason = nil
    var clients = [native, FakeClient()]
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in clients.removeFirst() }, emitEvent: { _ in })
    let id = try client(api), reply = try session(api, id)
    XCTAssertEqual(reply.playbackMode, "NATIVE_P2P")
    XCTAssertNil(reply.fallbackReason)
    let otherId = try client(api)
    XCTAssertThrowsError(try result { api.preload(clientId: otherId, sessionId: reply.sessionId, completion: $0) }) {
      XCTAssertEqual(($0 as? PigeonError)?.code, "UNKNOWN_SESSION")
    }
    try result { api.closeSession(clientId: otherId, sessionId: reply.sessionId, completion: $0) }
    XCTAssertEqual(native.nextSession.closeCount, 0)
    XCTAssertTrue(try result { api.preload(clientId: id, sessionId: reply.sessionId, completion: $0) })
    api.close()
  }

  func testIdenticalNativeSessionIdsAreScopedToTheirOwningClient() throws {
    let first = FakeClient(), second = FakeClient()
    var clients = [first, second]
    var events: [[String: Any]] = []
    let api = MeshStreamHostApiImpl(createNativeClient: { _ in clients.removeFirst() }, emitEvent: { events.append($0) })
    let c1 = try client(api), c2 = try client(api)
    let s1 = try session(api, c1), s2 = try session(api, c2)
    let lateCallback = first.eventHandler
    first.eventHandler?("native-1", ["type": "peerCountChanged", "peerCount": 1])
    second.eventHandler?("native-1", ["type": "peerCountChanged", "peerCount": 2])
    XCTAssertEqual(events[0]["sessionId"] as? String, s1.sessionId)
    XCTAssertEqual(events[0]["clientId"] as? String, c1)
    XCTAssertEqual(events[1]["sessionId"] as? String, s2.sessionId)
    XCTAssertEqual(events[1]["clientId"] as? String, c2)
    try result { api.closeClient(clientId: c1, completion: $0) }
    lateCallback?("native-1", ["type": "p2pReady"])
    second.eventHandler?("native-1", ["type": "p2pReady"])
    XCTAssertEqual(events.count, 3)
    XCTAssertEqual(events.last?["clientId"] as? String, c2)
    api.close()
  }
}

private final class FakeMessenger: NSObject, FlutterBinaryMessenger {
  var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private var nextConnection: Int64 = 0
  private var channels: [Int64: String] = [:]
  private var latestConnections: [String: Int64] = [:]
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    nextConnection += 1
    channels[nextConnection] = channel
    latestConnections[channel] = nextConnection
    return nextConnection
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    guard let channel = channels.removeValue(forKey: connection), latestConnections[channel] == connection else { return }
    handlers.removeValue(forKey: channel)
    latestConnections.removeValue(forKey: channel)
  }
}

private final class FakeRegistrar: NSObject, FlutterPluginRegistrar {
  let binaryMessenger = FakeMessenger()
  var published: NSObject?
  var viewController: UIViewController? { nil }
  func messenger() -> FlutterBinaryMessenger { binaryMessenger }
  func textures() -> FlutterTextureRegistry { fatalError("Textures are outside this plugin's contract") }
  func publish(_ value: NSObject) { published = value }
  func valuePublished(byPlugin pluginKey: String) -> NSObject? { published }
  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String) {}
  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String,
    gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy) {}
  func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) {}
  func addApplicationDelegate(_ delegate: FlutterPlugin) {}
  func addSceneDelegate(_ delegate: FlutterSceneLifeCycleDelegate) {}
  func lookupKey(forAsset asset: String) -> String { asset }
  func lookupKey(forAsset asset: String, fromPackage package: String) -> String { asset }
}

private final class FakeClient: MeshStreamNativeClient {
  var status: MeshStreamStatusSnapshot
  var eventHandler: ((String, [String: Any]) -> Void)?
  var nextSession = FakeSession("native-1")
  var seenURL: URL?
  var seenOptions: P2PPlaybackOptions?
  var onCreate: (() -> Void)?
  var onClose: (() -> Void)?
  var closeCount = 0
  var creationError: Error?
  init(status: MeshStreamStatusSnapshot = MeshStreamStatusSnapshot()) { self.status = status }
  func createPlaybackSession(url: URL, options: P2PPlaybackOptions) throws -> MeshStreamNativeSession {
    if let error = creationError { throw error }
    seenURL = url; seenOptions = options
    onCreate?()
    return nextSession
  }
  func close() { closeCount += 1; onClose?() }
}

private final class FakeSession: MeshStreamNativeSession {
  var nativeSessionId: String
  let playbackURL = URL(string: "http://127.0.0.1:8080/media")!
  var playbackMode = P2PPlaybackMode.nativeCDN
  var fallbackReason: P2PUnavailableReason? = .configUnavailable
  var stats = P2PStats()
  var diagnosticsSnapshot = MeshStreamDiagnosticsSnapshot()
  var enabled: Bool?
  var buffered: Int64?
  var position: Int64?
  var onClose: (() -> Void)?
  var closeCount = 0
  init(_ nativeSessionId: String) { self.nativeSessionId = nativeSessionId }
  func preload() -> Bool { true }
  func setP2pEnabled(_ value: Bool) { enabled = value }
  func updateBufferedDurationMs(_ value: Int64) { buffered = value }
  func updateCurrentPositionMs(_ value: Int64) { position = value }
  func close() { closeCount += 1; onClose?() }
}
